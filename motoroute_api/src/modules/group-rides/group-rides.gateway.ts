import { Logger } from '@nestjs/common';
import { OnEvent } from '@nestjs/event-emitter';
import { WebSocketGateway } from '@nestjs/websockets';
import type { Server } from 'ws';
import { GroupRideEvent } from './group-rides.service';
import { ChatGateway } from '../chat/chat.gateway';
import { BikerPoiRealtimeEvent } from '../biker-pois/biker-pois.realtime';

/**
 * Broadcast der Live-Fahrt-Ereignisse über die bestehende WS-Infrastruktur
 * (gleiche Verteilung wie GroupRoutesGateway). Die App hört auf
 * groupride.*-Events und zieht ride_live_state nach - der Zustand bleibt
 * server-autoritativ, Positionen laufen nie direkt über den WS-Strom ...
 *
 * ...AUSSER im Ride-Radar (Live-Gruppenfahrt + Radar verbunden): Die
 * groupride.radar-Events tragen die verifizierten Positionen der Route
 * direkt in der Payload (vom Relais kommend, nur nach Membership-Prüfung
 * eingespeist). Verteilung AUSSCHLIESSLICH in den Ride-Raum
 * (broadcastToRide) - nur Sockets mit bestandener Autorisierung empfangen
 * sie. groupride.sharing_started etc. bleiben bewusst global + ohne
 * Positionen (die App zieht ride_live_state nach).
 */
@WebSocketGateway({ path: '/v1/chat/ws' })
export class GroupRidesGateway {
  private readonly logger = new Logger(GroupRidesGateway.name);

  constructor(private readonly chatGateway: ChatGateway) {}

  private broadcast(event: string, payload: Record<string, unknown>): void {
    const server = (this.chatGateway as unknown as { server?: Server }).server;
    if (!server) return;
    for (const socket of server.clients) {
      if (socket.readyState === socket.OPEN) {
        socket.send(JSON.stringify({ event, data: payload }));
      }
    }
  }

  @OnEvent(GroupRideEvent.SHARING_STARTED)
  onStarted(payload: { routeId: string; userId: string }): void {
    this.broadcast(GroupRideEvent.SHARING_STARTED, payload);
  }

  @OnEvent(GroupRideEvent.POSITION_UPDATED)
  onHeartbeat(payload: { routeId: string; userId: string }): void {
    // Kein Positions-Payload: global sichtbar ist nur "jemand hat einen
    // Beat geschickt" (das zieht die App per REST nach). Positionen
    // fließen ausschließlich über groupride.radar (Ride-Raum).
    this.broadcast(GroupRideEvent.POSITION_UPDATED, payload);
  }

  @OnEvent(GroupRideEvent.SHARING_STOPPED)
  onStopped(payload: { routeId: string; userId: string }): void {
    this.broadcast(GroupRideEvent.SHARING_STOPPED, payload);
  }

  @OnEvent(GroupRideEvent.FINISHED)
  onFinished(payload: { routeId: string; userId: string }): void {
    this.broadcast(GroupRideEvent.FINISHED, payload);
  }

  // ------------------------------------------------------------ Ride-Radar

  /** Positionen der Route (aus dem Relais) -> NUR in den Ride-Raum. */
  @OnEvent(BikerPoiRealtimeEvent.RIDE_POSITION_UPDATE)
  onRadarUpdate(payload: { routeId: string; members: unknown[] }): void {
    this.chatGateway.broadcastToRide(payload.routeId, {
      event: BikerPoiRealtimeEvent.RIDE_POSITION_UPDATE,
      data: payload,
    });
  }

  /** Fahrer hat die Route verlassen (Freigabe aus) -> Ride-Raum. */
  @OnEvent(BikerPoiRealtimeEvent.RIDE_POSITION_LEAVE)
  onRadarLeave(payload: { routeId: string; userId: string }): void {
    this.chatGateway.broadcastToRide(payload.routeId, {
      event: BikerPoiRealtimeEvent.RIDE_POSITION_LEAVE,
      data: payload,
    });
  }
}
