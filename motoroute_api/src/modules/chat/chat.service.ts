import {
  ConflictException,
  ForbiddenException,
  Inject,
  Injectable,
  Logger,
  NotFoundException,
  UnauthorizedException,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { createClient, SupabaseClient } from '@supabase/supabase-js';
import { AuthenticatedUser, SupabaseAuthService } from '../../guards';
import { SUPABASE_CLIENT } from '../../supabase/supabase.module';
import { EventEmitter2 } from '@nestjs/event-emitter';

/**
 * Konversations-ID des öffentlichen Chats (Singleton aus schema.sql).
 */
export const PUBLIC_CONVERSATION_ID = '00000000-0000-0000-0000-000000000001';

/**
 * Kanonische Chat-Event-Namen (WS-Gateway + App) - Typensicherheit statt
 * verteilter String-Literale.
 */
export const ChatEvent = {
  NEW_MESSAGE: 'chat.message.created',
  MESSAGE_DELETED: 'chat.message.deleted',
  TYPING: 'chat.typing',
  PRESENCE: 'chat.presence',
} as const;

export type ChatEventName = (typeof ChatEvent)[keyof typeof ChatEvent];

/**
 * Spam-Schutz-Konstanten (Chat-Vorgabe Abschnitt 25): bewusst großzügig
 * genug, dass normale Nutzer nichts merken, eng genug, um Skripte zu bremsen.
 */
const RATE_WINDOW_MS = 10_000; // 10 s Fenster
const RATE_MAX_MESSAGES = 5; // max. 5 Nachrichten pro Fenster
const RATE_MAX_CHATS = 3; // max. 3 neue private Chats pro Fenster

interface RateEntry {
  timestamps: number[];
}
const rateBuckets = new Map<string, RateEntry>();

/**
 * Prüft und registriert eine Aktion im Sliding-Window.
 * In-Memory bewusst: begrenzt die API-Instanz; horizontale Skalierung
 * erfordert Redis (TODO bei Multi-Instance-Deployment).
 */
function consumeRateSlot(key: string, max: number, windowMs = RATE_WINDOW_MS): boolean {
  const now = Date.now();
  const entry = rateBuckets.get(key) ?? { timestamps: [] };
  entry.timestamps = entry.timestamps.filter((t) => now - t < windowMs);
  if (entry.timestamps.length >= max) {
    rateBuckets.set(key, entry);
    return false;
  }
  entry.timestamps.push(now);
  rateBuckets.set(key, entry);
  // Gelegentliches Aufräumen: Bucket tot, wenn nichts recent ist.
  if (entry.timestamps.length === 1) {
    setTimeout(() => {
      const e = rateBuckets.get(key);
      if (e && e.timestamps.every((t) => Date.now() - t > windowMs)) rateBuckets.delete(key);
    }, windowMs + 1000).unref?.();
  }
  return true;
}

/**
 * Einladungscodes (Abschnitt 12): 8 Zeichen aus einem Alphabet ohne
 * verwechselbare Glyphen (kein 0/O, 1/I/L) = ~30 Bit Entropie - mit dem
 * "MOTO"-Präfix ergibt das erratsichere Brute-Force-Raten bei moderater
 * Rate-Limitierung keinen praktikablen Angriff.
 */
const CODE_ALPHABET = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
function generateInvitationCode(): string {
  let suffix = '';
  const bytes = new Uint8Array(8);
  // globalThis.crypto existiert in Node 18+ immer.
  globalThis.crypto.getRandomValues(bytes);
  for (const b of bytes) suffix += CODE_ALPHABET[b % CODE_ALPHABET.length];
  return `MOTO-${suffix}`;
}

/**
 * Einheitlicher Supabase-Fehler -> HTTP-Fehler Mapper. SQL-Fehlercodes
 * aus den RPCs (schema.sql) werden auf maschinenlesbare HTTP-Codes
 * abgebildet, damit die App darauf reagieren kann.
 */
function mapSupabaseError(operation: string, error: { code?: string; message?: string } | null): never {
  const code = error?.code ?? '';
  const message = error?.message ?? 'unknown database error';

  if (message.includes('BLOCKED') || code === 'P0001') {
    throw new ForbiddenException({ error: 'BLOCKED', message: 'Aktion durch Blockierung verhindert' });
  }
  if (message.includes('INVALID_CODE') || code === 'P0002') {
    throw new NotFoundException({ error: 'INVALID_CODE', message: 'Einladungscode ungültig oder abgelaufen' });
  }
  if (code === '23505' || code === 'P0003') {
    throw new ConflictException({ error: 'ALREADY_EXISTS', message: 'Ressource existiert bereits' });
  }
  if (code === '42501' || message.includes('row-level security')) {
    throw new ForbiddenException({ error: 'FORBIDDEN', message: 'Kein Zugriff' });
  }
  if (code === 'PGRST301' || message.includes('JWT')) {
    throw new UnauthorizedException({ error: 'AUTH_REQUIRED', message: 'Sitzung abgelaufen' });
  }
  throw new Error(`${operation} failed: ${code} ${message}`);
}

/**
 * ChatService - alle Datenoperationen des Chat-Systems.
 *
 * Grundprinzip (Architekturregel 39 + Sicherheit 26/29): Das Backend
 * spricht Supabase mit dem JWT DES ANFRAGENDEN NUTZERS an. RLS in
 * schema.sql bleibt damit die durchsetzende Autorisierungsschicht - der
 * Service kann unmöglich mehr sehen, als der Nutzer darf, auch bei einem
 * Bug hier. Der Service-Role-Client wird NUR für den Realtime-Broadcast
 * genutzt (ChatGateway), der serverseitig ohnehin alle Ereignisse sieht.
 *
 * Modular aufgeteilt in logische Blöcke, die bei Wachstum in eigene
 * Services ausgelagert werden: Conversations, Messages, Groups,
 * Invitations, Moderation (blocks/reports), Presence.
 */
@Injectable()
export class ChatService {
  private readonly logger = new Logger(ChatService.name);

  /** Client mit User-JWT - RLS durchsetzend. */
  private readonly adminClient: SupabaseClient | null;

  constructor(
    @Inject(SUPABASE_CLIENT) adminClient: SupabaseClient | null,
    config: ConfigService,
    private readonly events: EventEmitter2,
    private readonly authService: SupabaseAuthService,
  ) {
    this.adminClient = adminClient;
    this.supabaseUrl = config.get<string>('SUPABASE_URL') ?? '';
    this.supabaseAnonKey = config.get<string>('SUPABASE_ANON_KEY') ?? config.get<string>('SUPABASE_SERVICE_ROLE_KEY') ?? '';
  }

  /**
   * WS-Auth (ChatGateway): validiert ein Supabase-JWT und liefert die
   * User-ID - oder null bei ungültigem Token.
   */
  async userIdFromToken(token: string): Promise<string | null> {
    if (!token) return null;
    const user = await this.authService.validateToken(token);
    return user?.id ?? null;
  }

  /**
   * Serverseitige Raum-Autorisierung fürs WS-Gateway: ist der Inhaber
   * des Tokens Mitglied der Konversation? Läuft über den User-JWT,
   * d.h. RLS entscheidet - kein Trust in Client-Angaben (26/29).
   */
  async isMember(token: string, conversationId: string): Promise<boolean> {
    if (!this.adminClient || !token) return false;
    try {
      const user = await this.authService.validateToken(token);
      if (!user) return false;
      const db = this.scoped(user);
      const { data, error } = await db.rpc('is_conversation_member', {
        conv: conversationId,
        usr: user.id,
      });
      return !error && data === true;
    } catch {
      return false;
    }
  }

  /**
   * Serverseitige Raum-Autorisierung fürs Ride-Radar (Live-Gruppenfahrt):
   * ist der Inhaber des Tokens Mitglied der Gruppe, zu der die Route
   * gehört? Läuft über die RLS-Funktion is_group_member_for_route -
   * kein Trust in Client-Angaben (Abschnitt 26/29).
   */
  async isRideMember(token: string, routeId: string, userId: string): Promise<boolean> {
    if (!this.adminClient || !token) return false;
    try {
      const user = await this.authService.validateToken(token);
      if (!user || user.id !== userId) return false;
      const db = this.scoped(user);
      const { data, error } = await db.rpc('is_group_member_for_route', {
        p_route: routeId,
        usr: user.id,
      });
      return !error && data === true;
    } catch {
      return false;
    }
  }

  private readonly supabaseUrl: string;
  private readonly supabaseAnonKey: string;

  /** Realtime-Verbindungsdaten für die App (WebSocket direkt zu Supabase). */
  realtimeConfig() {
    if (!this.adminClient) {
      return { configured: false as const };
    }
    return {
      configured: true as const,
      url: this.supabaseUrl,
      anonKey: this.supabaseAnonKey,
      publicConversationId: PUBLIC_CONVERSATION_ID,
    };
  }

  /**
   * Scoped Client mit dem User-JWT. Ohne Token: Fehler - alle Chat-
   * Endpunkte erfordern Auth (öffentlicher Chat nur für angemeldete
   * Nutzer, Abschnitt 2/26).
   */
  private scoped(user: AuthenticatedUser): SupabaseClient {
    if (!this.adminClient) {
      throw new Error('DB_NOT_CONFIGURED');
    }
    if (!user.token) {
      throw new UnauthorizedException({ error: 'AUTH_REQUIRED', message: 'Token fehlt' });
    }
    return createClient(this.supabaseUrl, this.supabaseAnonKey, {
      global: { headers: { Authorization: `Bearer ${user.token}` } },
      auth: { autoRefreshToken: false, persistSession: false },
    });
  }

  private ensureConfigured(): void {
    if (!this.adminClient) {
      throw new Error('DB_NOT_CONFIGURED');
    }
  }

  // =========================================================================
  // Profil & Usersuche (Abschnitt 3/4)
  // =========================================================================

  async getProfile(user: AuthenticatedUser): Promise<unknown> {
    this.ensureConfigured();
    const db = this.scoped(user);
    const { data, error } = await db
      .from('users')
      .select('id, username, display_name, avatar_url, vehicle_desc, bio, show_online, last_seen_at')
      .eq('id', user.id)
      .maybeSingle();

    if (error) mapSupabaseError('getProfile', error);
    if (data) return data;

    // Profil-Zeile existiert noch nicht (Webhook verzögert): anlegen.
    const { data: created, error: insertError } = await db
      .from('users')
      .insert({ id: user.id, email: user.email ?? null })
      .select('id, username, display_name, avatar_url, vehicle_desc, bio, show_online, last_seen_at')
      .single();
    if (insertError) mapSupabaseError('getProfile.create', insertError);
    return created;
  }

  async updateProfile(user: AuthenticatedUser, dto: Record<string, unknown>): Promise<unknown> {
    this.ensureConfigured();
    const db = this.scoped(user);
    const patch: Record<string, unknown> = { updated_at: new Date().toISOString() };
    if (dto['username'] !== undefined) patch['username'] = dto['username'];
    if (dto['displayName'] !== undefined) patch['display_name'] = dto['displayName'];
    if (dto['avatarUrl'] !== undefined) patch['avatar_url'] = dto['avatarUrl'];
    if (dto['vehicleDesc'] !== undefined) patch['vehicle_desc'] = dto['vehicleDesc'];
    if (dto['bio'] !== undefined) patch['bio'] = dto['bio'];
    if (dto['showOnline'] !== undefined) patch['show_online'] = dto['showOnline'];

    const { data, error } = await db
      .from('users')
      .upsert({ id: user.id, ...patch }, { onConflict: 'id' })
      .select('id, username, display_name, avatar_url, vehicle_desc, bio, show_online, last_seen_at')
      .single();
    if (error) mapSupabaseError('updateProfile', error);
    return data;
  }

  async searchUsers(user: AuthenticatedUser, query: string, limit: number): Promise<unknown[]> {
    this.ensureConfigured();
    const db = this.scoped(user);
    const term = query.trim();
    if (term.length < 2) return [];
    const { data, error } = await db
      .from('users')
      .select('id, username, display_name, avatar_url, vehicle_desc')
      .or(`username.ilike.%${term}%,display_name.ilike.%${term}%`)
      .neq('id', user.id)
      .limit(limit);
    if (error) mapSupabaseError('searchUsers', error);
    return data ?? [];
  }

  async getUserProfile(user: AuthenticatedUser, userId: string): Promise<unknown> {
    this.ensureConfigured();
    const db = this.scoped(user);
    const { data, error } = await db
      .from('users')
      .select('id, username, display_name, avatar_url, vehicle_desc, bio, show_online, last_seen_at')
      .eq('id', userId)
      .maybeSingle();
    if (error) mapSupabaseError('getUserProfile', error);
    if (!data) throw new NotFoundException({ error: 'USER_NOT_FOUND', message: 'Benutzer nicht gefunden' });
    return data;
  }

  // =========================================================================
  // Konversationen & Listen (Abschnitt 6/17)
  // =========================================================================

  async listConversations(user: AuthenticatedUser): Promise<unknown> {
    this.ensureConfigured();
    const db = this.scoped(user);

    const { data: memberships, error: mErr } = await db
      .from('conversation_members')
      .select('conversation_id, role, last_read_at, joined_at')
      .eq('user_id', user.id);
    if (mErr) mapSupabaseError('listConversations.memberships', mErr);
    const memberRows = memberships ?? [];
    if (memberRows.length === 0) return { conversations: [] };

    const ids = memberRows.map((m) => m.conversation_id);
    const { data: convs, error: cErr } = await db
      .from('conversations')
      .select('id, type, created_at')
      .in('id', ids);
    if (cErr) mapSupabaseError('listConversations.conversations', cErr);

    // Letzte Nachricht + Mitgliederzahl + Gruppen-Info je Konversation.
    const { data: groups, error: gErr } = await db
      .from('groups')
      .select('id, conversation_id, name, description, image_url, owner_id')
      .in('conversation_id', ids);
    if (gErr) mapSupabaseError('listConversations.groups', gErr);

    const { data: lastMessages, error: lmErr } = await db
      .from('messages')
      .select('conversation_id, content, attachment, created_at, sender_id, deleted_at')
      .in('conversation_id', ids)
      .order('created_at', { ascending: false })
      .limit(ids.length * 3);
    if (lmErr) mapSupabaseError('listConversations.lastMessages', lmErr);

    // Ungelesen je Konversation (Abschnitt 17) via last_read_at.
    const { data: unreadRows, error: uErr } = await db
      .from('messages')
      .select('conversation_id, created_at, sender_id, deleted_at')
      .in('conversation_id', ids)
      .neq('sender_id', user.id);
    if (uErr) mapSupabaseError('listConversations.unread', uErr);

    const lastByConv = new Map<string, unknown>();
    for (const msg of lastMessages ?? []) {
      const convId = (msg as { conversation_id: string }).conversation_id;
      if (!lastByConv.has(convId)) lastByConv.set(convId, msg);
    }

    const unreadByConv = new Map<string, number>();
    for (const membership of memberRows) {
      const cutoff = new Date(membership.last_read_at).getTime();
      const count = (unreadRows ?? []).filter(
        (m) =>
          (m as { conversation_id: string }).conversation_id === membership.conversation_id &&
          !(m as { deleted_at: string | null }).deleted_at &&
          new Date((m as { created_at: string }).created_at).getTime() > cutoff,
      ).length;
      unreadByConv.set(membership.conversation_id, count);
    }

    const groupByConv = new Map<string, unknown>();
    for (const g of groups ?? []) {
      groupByConv.set((g as { conversation_id: string }).conversation_id, g);
    }

    const result = memberRows.map((membership) => {
      const conv = (convs ?? []).find((c) => (c as { id: string }).id === membership.conversation_id);
      const group = groupByConv.get(membership.conversation_id);
      const last = lastByConv.get(membership.conversation_id);
      return {
        id: membership.conversation_id,
        type: (conv as { type: string } | undefined)?.type ?? 'private',
        role: membership.role,
        group,
        lastMessage: last,
        unreadCount: unreadByConv.get(membership.conversation_id) ?? 0,
      };
    });

    // Nach letzter Aktivität sortieren (Abschnitt 6).
    result.sort((a, b) => {
      const ta = new Date(((a.lastMessage as { created_at?: string } | undefined)?.created_at) ?? 0).getTime();
      const tb = new Date(((b.lastMessage as { created_at?: string } | undefined)?.created_at) ?? 0).getTime();
      return tb - ta;
    });

    return { conversations: result };
  }

  async listMembers(user: AuthenticatedUser, conversationId: string): Promise<unknown[]> {
    this.ensureConfigured();
    const db = this.scoped(user);
    const { data, error } = await db
      .from('conversation_members')
      .select('user_id, role, joined_at, users:users!inner(id, username, display_name, avatar_url, show_online, last_seen_at)')
      .eq('conversation_id', conversationId);
    if (error) mapSupabaseError('listMembers', error);
    return (data ?? []).map((row: Record<string, unknown>) => ({
      userId: row['user_id'],
      role: row['role'],
      joinedAt: row['joined_at'],
      profile: row['users'],
    }));
  }

  async markRead(user: AuthenticatedUser, conversationId: string): Promise<void> {
    this.ensureConfigured();
    const db = this.scoped(user);
    const { error } = await db.rpc('mark_read', { conv: conversationId });
    if (error) mapSupabaseError('markRead', error);
  }

  // =========================================================================
  // Nachrichten (Abschnitt 20/21/36)
  // =========================================================================

  async fetchMessages(
    user: AuthenticatedUser,
    conversationId: string,
    before: string | undefined,
    limit: number,
  ): Promise<{ messages: unknown[]; hasMore: boolean }> {
    this.ensureConfigured();
    const db = this.scoped(user);

    let query = db
      .from('messages')
      .select(
        'id, conversation_id, sender_id, content, attachment, reply_to_id, created_at, updated_at, deleted_at, sender:users!sender_id(username, display_name, avatar_url)',
      )
      .eq('conversation_id', conversationId)
      .order('created_at', { ascending: false })
      .limit(limit + 1);

    if (before) {
      query = query.lt('created_at', before);
    }

    const { data, error } = await query;
    if (error) mapSupabaseError('fetchMessages', error);

    const hasMore = (data?.length ?? 0) > limit;
    const messages = (data ?? []).slice(0, limit);
    // Aufsteigend ausliefern (älteste zuerst) - die App rendert so direkt.
    messages.reverse();
    return { messages, hasMore };
  }

  async sendMessage(
    user: AuthenticatedUser,
    conversationId: string,
    content: string,
    attachment?: Record<string, unknown>,
  ): Promise<unknown> {
    this.ensureConfigured();
    // Spam-Schutz (Abschnitt 25)
    if (!consumeRateSlot(`msg:${user.id}`, RATE_MAX_MESSAGES)) {
      throw new ForbiddenException({
        error: 'RATE_LIMITED',
        message: 'Zu viele Nachrichten - bitte kurz warten',
      });
    }

    const db = this.scoped(user);
    const { data, error } = await db
      .from('messages')
      .insert({
        conversation_id: conversationId,
        sender_id: user.id,
        content,
        ...(attachment ? { attachment } : {}),
      })
      .select('id, conversation_id, sender_id, content, attachment, reply_to_id, created_at')
      .single();
    if (error) mapSupabaseError('sendMessage', error);

    // Realtime-Broadcast an alle Raum-Abonnenten (Abschnitt 28):
    // (a) lokal an WS-Clients dieses Prozesses, (b) über Supabase-
    // Realtime-Kanal für andere Instanzen / direkte Supabase-Clients.
    this.events.emit(ChatEvent.NEW_MESSAGE, { conversationId, message: data });
    await this.broadcast('message', conversationId, data);
    return data;
  }

  async deleteMessage(user: AuthenticatedUser, messageId: string): Promise<void> {
    this.ensureConfigured();
    const db = this.scoped(user);

    // Erst lesen, um die conversation_id für den Broadcast zu kennen.
    const { data: existing, error: selErr } = await db
      .from('messages')
      .select('id, conversation_id, sender_id')
      .eq('id', messageId)
      .maybeSingle();
    if (selErr) mapSupabaseError('deleteMessage.lookup', selErr);
    if (!existing) throw new NotFoundException({ error: 'MESSAGE_NOT_FOUND', message: 'Nachricht nicht gefunden' });
    if ((existing as { sender_id: string }).sender_id !== user.id) {
      throw new ForbiddenException({ error: 'FORBIDDEN', message: 'Nur eigene Nachrichten löschbar' });
    }

    // Soft-Delete (Abschnitt 21): "Nachricht gelöscht"-Tombstone.
    const { error } = await db
      .from('messages')
      .update({ content: '', attachment: null, deleted_at: new Date().toISOString() })
      .eq('id', messageId);
    if (error) mapSupabaseError('deleteMessage', error);

    const deletedConversationId = (existing as { conversation_id: string }).conversation_id;
    this.events.emit(ChatEvent.MESSAGE_DELETED, {
      conversationId: deletedConversationId,
      messageId,
    });
    await this.broadcast('message_deleted', deletedConversationId, { id: messageId });
  }

  // =========================================================================
  // Private Chats (Abschnitt 4/5/23)
  // =========================================================================

  async startPrivateChat(user: AuthenticatedUser, otherUserId: string): Promise<{ conversationId: string }> {
    this.ensureConfigured();
    // Spam-Schutz: nicht beliebig viele neue Chats eröffnen.
    if (!consumeRateSlot(`chat-create:${user.id}`, RATE_MAX_CHATS)) {
      throw new ForbiddenException({ error: 'RATE_LIMITED', message: 'Zu viele neue Chats - bitte kurz warten' });
    }

    const db = this.scoped(user);
    const { data, error } = await db.rpc('get_or_create_private_chat', { other: otherUserId });
    if (error) mapSupabaseError('startPrivateChat', error);
    return { conversationId: String(data) };
  }

  // =========================================================================
  // Gruppen (Abschnitt 7-15/35)
  // =========================================================================

  async createGroup(
    user: AuthenticatedUser,
    dto: { name: string; description?: string; imageUrl?: string; category?: string },
  ): Promise<{ groupId: string }> {
    this.ensureConfigured();
    if (!consumeRateSlot(`group-create:${user.id}`, 3, 60_000)) {
      throw new ForbiddenException({ error: 'RATE_LIMITED', message: 'Zu viele Gruppen - bitte kurz warten' });
    }

    const db = this.scoped(user);
    const { data, error } = await db.rpc('create_group', {
      p_name: dto.name,
      p_description: dto.description ?? null,
      p_image_url: dto.imageUrl ?? null,
      p_category: dto.category ?? null,
    });
    if (error) mapSupabaseError('createGroup', error);
    return { groupId: String(data) };
  }

  async updateGroup(user: AuthenticatedUser, groupId: string, dto: Record<string, unknown>): Promise<unknown> {
    this.ensureConfigured();
    const db = this.scoped(user);
    const patch: Record<string, unknown> = {};
    if (dto['name'] !== undefined) patch['name'] = dto['name'];
    if (dto['description'] !== undefined) patch['description'] = dto['description'];
    if (dto['imageUrl'] !== undefined) patch['image_url'] = dto['imageUrl'];

    // RLS (groups_update) erlaubt nur den Owner - der Fehler hier ist
    // also korrekt 42501 -> 403.
    const { data, error } = await db
      .from('groups')
      .update(patch)
      .eq('id', groupId)
      .select('id, name, description, image_url, owner_id')
      .single();
    if (error) mapSupabaseError('updateGroup', error);
    return data;
  }

  async getGroup(user: AuthenticatedUser, groupId: string): Promise<unknown> {
    this.ensureConfigured();
    const db = this.scoped(user);
    const { data, error } = await db
      .from('groups')
      .select('id, conversation_id, owner_id, name, description, image_url, category, created_at')
      .eq('id', groupId)
      .maybeSingle();
    if (error) mapSupabaseError('getGroup', error);
    if (!data) throw new NotFoundException({ error: 'GROUP_NOT_FOUND', message: 'Gruppe nicht gefunden' });
    return data;
  }

  async deleteGroup(user: AuthenticatedUser, groupId: string): Promise<void> {
    this.ensureConfigured();
    const db = this.scoped(user);
    const { error } = await db.from('groups').delete().eq('id', groupId);
    if (error) mapSupabaseError('deleteGroup', error);
    // Gruppen-Konversation cascade-deletes (members/messages/groups).
  }

  async leaveGroup(user: AuthenticatedUser, groupId: string): Promise<{ needsOwnershipTransfer: boolean }> {
    this.ensureConfigured();
    const db = this.scoped(user);
    const group = (await this.getGroup(user, groupId)) as { conversation_id: string; owner_id: string };

    if (group.owner_id === user.id) {
      // Owner-Verlassen (Abschnitt 35): Ownership muss übertragen werden -
      // sonst wäre die Gruppe verwaist. Die App zeigt die Auswahl an.
      return { needsOwnershipTransfer: true };
    }
    const { error } = await db
      .from('conversation_members')
      .delete()
      .eq('conversation_id', group.conversation_id)
      .eq('user_id', user.id);
    if (error) mapSupabaseError('leaveGroup', error);
    return { needsOwnershipTransfer: false };
  }

  async transferOwnership(user: AuthenticatedUser, groupId: string, newOwnerId: string): Promise<void> {
    this.ensureConfigured();
    const db = this.scoped(user);
    const group = (await this.getGroup(user, groupId)) as { conversation_id: string; owner_id: string };
    if (group.owner_id !== user.id) {
      throw new ForbiddenException({ error: 'FORBIDDEN', message: 'Nur der Owner kann übertragen' });
    }
    // Beide Schritte via RPC-artigem Update; RLS erlaubt Owner beides.
    const { error: gErr } = await db.from('groups').update({ owner_id: newOwnerId }).eq('id', groupId);
    if (gErr) mapSupabaseError('transferOwnership.group', gErr);
    const { error: mErr } = await db
      .from('conversation_members')
      .update({ role: 'owner' })
      .eq('conversation_id', group.conversation_id)
      .eq('user_id', newOwnerId);
    if (mErr) mapSupabaseError('transferOwnership.member', mErr);
    const { error: oldErr } = await db
      .from('conversation_members')
      .update({ role: 'member' })
      .eq('conversation_id', group.conversation_id)
      .eq('user_id', user.id);
    if (oldErr) mapSupabaseError('transferOwnership.oldOwner', oldErr);
  }

  async removeMember(user: AuthenticatedUser, groupId: string, memberUserId: string): Promise<void> {
    this.ensureConfigured();
    const db = this.scoped(user);
    const group = (await this.getGroup(user, groupId)) as { conversation_id: string; owner_id: string };
    if (group.owner_id !== user.id) {
      throw new ForbiddenException({ error: 'FORBIDDEN', message: 'Nur der Owner kann entfernen' });
    }
    if (memberUserId === user.id) {
      throw new ForbiddenException({ error: 'FORBIDDEN', message: 'Owner kann sich nicht selbst entfernen' });
    }
    const { error } = await db
      .from('conversation_members')
      .delete()
      .eq('conversation_id', group.conversation_id)
      .eq('user_id', memberUserId);
    if (error) mapSupabaseError('removeMember', error);
  }

  // =========================================================================
  // Einladungscodes (Abschnitt 10-12)
  // =========================================================================

  async createInvitation(
    user: AuthenticatedUser,
    groupId: string,
    expiresInDays?: number,
  ): Promise<{ code: string; expiresAt: string | null }> {
    this.ensureConfigured();
    const db = this.scoped(user);
    // Neuer Code deaktiviert alte (Abschnitt 12: "Wenn ein neuer Code
    // erzeugt wird, kann der alte Code ungültig werden").
    await db.from('group_invitations').update({ active: false }).eq('group_id', groupId);
    // RLS (invitations_insert) verlangt created_by == auth.uid() && Owner.

    const expiresAt =
      expiresInDays && expiresInDays > 0
        ? new Date(Date.now() + expiresInDays * 24 * 3600 * 1000).toISOString()
        : null;

    for (let attempt = 0; attempt < 3; attempt++) {
      const code = generateInvitationCode();
      const { data, error } = await db
        .from('group_invitations')
        .insert({ group_id: groupId, code, created_by: user.id, expires_at: expiresAt })
        .select('code, expires_at')
        .single();
      if (!error) return { code: data['code'] as string, expiresAt: (data['expires_at'] as string | null) ?? null };
      if ((error as { code?: string }).code !== '23505') mapSupabaseError('createInvitation', error);
      // Kollision (extrem unwahrscheinlich): neuer Code.
    }
    throw new ConflictException({ error: 'CODE_GENERATION_FAILED', message: 'Code-Generierung fehlgeschlagen' });
  }

  async deactivateInvitation(user: AuthenticatedUser, groupId: string): Promise<void> {
    this.ensureConfigured();
    const db = this.scoped(user);
    const { error } = await db
      .from('group_invitations')
      .update({ active: false })
      .eq('group_id', groupId);
    if (error) mapSupabaseError('deactivateInvitation', error);
  }

  async getActiveInvitation(user: AuthenticatedUser, groupId: string): Promise<{ code: string } | null> {
    this.ensureConfigured();
    const db = this.scoped(user);
    const { data, error } = await db
      .from('group_invitations')
      .select('code')
      .eq('group_id', groupId)
      .eq('active', true)
      .order('created_at', { ascending: false })
      .limit(1)
      .maybeSingle();
    if (error) mapSupabaseError('getActiveInvitation', error);
    return data ? { code: (data as { code: string }).code } : null;
  }

  async previewByCode(user: AuthenticatedUser, code: string): Promise<unknown> {
    this.ensureConfigured();
    const db = this.scoped(user);
    const { data, error } = await db.rpc('preview_group_by_code', { p_code: code });
    if (error) mapSupabaseError('previewByCode', error);
    return data;
  }

  async joinByCode(user: AuthenticatedUser, code: string): Promise<unknown> {
    this.ensureConfigured();
    const db = this.scoped(user);
    const { data, error } = await db.rpc('join_group_with_code', { p_code: code });
    if (error) mapSupabaseError('joinByCode', error);
    return data;
  }

  // =========================================================================
  // Moderation: Blockieren & Melden (Abschnitt 22/23/24)
  // =========================================================================

  async blockUser(user: AuthenticatedUser, targetUserId: string): Promise<void> {
    this.ensureConfigured();
    if (targetUserId === user.id) {
      throw new ForbiddenException({ error: 'FORBIDDEN', message: 'Selbst-Blockierung nicht möglich' });
    }
    const db = this.scoped(user);
    const { error } = await db
      .from('blocked_users')
      .upsert({ user_id: user.id, blocked_user_id: targetUserId }, { onConflict: 'user_id,blocked_user_id' });
    if (error) mapSupabaseError('blockUser', error);
  }

  async unblockUser(user: AuthenticatedUser, targetUserId: string): Promise<void> {
    this.ensureConfigured();
    const db = this.scoped(user);
    const { error } = await db
      .from('blocked_users')
      .delete()
      .eq('user_id', user.id)
      .eq('blocked_user_id', targetUserId);
    if (error) mapSupabaseError('unblockUser', error);
  }

  async listBlocked(user: AuthenticatedUser): Promise<unknown[]> {
    this.ensureConfigured();
    const db = this.scoped(user);
    const { data, error } = await db
      .from('blocked_users')
      .select('blocked_user_id, created_at, blocked:users!blocked_users_blocked_user_id_fkey(username, display_name, avatar_url)')
      .eq('user_id', user.id);
    if (error) mapSupabaseError('listBlocked', error);
    return data ?? [];
  }

  async reportMessage(user: AuthenticatedUser, messageId: string, reason: string, details?: string): Promise<void> {
    this.ensureConfigured();
    if (!consumeRateSlot(`report:${user.id}`, 10, 60_000)) {
      throw new ForbiddenException({ error: 'RATE_LIMITED', message: 'Zu viele Meldungen' });
    }
    const db = this.scoped(user);
    const { data: msg, error: selErr } = await db
      .from('messages')
      .select('id, sender_id')
      .eq('id', messageId)
      .maybeSingle();
    if (selErr) mapSupabaseError('reportMessage.lookup', selErr);
    if (!msg) throw new NotFoundException({ error: 'MESSAGE_NOT_FOUND', message: 'Nachricht nicht gefunden' });

    const { error } = await db.from('reports').insert({
      reporter_id: user.id,
      reported_user_id: (msg as { sender_id: string }).sender_id,
      message_id: messageId,
      reason,
      details: details ?? null,
    });
    if (error) mapSupabaseError('reportMessage', error);
  }

  async reportUser(user: AuthenticatedUser, reportedUserId: string, reason: string, details?: string): Promise<void> {
    this.ensureConfigured();
    if (!consumeRateSlot(`report:${user.id}`, 10, 60_000)) {
      throw new ForbiddenException({ error: 'RATE_LIMITED', message: 'Zu viele Meldungen' });
    }
    const db = this.scoped(user);
    const { error } = await db.from('reports').insert({
      reporter_id: user.id,
      reported_user_id: reportedUserId,
      reason,
      details: details ?? null,
    });
    if (error) mapSupabaseError('reportUser', error);
  }

  // =========================================================================
  // Presence & Typing (Abschnitt 18/19)
  // =========================================================================

  async touchPresence(user: AuthenticatedUser): Promise<void> {
    this.ensureConfigured();
    const db = this.scoped(user);
    // show_online respektiert die Datenschutzeinstellung: bei false wird
    // last_seen_at nicht aktualisiert (Abschnitt 18).
    const { data: profile } = await db.from('users').select('show_online').eq('id', user.id).maybeSingle();
    if ((profile as { show_online?: boolean } | null)?.show_online === false) return;
    await db.rpc('touch_presence');
  }

  /** Typing-Event: reiner Broadcast, kein Persistenzbedarf (Abschnitt 19). */
  async broadcastTyping(user: AuthenticatedUser, conversationId: string, isTyping: boolean): Promise<void> {
    this.ensureConfigured();
    const db = this.scoped(user);
    // Mitgliedschaft prüfen, bevor gebroadcastet wird (RLS-Politik).
    const { data: isMember, error } = await db.rpc('is_conversation_member', {
      conv: conversationId,
      usr: user.id,
    });
    if (error || !isMember) return;
    // Lokal an WS-Clients + Supabase-Kanal (siehe sendMessage).
    this.events.emit(ChatEvent.TYPING, { conversationId, userId: user.id, isTyping });
    await this.broadcast('typing', conversationId, { userId: user.id, isTyping });
  }

  // =========================================================================
  // Realtime-Broadcast (Abschnitt 28)
  // =========================================================================

  /**
   * Server-seitiger Broadcast in den Realtime-Kanal der Konversation.
   * Channel-Namenskonvention: `conversation:<uuid>` - die App abonniert
   * genau diese Kanäle. Broadcast-Events mit User-JWT erfordern in
   * Supabase Realtime keine weitere Auth, da die App nur Kanäle von
   * Konversationen abonniert, deren Mitglied sie ist (Prüfung client-
   * seitig + serverseitig via RLS beim Lesen).
   */
  private async broadcast(event: string, conversationId: string, payload: unknown): Promise<void> {
    if (!this.adminClient) return;
    try {
      const channel = this.adminClient.channel(`conversation:${conversationId}`);
      await channel.send({
        type: 'broadcast',
        event,
        payload,
      });
      // Channel nach dem Senden wieder freigeben (keine Leaks bei
      // hohen Nachrichtenraten).
      this.adminClient.removeChannel(channel);
    } catch (err) {
      // Broadcast-Fehler dürfen das Senden nicht scheitern lassen -
      // die Nachricht ist persistiert, Clients holen sie per Pull nach.
      this.logger.warn(`broadcast failed for ${conversationId}: ${err}`);
    }
  }
}
