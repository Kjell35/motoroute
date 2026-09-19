import { Injectable, Logger, OnModuleDestroy, OnModuleInit } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { EventEmitter2 } from '@nestjs/event-emitter';
import { io, Socket } from 'socket.io-client';

/**
 * Kanonische Event-Namen (Spiegel zu GroupRouteEvent / ChatEvent).
 * - BATCH geht an App-Sockets (bündelt mehrere POI-Änderungen in EINEM
 *   Frame - nach dem täglichen Scan kommen sonst hunderte Einzel-Pushes).
 * - UPSTREAM_* sind die Socket.IO-Events des eigenständigen Dienstes.
 * - RIDE_* sind das Ride-Relais (Live-Gruppenfahrt) über denselben
 *   Dienst: Das BFF spielt verifizierte Beats ein und empfängt die
 *   Routen-Mitgliederliste zurück - NUR das BFF hat das Relay-Secret.
 */
export const BikerPoiRealtimeEvent = {
  BATCH: 'bikerpoi.batch',
  UPSTREAM_UPSERT: 'poi:upsert',
  UPSTREAM_DELETE: 'poi:delete',
  RIDE_POSITION_UPDATE: 'groupride.radar',
  RIDE_POSITION_LEAVE: 'groupride.radar_leave',
  UPSTREAM_RIDE_UPDATE: 'ride_position_update',
  UPSTREAM_RIDE_LEAVE: 'ride_position_leave',
} as const;

export interface BikerPoiChange {
  /** DIENST-ID (ohne biker-Präfix) - gemappt via mapBikerPoiRow. */
  id: string;
  action: 'upsert' | 'delete';
}

/** Mitglied-Position aus dem Relais (Dienst -> BFF). */
export interface RideRelayMember {
  userId: string;
  lat: number;
  lng: number;
  lastSeen: string | Date;
}

export interface RideRelayUpdate {
  routeId: string;
  members: RideRelayMember[];
}

/** Sekunden, die gesammelt wird, bevor ein Batch ausgelöst wird. */
export const BATCH_WINDOW_MS = 5_000;
/** Sicherheitsnetz: nicht ewig sammeln, wenn permanent Änderungen kommen. */
export const BATCH_MAX_AGE_MS = 30_000;

/**
 * BikerPoisRealtimeBridge - verbindet das BFF mit dem Socket.IO-Server des
 * Biker-POI-Dienstes: (a) POI-Push (Koaleszierung), (b) Ride-Relais der
 * Live-Gruppenfahrt.
 *
 * Ride-Relais-Sicherheitsmodell: Das BFF ist DER eine Relay-Client. Ein
 * ride_position-Frame wird nur NACH erfolgreicher Membership-Prüfung
 * (Supabase-RLS, rideRadarGuard im GroupRidesService) abgesendet - der
 * POI-Dienst vertraut dem Secret, das Secret verlässt nie das BFF. Die
 * zurückkommenden Positionen werden nur an App-Sockets im Raum
 * ride:<routeId> verteilt (ChatGateway.broadcastToRide) - nie global.
 */
@Injectable()
export class BikerPoisRealtimeBridge implements OnModuleInit, OnModuleDestroy {
  private readonly logger = new Logger(BikerPoisRealtimeBridge.name);
  private readonly baseUrl: string;
  private readonly relaySecret: string;
  private socket: Socket | null = null;
  private reconnectTimer: NodeJS.Timeout | null = null;
  private disposed = false;

  /** Gesammelte Änderungen (Dienst-ID -> action) im offenen Batch-Fenster. */
  private pending = new Map<string, 'upsert' | 'delete'>();
  private batchTimer: NodeJS.Timeout | null = null;
  private firstChangeAt: number | null = null;

  constructor(config: ConfigService, private readonly events: EventEmitter2) {
    this.baseUrl = (config.get<string>('BIKER_POI_SERVICE_URL') ?? '').replace(/\/$/, '');
    this.relaySecret = config.get<string>('RIDE_RELAY_SECRET') ?? '';
  }

  get configured(): boolean {
    return this.baseUrl.length > 0;
  }

  onModuleInit(): void {
    if (!this.configured) {
      this.logger.warn(
        'BIKER_POI_SERVICE_URL nicht gesetzt - kein Push für kuratierte POIs (Delta-Sync bleibt verfügbar).',
      );
      return;
    }
    this.connect();
  }

  onModuleDestroy(): void {
    this.disposed = true;
    this.batchTimer && clearTimeout(this.batchTimer);
    this.reconnectTimer && clearTimeout(this.reconnectTimer);
    this.socket?.disconnect();
  }

  private connect(): void {
    if (this.disposed) return;
    try {
      this.socket = io(this.baseUrl, {
        transports: ['websocket'],
        reconnection: true,
        reconnectionAttempts: Infinity,
        reconnectionDelay: 2000,
        reconnectionDelayMax: 30_000,
        timeout: 5000,
        auth: this.relaySecret ? { relaySecret: this.relaySecret } : undefined,
      });

      this.socket.on('connect', () => {
        this.logger.log(`Biker-POI-Dienst verbunden (${this.baseUrl})`);
      });
      this.socket.on('disconnect', (reason: string) => {
        this.logger.warn(`Biker-POI-Dienst getrennt: ${reason} - socket.io reconnectet automatisch`);
      });
      this.socket.on('connect_error', (err: Error) => {
        // Bewusst nur debug: der Dienst ist optional, Fehler seria-
        // lisieren sonst das Log bei jedem Reconnect-Versuch.
        this.logger.debug(`Biker-POI-Dienst nicht erreichbar: ${err.message}`);
      });

      this.socket.on(BikerPoiRealtimeEvent.UPSTREAM_UPSERT, (poi: unknown) => {
        this.handleUpstream(poi, 'upsert');
      });
      this.socket.on(BikerPoiRealtimeEvent.UPSTREAM_DELETE, (poi: unknown) => {
        this.handleUpstream(poi, 'delete');
      });
      this.socket.on(BikerPoiRealtimeEvent.UPSTREAM_RIDE_UPDATE, (payload: RideRelayUpdate) => {
        if (payload && typeof payload.routeId === 'string' && Array.isArray(payload.members)) {
          this.events.emit(BikerPoiRealtimeEvent.RIDE_POSITION_UPDATE, payload);
        }
      });
      this.socket.on(BikerPoiRealtimeEvent.UPSTREAM_RIDE_LEAVE, (payload: { routeId?: string; userId?: string }) => {
        if (payload && typeof payload.routeId === 'string' && typeof payload.userId === 'string') {
          this.events.emit(BikerPoiRealtimeEvent.RIDE_POSITION_LEAVE, {
            routeId: payload.routeId,
            userId: payload.userId,
          });
        }
      });
    } catch (err) {
      this.logger.warn(`Biker-POI-Dienst-Verbindung fehlgeschlagen: ${String(err)}`);
      this.scheduleReconnect();
    }
  }

  private scheduleReconnect(): void {
    if (this.disposed || this.reconnectTimer) return;
    this.reconnectTimer = setTimeout(() => {
      this.reconnectTimer = null;
      this.connect();
    }, 10_000);
  }

  /**
   * Ride-Relais: verifizierten Beat einspeisen. Liefert die aktuelle
   * Mitgliederliste (oder null, wenn das Relais nicht erreichbar war -
   * der REST-/Polling-Pfad bleibt dann die Wahrheit).
   */
  async pushRidePosition(frame: {
    routeId: string;
    userId: string;
    lat: number;
    lng: number;
  }): Promise<RideRelayUpdate | null> {
    if (!this.configured || !this.relaySecret || !this.socket || this.socket.connected !== true) {
      return null;
    }
    return new Promise((resolve) => {
      const timer = setTimeout(() => resolve(null), 3000);
      this.socket!.emit(
        'ride_position',
        { secret: this.relaySecret, ...frame },
        (res: { ok: boolean; members?: RideRelayMember[] }) => {
          clearTimeout(timer);
          resolve(res?.ok ? { routeId: frame.routeId, members: res.members ?? [] } : null);
        },
      );
    });
  }

  /** Ride-Relais: Fahrer aus der Route entfernen (Freigabe aus). */
  async leaveRide(routeId: string, userId: string): Promise<void> {
    if (!this.configured || !this.relaySecret || !this.socket || this.socket.connected !== true) {
      return;
    }
    return new Promise((resolve) => {
      const timer = setTimeout(() => resolve(), 3000);
      this.socket!.emit('leave_ride', { secret: this.relaySecret, routeId, userId }, () => {
        clearTimeout(timer);
        resolve();
      });
    });
  }

  /**
   * Öffentlich (statt privat), damit der Pfad ohne echten Socket.IO-Server
   * getestet werden kann - dieselbe Methode, die die socket.on-Callbacks
   * aufrufen.
   */
  handleUpstream(poi: unknown, action: 'upsert' | 'delete'): void {
    // Invariante: ohne konfigurierten Dienst gibt es keinen Push-Pfad -
    // es darf NIEMALS ein Batch emittiert werden (Delta-Sync bleibt als
    // Fallback; das ist derselbe Vertrag wie beim REST-Proxy).
    if (!this.configured) return;
    const id =
      poi && typeof poi === 'object' && 'id' in (poi as Record<string, unknown>)
        ? String((poi as Record<string, unknown>)['id'])
        : '';
    if (!id) return;

    const now = Date.now();
    if (this.batchTimer === null) {
      // Erstes Ereignis im Fenster: sammeln starten (trailing window).
      this.pending.set(id, action);
      this.firstChangeAt = now;
      this.batchTimer = setTimeout(() => this.flush(), BATCH_WINDOW_MS);
      return;
    }
    this.pending.set(id, action);
    // Sicherheitsnetz: Fenster hart schließen, wenn der Strom nicht
    // abreißen will (sonst würde die Latenz unbegrenzt wachsen).
    if (this.firstChangeAt !== null && now - this.firstChangeAt >= BATCH_MAX_AGE_MS) {
      this.flush();
    }
  }

  /** Schließt das Sammelfenster und emittiert EIN bikerpoi.batch-Event. */
  flush(): void {
    this.batchTimer && clearTimeout(this.batchTimer);
    this.batchTimer = null;
    this.firstChangeAt = null;
    if (this.pending.size === 0) return;

    const changes: BikerPoiChange[] = [...this.pending].map(([id, action]) => ({ id, action }));
    this.pending.clear();
    this.events.emit(BikerPoiRealtimeEvent.BATCH, { changes });
  }

  /** Test-Hook: internen Zustand zurücksetzen. */
  resetForTest(): void {
    this.batchTimer && clearTimeout(this.batchTimer);
    this.batchTimer = null;
    this.firstChangeAt = null;
    this.pending.clear();
  }
}
