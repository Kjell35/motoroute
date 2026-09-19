import { Logger } from '@nestjs/common';
import { OnEvent } from '@nestjs/event-emitter';
import { WebSocketGateway } from '@nestjs/websockets';
import type { Server, WebSocket } from 'ws';
import { ChatGateway } from '../chat/chat.gateway';
import { BikerPoisRealtimeBridge, BikerPoiRealtimeEvent } from './biker-pois.realtime';

/**
 * WS-Broadcast kuratierter Biker-POI-Änderungen (bikerpoi.batch) über die
 * bestehende authentifizierte App-WebSocket-Infrastruktur /v1/chat/ws -
 * die App kennt den POI-Dienst nie direkt (BFF-Prinzip).
 *
 * Zielgruppe: alle Sockets, die den POI-Delta-Sync nutzen können, also
 * authentifizierte Sockets mit gültigem Chat-WS-Login. POI-Daten sind
 * kein Geheimnis, aber der Abfluss bleibt im authentifizierten Kanal -
 * konsistent mit /v1/biker-pois/sync (Auth-Gate).
 */
@WebSocketGateway({ path: '/v1/chat/ws' })
export class BikerPoisGateway {
  private readonly logger = new Logger(BikerPoisGateway.name);

  constructor(private readonly chatGateway: ChatGateway) {}

  private broadcast(frame: { event: string; data: unknown }): void {
    const internals = this.chatGateway as unknown as {
      server?: Server;
      sockets?: Map<WebSocket, { userId?: string }>;
    };
    const server = internals.server;
    if (!server) return;
    // Nur authentifizierte Sockets (userId nach auth-Frame gesetzt) -
    // konsistent zum Auth-Gate des REST-Sync-Endpunkts.
    const authenticated = internals.sockets;
    for (const socket of server.clients) {
      if (socket.readyState !== socket.OPEN) continue;
      if (authenticated && !authenticated.get(socket)?.userId) continue;
      socket.send(JSON.stringify(frame));
    }
  }

  @OnEvent(BikerPoiRealtimeEvent.BATCH)
  onBatch(payload: { changes: Array<{ id: string; action: 'upsert' | 'delete' }> }): void {
    this.broadcast({ event: BikerPoiRealtimeEvent.BATCH, data: payload });
  }
}
