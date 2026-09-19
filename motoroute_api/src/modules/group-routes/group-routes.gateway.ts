import { Logger } from '@nestjs/common';
import {
  OnEvent,
} from '@nestjs/event-emitter';
import { WebSocketGateway } from '@nestjs/websockets';
import type { Server } from 'ws';
import { GroupRouteEvent } from './group-routes.service';
import { ChatGateway } from '../chat/chat.gateway';

/**
 * Broadcast der Routen-Änderungen (Abschnitt 12/27) über die ETWAIGE
 * bestehende Chat-WS-Infrastruktur: Das ChatGateway hält die Socket-
 * Verwaltung und die raumbasierte Verteilung - hier reichern wir nur
 * Gruppenrouten-Ereignisse an und senden sie an alle Sockets, die die
 * passende Konversation (Gruppen-Chat = Gruppen-Konversation) abonniert
 * haben.
 *
 * Räume: Gruppenrouten hängen an einer Gruppe; die App abonniert beim
 * Öffnen des Planers die Gruppen-KONVERSATION (conversation:<uuid>) -
 * dieselbe Mitgliedschafts-Prüfung wie im Chat greift damit automatisch
 * (serverseitig, Abschnitt 32).
 */
@WebSocketGateway({ path: '/v1/chat/ws' })
export class GroupRoutesGateway {
  private readonly logger = new Logger(GroupRoutesGateway.name);

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

  @OnEvent(GroupRouteEvent.UPDATED)
  onUpdated(payload: { routeId: string }): void {
    this.broadcast(GroupRouteEvent.UPDATED, payload);
  }

  @OnEvent(GroupRouteEvent.STOP_ADDED)
  onStopAdded(payload: { routeId: string; stopId: string; by: string }): void {
    this.broadcast(GroupRouteEvent.STOP_ADDED, payload);
  }

  @OnEvent(GroupRouteEvent.STOP_REMOVED)
  onStopRemoved(payload: { routeId: string; stopId: string }): void {
    this.broadcast(GroupRouteEvent.STOP_REMOVED, payload);
  }

  @OnEvent(GroupRouteEvent.REORDERED)
  onReordered(payload: { routeId: string }): void {
    this.broadcast(GroupRouteEvent.REORDERED, payload);
  }

  @OnEvent(GroupRouteEvent.RECALCULATED)
  onRecalculated(payload: { routeId: string; distanceMeters: number; durationSeconds: number }): void {
    this.broadcast(GroupRouteEvent.RECALCULATED, payload);
  }

  @OnEvent(GroupRouteEvent.STATUS_CHANGED)
  onStatusChanged(payload: { routeId: string; status: string }): void {
    this.broadcast(GroupRouteEvent.STATUS_CHANGED, payload);
  }

  @OnEvent(GroupRouteEvent.PERMISSION_CHANGED)
  onPermissionChanged(payload: { routeId: string; permission: string }): void {
    this.broadcast(GroupRouteEvent.PERMISSION_CHANGED, payload);
  }
}
