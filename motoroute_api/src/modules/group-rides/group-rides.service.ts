import { ForbiddenException, Inject, Injectable, Logger } from '@nestjs/common';
import { createClient, SupabaseClient } from '@supabase/supabase-js';
import { EventEmitter2 } from '@nestjs/event-emitter';
import { ConfigService } from '@nestjs/config';
import { AuthenticatedUser } from '../../guards';
import { SUPABASE_CLIENT } from '../../supabase/supabase.module';
import { BikerPoisRealtimeBridge } from '../biker-pois/biker-pois.realtime';

export const GroupRideEvent = {
  SHARING_STARTED: 'groupride.sharing_started',
  POSITION_UPDATED: 'groupride.position_updated',
  SHARING_STOPPED: 'groupride.sharing_stopped',
  FINISHED: 'groupride.finished',
} as const;

/**
 * GroupRidesService - Live-Gruppenfahrt.
 *
 * PRIVATSPHÄRE zuerst: Das Teilen der Position ist strikt OPT-IN. Es
 * gibt keine serverseitige Funktion, die eine Position ohne ausdrückliche
 * Freigabe des Fahrers anlegt. ride_stop_sharing löscht die Zeile
 * physisch - "aus" bedeutet wirklich weg, kein schlafender Datensatz.
 *
 * Positionen werden NUR TRANSIENT gehalten (keine Historie, kein Tracking),
 * konsistent mit der TomTom-Transient-Regel und dem Datenschutz-Anspruch
 * der Chat-Vorgabe (Abschnitt 18/26).
 */
@Injectable()
export class GroupRidesService {
  private readonly logger = new Logger(GroupRidesService.name);
  private readonly supabaseUrl: string;
  private readonly supabaseAnonKey: string;

  constructor(
    @Inject(SUPABASE_CLIENT) private readonly adminClient: SupabaseClient | null,
    config: ConfigService,
    private readonly events: EventEmitter2,
    private readonly realtime: BikerPoisRealtimeBridge,
  ) {
    this.supabaseUrl = config.get<string>('SUPABASE_URL') ?? '';
    this.supabaseAnonKey =
      config.get<string>('SUPABASE_ANON_KEY') ??
      config.get<string>('SUPABASE_SERVICE_ROLE_KEY') ??
      '';
  }

  private scoped(user: AuthenticatedUser): SupabaseClient {
    if (!this.adminClient) throw new Error('DB_NOT_CONFIGURED');
    if (!user.token) {
      throw new ForbiddenException({ error: 'AUTH_REQUIRED', message: 'Token fehlt' });
    }
    return createClient(this.supabaseUrl, this.supabaseAnonKey, {
      global: { headers: { Authorization: `Bearer ${user.token}` } },
      auth: { autoRefreshToken: false, persistSession: false },
    });
  }

  private mapError(operation: string, error: { code?: string; message?: string } | null): never {
    const code = error?.code ?? '';
    if (code === '42501' || error?.message?.includes('FORBIDDEN')) {
      throw new ForbiddenException({ error: 'FORBIDDEN', message: 'Kein Zugriff auf diese Fahrt' });
    }
    throw new Error(`${operation} failed: ${code} ${error?.message ?? ''}`);
  }

  private emit(event: string, routeId: string, extra: Record<string, unknown> = {}): void {
    this.events.emit(event, { routeId, ...extra });
  }

  /** Fahrer aktiviert die Freigabe (opt-in) mit erster Position. */
  async startSharing(
    user: AuthenticatedUser,
    routeId: string,
    position: { lat: number; lng: number },
  ): Promise<void> {
    const db = this.scoped(user);
    const { error } = await db.rpc('ride_start_sharing', {
      p_route: routeId,
      p_lat: position.lat,
      p_lng: position.lng,
    });
    if (error) this.mapError('startSharing', error);
    this.emit(GroupRideEvent.SHARING_STARTED, routeId, { userId: user.id });
  }

  /**
   * Ride-Radar-Autorisierung: ist der Nutzer Mitglied der Gruppe, zu der
   * die Route gehört? Serverseitig geprüft gegen Supabase (RLS-Funktion
   * is_group_member_for_route) - NUR verifizierte Mitglieder werden ins
   * Ride-Relais eingespeist und dürfen den Raum abonnieren.
   */
  async assertRideMember(user: AuthenticatedUser, routeId: string): Promise<boolean> {
    const db = this.scoped(user);
    const { data, error } = await db.rpc('is_group_member_for_route', {
      p_route: routeId,
      usr: user.id,
    });
    return !error && data === true;
  }

  /** Heartbeat während der Fahrt (Position nur bei aktiver Freigabe). */
  async heartbeat(
    user: AuthenticatedUser,
    routeId: string,
    position: { lat: number; lng: number },
  ): Promise<void> {
    const db = this.scoped(user);
    const { error } = await db.rpc('ride_heartbeat', {
      p_route: routeId,
      p_lat: position.lat,
      p_lng: position.lng,
    });
    if (error) this.mapError('heartbeat', error);
    this.emit(GroupRideEvent.POSITION_UPDATED, routeId, { userId: user.id });

    // Ride-Radar (unabhängig vom Umkreis): Nach dem RLS-verifizierten
    // Beat das Relais füttern. Best-effort: Relais offline -> null,
    // der REST-/Polling-Pfad bleibt die autoritative Wahrheit. Die
    // VERTEILUNG an die Ride-Räume läuft kanonisch über die Bridge
    // (ride_position_update -> groupride.radar), hier KEIN lokales
    // Emit - sonst würde das Gateway doppelt senden.
    if (await this.assertRideMember(user, routeId)) {
      await this.realtime.pushRidePosition({
        routeId,
        userId: user.id,
        lat: position.lat,
        lng: position.lng,
      });
    } else {
      this.logger.warn(
        `Ride-Relais übersprungen: Nutzer ${user.id} ist kein Mitglied der Route ${routeId}`,
      );
    }
  }

  /** Freigabe beenden - löscht die Position physisch (Supabase + Relais). */
  async stopSharing(user: AuthenticatedUser, routeId: string): Promise<void> {
    const db = this.scoped(user);
    const { error } = await db.rpc('ride_stop_sharing', { p_route: routeId });
    if (error) this.mapError('stopSharing', error);
    this.emit(GroupRideEvent.SHARING_STOPPED, routeId, { userId: user.id });
    // Relais ebenfalls räumen (best-effort) - sonst bliebe der letzte
    // Beat bis zum Prune in den Radar-Updates anderer hängen.
    await this.realtime.leaveRide(routeId, user.id);
  }

  /** Fahrer markiert sich als fertig. */
  async finish(user: AuthenticatedUser, routeId: string): Promise<void> {
    const db = this.scoped(user);
    const { error } = await db.rpc('ride_finish', { p_route: routeId });
    if (error) this.mapError('finish', error);
    this.emit(GroupRideEvent.FINISHED, routeId, { userId: user.id });
  }

  /** Live-Zustand: alle teilenden Fahrer (nur Mitglieder sehen etwas). */
  async liveState(user: AuthenticatedUser, routeId: string): Promise<unknown> {
    const db = this.scoped(user);
    const { data, error } = await db.rpc('ride_live_state', { p_route: routeId });
    if (error) this.mapError('liveState', error);
    return data ?? [];
  }
}
