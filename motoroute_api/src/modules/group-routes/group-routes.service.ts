import {
  ForbiddenException,
  Inject,
  Injectable,
  Logger,
  NotFoundException,
} from '@nestjs/common';
import { createClient, SupabaseClient } from '@supabase/supabase-js';
import { EventEmitter2 } from '@nestjs/event-emitter';
import { ConfigService } from '@nestjs/config';
import { AuthenticatedUser } from '../../guards';
import { SUPABASE_CLIENT } from '../../supabase/supabase.module';
import { RoutingService } from '../routing/routing.service';
import { AvoidOption, RouteStyle, VehicleType } from '../routing/dto/create-route.dto';

/** Kanonische Event-Namen für den WS-Broadcast (Spiegel zu ChatEvent). */
export const GroupRouteEvent = {
  UPDATED: 'grouproute.updated',
  STOP_ADDED: 'grouproute.stop_added',
  STOP_REMOVED: 'grouproute.stop_removed',
  REORDERED: 'grouproute.reordered',
  STATUS_CHANGED: 'grouproute.status_changed',
  PERMISSION_CHANGED: 'grouproute.permission_changed',
  RECALCULATED: 'grouproute.recalculated',
} as const;

/**
 * GroupRoutesService - kollaborativer Gruppen-Routenplaner.
 *
 * Grundprinzip wie im ChatService: Supabase wird mit dem User-JWT
 * aufgerufen, d.h. RLS + die RPC-Prüfungen (can_edit_route) bleiben die
 * DURCHSETZENDE Autorisierungsschicht. Der Service übersetzt nur SQL-
 * Fehlercodes in HTTP-Fehler - ein Client-Manipulationsversuch scheitert
 * an der Datenbank, nicht an einer Prüfung hier (Abschnitt 25/32).
 */
@Injectable()
export class GroupRoutesService {
  private readonly logger = new Logger(GroupRoutesService.name);
  private readonly supabaseUrl: string;
  private readonly supabaseAnonKey: string;

  constructor(
    @Inject(SUPABASE_CLIENT) private readonly adminClient: SupabaseClient | null,
    private readonly config: ConfigService,
    private readonly events: EventEmitter2,
    private readonly routing: RoutingService,
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

  private ensureConfigured(): void {
    if (!this.adminClient) throw new Error('DB_NOT_CONFIGURED');
  }

  private mapError(operation: string, error: { code?: string; message?: string } | null): never {
    const code = error?.code ?? '';
    const message = error?.message ?? 'unknown';
    if (code === '42501' || message.includes('FORBIDDEN') || message.includes('row-level security')) {
      throw new ForbiddenException({ error: 'FORBIDDEN', message: 'Keine Berechtigung für diese Aktion' });
    }
    if (code === 'P0002' || message.includes('NOT_FOUND')) {
      throw new NotFoundException({ error: 'NOT_FOUND', message: 'Ressource nicht gefunden' });
    }
    if (message.includes('STOP_LIST_MISMATCH')) {
      throw new ForbiddenException({ error: 'STOP_LIST_MISMATCH', message: 'Reihenfolge veraltet - bitte neu laden' });
    }
    if (code === 'P0001' || code === '23505') {
      throw new ForbiddenException({ error: 'INVALID', message });
    }
    throw new Error(`${operation} failed: ${code} ${message}`);
  }

  private emitRoute(event: string, routeId: string, extra: Record<string, unknown> = {}): void {
    this.events.emit(event, { routeId, ...extra });
  }

  // ==========================================================================
  // CRUD (Abschnitt 33)
  // ==========================================================================

  /** Erstellt die Route (Owner-only, RPC prüft) und berechnet sofort. */
  async createRoute(
    user: AuthenticatedUser,
    dto: {
      groupId: string;
      name: string;
      description?: string;
      startName?: string;
      startLat: number;
      startLng: number;
      destName?: string;
      destLat: number;
      destLng: number;
      vehicleType?: string;
      routingStyle?: string;
      avoidHighways?: boolean;
      avoidFerries?: boolean;
      avoidTolls?: boolean;
      permission?: string;
    },
  ): Promise<{ routeId: string }> {
    this.ensureConfigured();
    const db = this.scoped(user);
    const { data, error } = await db.rpc('create_group_route', {
      p_group: dto.groupId,
      p_name: dto.name,
      p_description: dto.description ?? null,
      p_start_name: dto.startName ?? null,
      p_start_lat: dto.startLat,
      p_start_lng: dto.startLng,
      p_dest_name: dto.destName ?? null,
      p_dest_lat: dto.destLat,
      p_dest_lng: dto.destLng,
      p_vehicle: dto.vehicleType ?? 'MOTORCYCLE',
      p_style: dto.routingStyle ?? 'CURVY',
      p_avoid_highways: dto.avoidHighways ?? false,
      p_avoid_ferries: dto.avoidFerries ?? false,
      p_avoid_tolls: dto.avoidTolls ?? false,
      p_permission: dto.permission ?? 'all_members',
    });
    if (error) this.mapError('createRoute', error);
    const routeId = String((data as { routeId: string }).routeId);

    // Erstberechnung asynchron - der Owner sieht die Route sofort,
    // Distanz/Zeit füllen sich, sobald GraphHopper geantwortet hat.
    void this.recalculate(user, routeId).catch((err) =>
      this.logger.warn(`initiale Berechnung fehlgeschlagen für ${routeId}: ${err}`),
    );
    return { routeId };
  }

  /** Alle Routen einer Gruppe (Liste mit Status, Metriken). */
  async listRoutes(user: AuthenticatedUser, groupId: string): Promise<unknown[]> {
    this.ensureConfigured();
    const db = this.scoped(user);
    const { data, error } = await db
      .from('group_routes')
      .select('*')
      .eq('group_id', groupId)
      .order('updated_at', { ascending: false });
    if (error) this.mapError('listRoutes', error);
    return data ?? [];
  }

  /** Einzelne Route inkl. Stopps (sortiert) und letzter Änderungen. */
  async getRoute(user: AuthenticatedUser, routeId: string): Promise<unknown> {
    this.ensureConfigured();
    const db = this.scoped(user);
    const { data: route, error } = await db
      .from('group_routes')
      .select('*')
      .eq('id', routeId)
      .maybeSingle();
    if (error) this.mapError('getRoute', error);
    if (!route) throw new NotFoundException({ error: 'NOT_FOUND', message: 'Route nicht gefunden' });

    const { data: stops, error: stopsErr } = await db
      .from('route_stops')
      .select('*')
      .eq('route_id', routeId)
      .order('position');
    if (stopsErr) this.mapError('getRoute.stops', stopsErr);

    const { data: history, error: histErr } = await db
      .from('route_changes')
      .select('id, action, detail, created_at, user_id, users:user_id(username, display_name, avatar_url)')
      .eq('route_id', routeId)
      .order('created_at', { ascending: false })
      .limit(20);
    if (histErr) this.mapError('getRoute.history', histErr);

    return { route, stops: stops ?? [], history: history ?? [] };
  }

  /** Metadaten ändern (Name, Beschreibung) - RLS entscheidet. */
  async updateRoute(
    user: AuthenticatedUser,
    routeId: string,
    patch: { name?: string; description?: string },
  ): Promise<void> {
    this.ensureConfigured();
    const db = this.scoped(user);
    const { error } = await db
      .from('group_routes')
      .update({
        ...(patch.name !== undefined ? { name: patch.name } : {}),
        ...(patch.description !== undefined ? { description: patch.description } : {}),
      })
      .eq('id', routeId);
    if (error) this.mapError('updateRoute', error);
    this.emitRoute(GroupRouteEvent.UPDATED, routeId, { action: 'updated' });
  }

  async deleteRoute(user: AuthenticatedUser, routeId: string): Promise<void> {
    this.ensureConfigured();
    const db = this.scoped(user);
    const { error } = await db.from('group_routes').delete().eq('id', routeId);
    if (error) this.mapError('deleteRoute', error);
  }

  async duplicateRoute(user: AuthenticatedUser, routeId: string, newName?: string): Promise<{ routeId: string }> {
    this.ensureConfigured();
    const db = this.scoped(user);
    const { data, error } = await db.rpc('duplicate_group_route', {
      p_route: routeId,
      p_new_name: newName ?? null,
    });
    if (error) this.mapError('duplicateRoute', error);
    return { routeId: String((data as { routeId: string }).routeId) };
  }

  // ==========================================================================
  // Rechte/Status/Sperre (Abschnitt 4/5/15/16)
  // ==========================================================================

  async setPermission(user: AuthenticatedUser, routeId: string, permission: 'all_members' | 'owner_only'): Promise<void> {
    this.ensureConfigured();
    const db = this.scoped(user);
    const { error } = await db.rpc('set_route_permission', {
      p_route: routeId,
      p_permission: permission,
    });
    if (error) this.mapError('setPermission', error);
    this.emitRoute(GroupRouteEvent.PERMISSION_CHANGED, routeId, { permission });
  }

  async setStatus(user: AuthenticatedUser, routeId: string, status: string): Promise<void> {
    this.ensureConfigured();
    const db = this.scoped(user);
    const { error } = await db.rpc('set_route_status', { p_route: routeId, p_status: status });
    if (error) this.mapError('setStatus', error);
    this.emitRoute(GroupRouteEvent.STATUS_CHANGED, routeId, { status });
  }

  async lock(user: AuthenticatedUser, routeId: string): Promise<void> {
    this.ensureConfigured();
    const db = this.scoped(user);
    const { error } = await db.rpc('lock_route', { p_route: routeId });
    if (error) this.mapError('lock', error);
    this.emitRoute(GroupRouteEvent.STATUS_CHANGED, routeId, { status: 'locked' });
  }

  async unlock(user: AuthenticatedUser, routeId: string): Promise<void> {
    this.ensureConfigured();
    const db = this.scoped(user);
    const { error } = await db.rpc('unlock_route', { p_route: routeId });
    if (error) this.mapError('unlock', error);
    this.emitRoute(GroupRouteEvent.STATUS_CHANGED, routeId, { status: 'planning' });
  }

  // ==========================================================================
  // Stopps (Abschnitt 7-10)
  // ==========================================================================

  async addStop(
    user: AuthenticatedUser,
    routeId: string,
    dto: { lat: number; lng: number; name: string; category?: string; description?: string; address?: string },
  ): Promise<{ stopId: string; position: number }> {
    this.ensureConfigured();
    const db = this.scoped(user);
    const { data, error } = await db.rpc('add_route_stop', {
      p_route: routeId,
      p_lat: dto.lat,
      p_lng: dto.lng,
      p_name: dto.name,
      p_category: dto.category ?? 'other',
      p_description: dto.description ?? null,
      p_address: dto.address ?? null,
    });
    if (error) this.mapError('addStop', error);
    const result = data as { stopId: string; position: number };
    this.emitRoute(GroupRouteEvent.STOP_ADDED, routeId, { stopId: result.stopId, by: user.id });
    // Auto-Neuberechnung (Abschnitt 11) - asynchron, Fehler brechen nichts.
    void this.recalculate(user, routeId).catch((err) =>
      this.logger.warn(`Recalc nach addStop fehlgeschlagen: ${err}`),
    );
    return result;
  }

  async deleteStop(user: AuthenticatedUser, stopId: string): Promise<void> {
    this.ensureConfigured();
    const db = this.scoped(user);
    // route_id vorher lesen (für Event + Recalc), Lesen ist für Mitglieder ok.
    const { data: stop, error: selErr } = await db
      .from('route_stops')
      .select('id, route_id, name')
      .eq('id', stopId)
      .maybeSingle();
    if (selErr) this.mapError('deleteStop.lookup', selErr);
    if (!stop) throw new NotFoundException({ error: 'NOT_FOUND', message: 'Stopp nicht gefunden' });
    const routeId = (stop as { route_id: string }).route_id;

    const { error } = await db.rpc('delete_route_stop', { p_stop: stopId });
    if (error) this.mapError('deleteStop', error);
    this.emitRoute(GroupRouteEvent.STOP_REMOVED, routeId, { stopId });
    void this.recalculate(user, routeId).catch((err) =>
      this.logger.warn(`Recalc nach deleteStop fehlgeschlagen: ${err}`),
    );
  }

  async reorderStops(user: AuthenticatedUser, routeId: string, stopIds: string[]): Promise<void> {
    this.ensureConfigured();
    const db = this.scoped(user);
    const { error } = await db.rpc('reorder_route_stops', { p_route: routeId, p_stop_ids: stopIds });
    if (error) this.mapError('reorderStops', error);
    this.emitRoute(GroupRouteEvent.REORDERED, routeId);
    void this.recalculate(user, routeId).catch((err) =>
      this.logger.warn(`Recalc nach reorder fehlgeschlagen: ${err}`),
    );
  }

  async updateStop(
    user: AuthenticatedUser,
    stopId: string,
    patch: { name?: string; description?: string; category?: string },
  ): Promise<void> {
    this.ensureConfigured();
    const db = this.scoped(user);
    const { error } = await db
      .from('route_stops')
      .update({
        ...(patch.name !== undefined ? { name: patch.name } : {}),
        ...(patch.description !== undefined ? { description: patch.description } : {}),
        ...(patch.category !== undefined ? { category: patch.category } : {}),
      })
      .eq('id', stopId);
    if (error) this.mapError('updateStop', error);
  }

  // ==========================================================================
  // Kommentare (Abschnitt 21) + Verlauf (Abschnitt 13)
  // ==========================================================================

  async addComment(user: AuthenticatedUser, stopId: string, content: string): Promise<void> {
    this.ensureConfigured();
    const db = this.scoped(user);
    const { error } = await db
      .from('route_comments')
      .insert({ stop_id: stopId, user_id: user.id, content });
    if (error) this.mapError('addComment', error);
  }

  async getComments(user: AuthenticatedUser, stopId: string): Promise<unknown[]> {
    this.ensureConfigured();
    const db = this.scoped(user);
    const { data, error } = await db.rpc('get_stop_comments', { p_stop: stopId });
    if (error) this.mapError('getComments', error);
    return (data as unknown[]) ?? [];
  }

  // ==========================================================================
  // Automatische Neuberechnung (Abschnitt 11)
  // ==========================================================================

  /**
   * Berechnet die Route über den NORMALEN RoutingService neu - mit den
   * GESPEICHERTEN Einstellungen der Gruppenroute (Stil/Fahrzeug/Vermeiden,
   * Abschnitt 11: "aktuelle Routing-Einstellungen berücksichtigen").
   * Metriken + Version werden zurückgeschrieben; das RECALCULATED-Event
   * triggert den WS-Broadcast an alle offenen Planer.
   */
  async recalculate(user: AuthenticatedUser, routeId: string): Promise<void> {
    this.ensureConfigured();
    const db = this.scoped(user);

    const { data: route, error } = await db
      .from('group_routes')
      .select('*')
      .eq('id', routeId)
      .maybeSingle();
    if (error) this.mapError('recalculate.load', error);
    if (!route) return;
    const r = route as Record<string, unknown>;

    const stops = (await db
      .from('route_stops')
      .select('lat, lng, name')
      .eq('route_id', routeId)
      .order('position')) as { data: Array<{ lat: number; lng: number; name: string }> | null };

    const waypoints = [
      { lat: r['start_lat'] as number, lng: r['start_lng'] as number },
      ...(stops.data ?? []).map((s) => ({ lat: s.lat, lng: s.lng })),
      { lat: r['dest_lat'] as number, lng: r['dest_lng'] as number },
    ];

    const avoid: AvoidOption[] = [];
    if (r['avoid_highways']) avoid.push(AvoidOption.HIGHWAY);
    if (r['avoid_ferries']) avoid.push(AvoidOption.FERRY);
    if (r['avoid_tolls']) avoid.push(AvoidOption.TOLL);

    const computed = await this.routing.createRoute({
      waypoints,
      preference: {
        style: r['routing_style'] as RouteStyle,
        vehicleType: r['vehicle_type'] as VehicleType,
        avoid,
      },
    });

    const { error: updErr } = await db
      .from('group_routes')
      .update({
        distance_meters: computed.distanceMeters,
        duration_seconds: computed.durationSeconds,
        version: (r['version'] as number) + 1,
      })
      .eq('id', routeId);
    if (updErr) this.mapError('recalculate.update', updErr);

    await db.from('route_changes').insert({
      route_id: routeId,
      user_id: user.id,
      action: 'recalculated',
      detail: `${Math.round(computed.distanceMeters / 1000)} km`,
    });

    this.emitRoute(GroupRouteEvent.RECALCULATED, routeId, {
      distanceMeters: computed.distanceMeters,
      durationSeconds: computed.durationSeconds,
    });
  }
}
