import { Inject, Logger } from '@nestjs/common';
import {
  OnGatewayConnection,
  OnGatewayDisconnect,
  OnGatewayInit,
  SubscribeMessage,
  WebSocketGateway,
  WebSocketServer,
} from '@nestjs/websockets';
import { OnEvent } from '@nestjs/event-emitter';
import type { Server, WebSocket } from 'ws';
import { ChatEvent, ChatService } from './chat.service';
import { SUPABASE_CLIENT } from '../../supabase/supabase.module';
import type { SupabaseClient } from '@supabase/supabase-js';

interface SocketState {
  userId?: string;
  token?: string;
  rooms: Set<string>;
  /** Ride-Räume (ride:<routeId>) - separat von Chat-Räumen gezählt. */
  rideRooms: Set<string>;
  lastTypingAt: number;
}

/**
 * WebSocket-Gateway für Echtzeit-Chat (Abschnitt 28) unter /v1/chat/ws.
 *
 * Protokoll (JSON-Frames):
 *   Client -> Server:
 *     { "event": "auth",        "data": { "token": "<supabase-jwt>" } }
 *     { "event": "subscribe",   "data": { "conversationId": "..." } }
 *     { "event": "unsubscribe", "data": { "conversationId": "..." } }
 *     { "event": "typing",      "data": { "conversationId": "...", "isTyping": true } }
 *
 *   Server -> Client:
 *     { "event": "auth_ok",     "data": { "userId": "..." } }
 *     { "event": "subscribed",  "data": { "conversationId": "..." } }
 *     { "event": "error",       "data": { "message": "..." } }
 *     { "event": "chat.message.created", "data": <Nachricht> }
 *     { "event": "chat.message.deleted", "data": { "conversationId", "messageId" } }
 *     { "event": "chat.typing", "data": { "conversationId", "userId", "isTyping" } }
 *     { "event": "chat.presence", "data": { "userId", "online", "lastSeenAt" } }
 *
 * Sicherheit: Für JEDE Raumanmeldung prüft der Server serverseitig die
 * Mitgliedschaft (is_conversation_member via Supabase) - ein Client kann
 * sich nicht in fremde Chats einschleichen. Autorisierung passiert nie
 * nur im Client (Abschnitt 26/29).
 *
 * Ereignisquellen: sendMessage/deleteMessage im ChatService emittieren
 * lokale Events (EventEmitter2), die hier in die Raeume gebroadcastet
 * werden. Supabase-Realtime-Kanaele (conversation:<id>) bleiben parallel
 * bedient - das ist der Skalierungspfad für Multi-Instance-Deployments
 * (TODO: dort Ereignis-Verbrach statt lokalem Emitter, sobald >1 Instanz).
 */
@WebSocketGateway({ path: '/v1/chat/ws' })
export class ChatGateway implements OnGatewayInit, OnGatewayConnection, OnGatewayDisconnect {
  private readonly logger = new Logger(ChatGateway.name);

  @WebSocketServer()
  server!: Server;

  private readonly sockets = new Map<WebSocket, SocketState>();

  constructor(
    private readonly chat: ChatService,
    @Inject(SUPABASE_CLIENT) adminClient: SupabaseClient | null,
  ) {
    if (!adminClient) {
      this.logger.warn('Supabase nicht konfiguriert - Chat-REST liefert DB_NOT_CONFIGURED, WS-Gateway bleibt passiv.');
    }
  }

  afterInit(): void {
    this.logger.log('ChatGateway ready on /v1/chat/ws');
  }

  handleConnection(socket: WebSocket): void {
    this.sockets.set(socket, { rooms: new Set(), rideRooms: new Set(), lastTypingAt: 0 });
  }

  handleDisconnect(socket: WebSocket): void {
    const state = this.sockets.get(socket);
    this.sockets.delete(socket);
    const userId = state?.userId;
    if (userId) {
      // Offline erst, wenn keine weitere Verbindung desselben Nutzers übrig ist.
      const stillOnline = [...this.sockets.values()].some((s) => s.userId === userId);
      if (!stillOnline) {
        this.broadcastToAll({
          event: ChatEvent.PRESENCE,
          data: { userId, online: false, lastSeenAt: new Date().toISOString() },
        });
      }
    }
  }

  // Hinweis zu platform-ws: Der Client sendet NestJS-Standard-Umschläge
  // {"event": "<name>", "data": {...}} - der Adapter verteilt an die
  // @SubscribeMessage-Handler und übergibt NUR das data-Feld.

  @SubscribeMessage('auth')
  async onAuth(client: WebSocket, data: { token?: string }): Promise<void> {
    const state = this.sockets.get(client);
    if (!state) return;
    await this.handleAuth(client, state, String(data?.token ?? ''));
  }

  @SubscribeMessage('subscribe')
  async onSubscribe(client: WebSocket, data: { conversationId?: string }): Promise<void> {
    const state = this.sockets.get(client);
    if (!state) return;
    await this.handleSubscribe(client, state, String(data?.conversationId ?? ''));
  }

  @SubscribeMessage('unsubscribe')
  onUnsubscribe(client: WebSocket, data: { conversationId?: string }): void {
    const state = this.sockets.get(client);
    if (state) state.rooms.delete(String(data?.conversationId ?? ''));
  }

  /**
   * Ride-Radar-Abonnement: Mitglieder derselben Route empfangen hier
   * groupride.radar-Updates (Positionen der Fahrt UNABHÄNGIG vom
   * Umkreis). Autorisierung serverseitig via Supabase-RLS-Funktion
   * is_group_member_for_route - ein manipulierter Client kann sich
   * nicht in fremde Fahrten einschleichen (dieselbe Regel wie beim
   * Chat-Raum-Abonnement, Abschnitt 26/29).
   */
  @SubscribeMessage('subscribe_ride')
  async onSubscribeRide(client: WebSocket, data: { routeId?: string }): Promise<void> {
    const state = this.sockets.get(client);
    if (!state) return;
    const routeId = String(data?.routeId ?? '');
    if (!state.userId || !state.token || !routeId) {
      this.send(client, { event: 'error', data: { message: 'Erst auth senden.' } });
      return;
    }
    const isMember = await this.chat.isRideMember(state.token, routeId, state.userId);
    if (!isMember) {
      this.send(client, { event: 'error', data: { message: 'Kein Zugriff auf diese Gruppenfahrt.' } });
      return;
    }
    state.rideRooms.add(routeId);
    this.send(client, { event: 'subscribed_ride', data: { routeId } });
  }

  @SubscribeMessage('unsubscribe_ride')
  onUnsubscribeRide(client: WebSocket, data: { routeId?: string }): void {
    const state = this.sockets.get(client);
    if (state) state.rideRooms.delete(String(data?.routeId ?? ''));
  }

  @SubscribeMessage('typing')
  async onTypingFrame(client: WebSocket, data: { conversationId?: string; isTyping?: boolean }): Promise<void> {
    const state = this.sockets.get(client);
    if (!state) return;
    const conversationId = String(data?.conversationId ?? '');
    const isTyping = data?.isTyping !== false;
    if (!state.userId || !state.token || !conversationId) return;
    // Throttle: maximal ein Typing-Frame pro 2 s pro Socket.
    const now = Date.now();
    if (isTyping && now - state.lastTypingAt < 2000) return;
    state.lastTypingAt = now;
    if (await this.chat.isMember(state.token, conversationId)) {
      this.broadcast(conversationId, {
        event: ChatEvent.TYPING,
        data: { conversationId, userId: state.userId, isTyping },
      }, state.userId);
    }
  }

  private async handleAuth(client: WebSocket, state: SocketState, token: string): Promise<void> {
    const userId = await this.chat.userIdFromToken(token);
    if (!userId) {
      this.send(client, { event: 'error', data: { message: 'Authentifizierung fehlgeschlagen.' } });
      return;
    }
    state.userId = userId;
    state.token = token;
    this.send(client, { event: 'auth_ok', data: { userId } });
    const alreadyOnline = [...this.sockets.values()].some((s) => s !== state && s.userId === userId);
    if (!alreadyOnline) {
      this.broadcastToAll({
        event: ChatEvent.PRESENCE,
        data: { userId, online: true, lastSeenAt: new Date().toISOString() },
      });
    }
  }

  private async handleSubscribe(client: WebSocket, state: SocketState, conversationId: string): Promise<void> {
    if (!state.userId || !state.token) {
      this.send(client, { event: 'error', data: { message: 'Erst auth senden.' } });
      return;
    }
    if (!(await this.chat.isMember(state.token, conversationId))) {
      this.send(client, { event: 'error', data: { message: 'Kein Zugriff auf diese Konversation.' } });
      return;
    }
    state.rooms.add(conversationId);
    this.send(client, { event: 'subscribed', data: { conversationId } });
  }

  // ------------------------------------------- Upstream: Service -> Räume

  @OnEvent(ChatEvent.NEW_MESSAGE)
  onNewMessage(payload: { conversationId: string; message: Record<string, unknown> }): void {
    if (payload.conversationId) {
      this.broadcast(payload.conversationId, { event: ChatEvent.NEW_MESSAGE, data: payload.message });
    }
  }

  @OnEvent(ChatEvent.MESSAGE_DELETED)
  onMessageDeleted(payload: { conversationId: string; messageId: string }): void {
    this.broadcast(payload.conversationId, {
      event: ChatEvent.MESSAGE_DELETED,
      data: { conversationId: payload.conversationId, messageId: payload.messageId },
    });
  }

  @OnEvent(ChatEvent.TYPING)
  onTyping(payload: { conversationId: string; userId: string; isTyping: boolean }): void {
    // Vom REST-Weg (broadcastTyping) kommend: Absender-Sockets ausschließen.
    this.broadcast(payload.conversationId, {
      event: ChatEvent.TYPING,
      data: { conversationId: payload.conversationId, userId: payload.userId, isTyping: payload.isTyping },
    }, payload.userId);
  }

  // ------------------------------------------------------------ Helpers

  private send(socket: WebSocket, frame: { event: string; data: unknown }): void {
    if (socket.readyState === socket.OPEN) socket.send(JSON.stringify(frame));
  }

  private broadcast(conversationId: string, frame: { event: string; data: unknown }, excludeUserId?: string): void {
    if (!this.server) return;
    for (const [socket, state] of this.sockets) {
      if (!state.rooms.has(conversationId)) continue;
      if (excludeUserId && state.userId === excludeUserId) continue;
      this.send(socket, frame);
    }
  }

  private broadcastToAll(frame: { event: string; data: unknown }): void {
    if (!this.server) return;
    for (const socket of this.sockets.keys()) this.send(socket, frame);
  }

  /**
   * Ride-Radar-Verteilung: groupride.radar / groupride.radar_leave NUR
   * an Sockets im Raum ride:<routeId>. Ein Socket ist nur NACH erfolg-
   * reicher Membership-Prüfung im Raum - Mitglieder derselben Route
   * sehen einander unabhängig vom Umkreis, Fremde sehen nichts.
   * Öffentliche Methode (kein @OnEvent): der GroupRidesService emittiert
   * die Events lokal je Route, der GroupRidesGateway reicht sie hierhin
   * weiter - so bleibt die Verteilung in EINER Socket-Verwaltung.
   */
  broadcastToRide(routeId: string, frame: { event: string; data: unknown }): void {
    for (const [socket, state] of this.sockets) {
      if (!state.rideRooms.has(routeId)) continue;
      this.send(socket, frame);
    }
  }
}
