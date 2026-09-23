import {
  ForbiddenException,
  HttpException,
  HttpStatus,
  Inject,
  Injectable,
  Logger,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { createClient, SupabaseClient } from '@supabase/supabase-js';
import { AuthenticatedUser } from '../../guards';
import { SUPABASE_CLIENT } from '../../supabase/supabase.module';
import { SearchService } from '../search/search.service';

const MAX_TRACK_POINTS = 5000;
const MAX_POIS = 100;
const MAX_PHOTOS = 8;
const MAX_DESC = 2000;

export interface RideTrackPoint {
  lat: number;
  lng: number;
  elevationMeters?: number | null;
  secondsSinceStart: number;
}

export interface PlaceVisitInput {
  externalId: string;
  category: 'fuel' | 'restaurant' | 'hotel' | 'camping' | 'bikertreff' | 'other';
  label: string;
  lat: number;
  lng: number;
}

export interface RideSyncDto {
  externalId: string;
  title: string;
  startedAt: string;
  endedAt: string;
  distanceMeters: number;
  durationSeconds: number;
  elevationGainMeters: number;
  track: RideTrackPoint[];
  pois: PlaceVisitInput[];
  startLabel?: string | null;
  endLabel?: string | null;
  startLat?: number | null;
  startLng?: number | null;
  endLat?: number | null;
  endLng?: number | null;
  description?: string | null;
  photos?: string[];
}

export interface PrivacyUpdateDto {
  rideHistoryEnabled?: boolean;
  authPrivacy?: 'private' | 'public';
  shareRides?: boolean;
  sharePlaces?: boolean;
  hideStartEnd?: boolean;
  perRide?: Array<{ externalId: string; isPublic: boolean; shareTrack?: boolean }>;
  perPlace?: Array<{ externalId: string; isPublic: boolean }>;
}

/** Öffentliche Sicht eines fremden Profils - NUR freigegebene Daten. */
export interface PublicRideView {
  externalId: string;
  title: string;
  startedAt: string;
  endedAt: string;
  distanceMeters: number;
  durationSeconds: number;
  elevationGainMeters: number;
  region: string | null;
  description: string | null;
  photos: string[];
  track: Array<{ lat: number; lng: number }>;
  pois: Array<{ label: string; lat: number; lng: number }>;
  startLabel: string | null;
  endLabel: string | null;
  start: { lat: number; lng: number } | null;
  end: { lat: number; lng: number } | null;
}

export interface PublicProfileView {
  profile: {
    userId: string;
    displayName: string | null;
    username: string | null;
    avatarUrl: string | null;
    isPrivate: boolean;
  };
  history: {
    rideCount: number;
    totalKm: number;
    totalHours: number;
    totalElevationGain: number;
    regions: string[];
    rides: PublicRideView[];
    places: Array<{
      externalId: string;
      category: string;
      label: string;
      lat: number;
      lng: number;
      visitCount: number;
      lastVisitedAt: string | null;
    }>;
  };
}

export interface RideRow {
  user_id: string;
  external_id: string;
  title: string;
  started_at: string;
  ended_at: string;
  distance_meters: number;
  duration_seconds: number;
  elevation_gain_meters: number;
  track: RideTrackPoint[] | null;
  pois: Array<{ label: string; lat: number; lng: number }> | null;
  start_label: string | null;
  end_label: string | null;
  start_lat: number | null;
  start_lng: number | null;
  end_lat: number | null;
  end_lng: number | null;
  region: string | null;
  description: string | null;
  photos: string[] | null;
  is_public: boolean;
  share_track: boolean;
}

@Injectable()
export class RideHistoryService {
  private readonly logger = new Logger(RideHistoryService.name);
  private readonly supabaseUrl: string;
  private readonly supabaseAnonKey: string;

  constructor(
    @Inject(SUPABASE_CLIENT) private readonly adminClient: SupabaseClient | null,
    config: ConfigService,
    private readonly search: SearchService,
  ) {
    this.supabaseUrl = config.get<string>('SUPABASE_URL') ?? '';
    this.supabaseAnonKey =
      config.get<string>('SUPABASE_ANON_KEY') ??
      config.get<string>('SUPABASE_SERVICE_ROLE_KEY') ??
      '';
  }

  /** Client mit dem JWT des Aufrufers - RLS erzwingt Zeilenrechte. */
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
      throw new ForbiddenException({ error: 'FORBIDDEN', message: 'Keine Berechtigung' });
    }
    const schemaMissing =
      code === 'PGRST205' ||
      code === 'PGRST204' ||
      /relation .* does not exist|column .* does not exist|schema cache/i.test(
        error?.message ?? '',
      );
    if (schemaMissing) {
      throw new HttpException(
        {
          error: 'SCHEMA_NOT_MIGRATED',
          message: 'Migration 0004 fehlt - SQL im Supabase-SQL-Editor ausführen',
        },
        HttpStatus.SERVICE_UNAVAILABLE,
      );
    }
    this.logger.warn(`${operation}: ${error?.message ?? 'unbekannt'}`);
    throw new HttpException(
      { error: 'DB_ERROR', message: error?.message ?? 'Datenbankfehler' },
      HttpStatus.INTERNAL_SERVER_ERROR,
    );
  }

  // ================= Sync (App -> Backend) =================

  /**
   * Synchronisiert EINE abgeschlossene Tour (Upsert auf user+externalId)
   * und leitet besuchte Orte ab. Auto-Sichtbarkeit: ist der Nutzer
   * öffentlich + shareRides, ist die neue Tour sofort geteilt (kann pro
   * Tour zurückgezogen werden); sonst privat.
   */
  async syncRide(user: AuthenticatedUser, dto: RideSyncDto): Promise<{ synced: boolean }> {
    const client = this.scoped(user);
    const track = (dto.track ?? []).slice(0, MAX_TRACK_POINTS);
    const pois = (dto.pois ?? []).slice(0, MAX_POIS);
    const photos = (dto.photos ?? []).slice(0, MAX_PHOTOS);
    const description = (dto.description ?? '').slice(0, MAX_DESC) || null;

    if (!dto.externalId || !dto.title || !dto.startedAt || !dto.endedAt) {
      throw new HttpException(
        { error: 'VALIDATION', message: 'externalId, title, startedAt, endedAt sind Pflicht' },
        HttpStatus.BAD_REQUEST,
      );
    }

    const region = await this.deriveRegion(track);

    // Aktuelle Privacy-Einstellungen (bestimmen Auto-Sichtbarkeit);
    // ride_history_enabled=false: der Nutzer will KEINE Historie -
    // nichts speichern (bewusst kein Schatten-Datensatz).
    const { data: profile, error: profileError } = await client
      .from('users')
      .select('ride_history_enabled, auth_privacy, share_rides')
      .eq('id', user.id)
      .maybeSingle();
    if (profileError) this.mapError('syncRide/profile', profileError);
    if (profile?.ride_history_enabled === false) return { synced: false };
    const autoPublic =
      (profile?.auth_privacy ?? 'private') === 'public' && (profile?.share_rides ?? false);

    const row = {
      user_id: user.id,
      external_id: dto.externalId,
      title: dto.title,
      started_at: dto.startedAt,
      ended_at: dto.endedAt,
      distance_meters: Number(dto.distanceMeters) || 0,
      duration_seconds: Number(dto.durationSeconds) || 0,
      elevation_gain_meters: Number(dto.elevationGainMeters) || 0,
      track,
      pois: pois.map((p) => ({ label: p.label, lat: p.lat, lng: p.lng })),
      start_label: dto.startLabel ?? null,
      end_label: dto.endLabel ?? null,
      start_lat: dto.startLat ?? null,
      start_lng: dto.startLng ?? null,
      end_lat: dto.endLat ?? null,
      end_lng: dto.endLng ?? null,
      region,
      description,
      photos,
      is_public: autoPublic,
      share_track: true,
    };

    const { error } = await client
      .from('ride_history')
      .upsert(row, { onConflict: 'user_id,external_id' });
    if (error) this.mapError('syncRide', error);

    await this.upsertPlaces(client, user.id, pois);
    return { synced: true };
  }

  /** Besuchte Orte upserten (visit_count erhöhen, last_visited setzen). */
  private async upsertPlaces(
    client: SupabaseClient,
    userId: string,
    pois: PlaceVisitInput[],
  ): Promise<void> {
    for (const poi of pois) {
      if (!poi.externalId || !poi.label) continue;
      const { data: existing, error: readError } = await client
        .from('place_visits')
        .select('id, visit_count')
        .eq('user_id', userId)
        .eq('external_id', poi.externalId)
        .maybeSingle();
      if (readError) this.mapError('upsertPlaces', readError);

      if (existing) {
        const { error } = await client
          .from('place_visits')
          .update({
            visit_count: (existing.visit_count ?? 1) + 1,
            last_visited_at: new Date().toISOString(),
          })
          .eq('id', existing.id);
        if (error) this.mapError('upsertPlaces/update', error);
      } else {
        const { error } = await client.from('place_visits').insert({
          user_id: userId,
          external_id: poi.externalId,
          category: poi.category ?? 'other',
          label: poi.label,
          lat: poi.lat,
          lng: poi.lng,
          visit_count: 1,
          last_visited_at: new Date().toISOString(),
        });
        if (error) this.mapError('upsertPlaces/insert', error);
      }
    }
  }

  /** Grob-Region aus der Track-Mitte (Stadtname, kein exakter Punkt). */
  private async deriveRegion(track: RideTrackPoint[]): Promise<string | null> {
    if (track.length === 0) return null;
    const mid = track[Math.floor(track.length / 2)];
    try {
      const hit = await this.search.reverse(mid.lat, mid.lng);
      return hit?.city ?? null;
    } catch (e) {
      this.logger.warn(`Region-Ableitung fehlgeschlagen: ${String(e)}`);
      return null;
    }
  }

  // ================= Eigene Daten + Einstellungen =================

  async getMyHistory(
    user: AuthenticatedUser,
  ): Promise<{ settings: Record<string, unknown>; rides: RideRow[]; places: unknown[] }> {
    const client = this.scoped(user);

    const { data: profile, error: profileError } = await client
      .from('users')
      .select(
        'ride_history_enabled, auth_privacy, share_rides, share_places, hide_start_end',
      )
      .eq('id', user.id)
      .maybeSingle();
    if (profileError) this.mapError('getMyHistory/profile', profileError);

    const { data: rides, error: ridesError } = await client
      .from('ride_history')
      .select('*')
      .eq('user_id', user.id)
      .order('started_at', { ascending: false });
    if (ridesError) this.mapError('getMyHistory/rides', ridesError);

    const { data: places, error: placesError } = await client
      .from('place_visits')
      .select('*')
      .eq('user_id', user.id)
      .order('last_visited_at', { ascending: false });
    if (placesError) this.mapError('getMyHistory/places', placesError);

    return {
      settings: {
        rideHistoryEnabled: profile?.ride_history_enabled ?? true,
        authPrivacy: profile?.auth_privacy ?? 'private',
        shareRides: profile?.share_rides ?? false,
        sharePlaces: profile?.share_places ?? false,
        hideStartEnd: profile?.hide_start_end ?? true,
      },
      rides: rides ?? [],
      places: places ?? [],
    };
  }

  async updatePrivacy(user: AuthenticatedUser, dto: PrivacyUpdateDto): Promise<{ updated: boolean }> {
    const client = this.scoped(user);

    const userPatch: Record<string, unknown> = {};
    if (dto.rideHistoryEnabled !== undefined) userPatch.ride_history_enabled = dto.rideHistoryEnabled;
    if (dto.authPrivacy !== undefined) userPatch.auth_privacy = dto.authPrivacy;
    if (dto.shareRides !== undefined) userPatch.share_rides = dto.shareRides;
    if (dto.sharePlaces !== undefined) userPatch.share_places = dto.sharePlaces;
    if (dto.hideStartEnd !== undefined) userPatch.hide_start_end = dto.hideStartEnd;

    if (Object.keys(userPatch).length > 0) {
      const { error } = await client.from('users').update(userPatch).eq('id', user.id);
      if (error) this.mapError('updatePrivacy/users', error);
    }

    // Pro-Tour-Sichtbarkeit (nur eigene Zeilen - RLS erzwingt das).
    for (const ride of dto.perRide ?? []) {
      const patch: Record<string, unknown> = { is_public: ride.isPublic };
      if (ride.shareTrack !== undefined) patch.share_track = ride.shareTrack;
      const { error } = await client
        .from('ride_history')
        .update(patch)
        .eq('user_id', user.id)
        .eq('external_id', ride.externalId);
      if (error) this.mapError('updatePrivacy/perRide', error);
    }

    for (const place of dto.perPlace ?? []) {
      const { error } = await client
        .from('place_visits')
        .update({ is_public: place.isPublic })
        .eq('user_id', user.id)
        .eq('external_id', place.externalId);
      if (error) this.mapError('updatePrivacy/perPlace', error);
    }

    return { updated: true };
  }

  // ================= Öffentliches Profil =================

  async getPublicProfile(viewer: AuthenticatedUser, ownerUserId: string): Promise<PublicProfileView> {
    const client = this.scoped(viewer);

    const { data: owner, error: ownerError } = await client
      .from('users')
      .select(
        'id, username, display_name, avatar_url, auth_privacy, share_rides, share_places, hide_start_end',
      )
      .eq('id', ownerUserId)
      .maybeSingle();
    if (ownerError) this.mapError('getPublicProfile/owner', ownerError);

    const displayName = owner?.display_name ?? owner?.username ?? null;
    const base: PublicProfileView = {
      profile: {
        userId: ownerUserId,
        displayName,
        username: owner?.username ?? null,
        avatarUrl: owner?.avatar_url ?? null,
        isPrivate: true,
      },
      history: {
        rideCount: 0,
        totalKm: 0,
        totalHours: 0,
        totalElevationGain: 0,
        regions: [],
        rides: [],
        places: [],
      },
    };

    // Kein Profil oder privat: nur Basisdaten, keine Historie.
    if (!owner || owner.auth_privacy !== 'public') return base;

    // RLS (ride_history_public_read / place_visits_public_read) filtert
    // Blockaden und Nicht-Freigegebenes auf DB-Ebene - hier nur noch
    // hide_start_end/share_track anwenden.
    const ridesPublic = owner.share_rides === true;
    const placesPublic = owner.share_places === true;
    const hideCoords = owner.hide_start_end !== false;

    let rides: RideRow[] = [];
    if (ridesPublic) {
      const { data, error } = await client
        .from('ride_history')
        .select('*')
        .eq('user_id', ownerUserId)
        .eq('is_public', true)
        .order('started_at', { ascending: false })
        .limit(100);
      if (error) this.mapError('getPublicProfile/rides', error);
      rides = data ?? [];
    }

    let places: Array<{
      external_id: string;
      category: string;
      label: string;
      lat: number;
      lng: number;
      visit_count: number;
      last_visited_at: string | null;
    }> = [];
    if (placesPublic) {
      const { data, error } = await client
        .from('place_visits')
        .select('external_id, category, label, lat, lng, visit_count, last_visited_at')
        .eq('user_id', ownerUserId)
        .order('visit_count', { ascending: false })
        .limit(200);
      if (error) this.mapError('getPublicProfile/places', error);
      places = data ?? [];
    }

    const rideViews: PublicRideView[] = rides.map((r) => ({
      externalId: r.external_id,
      title: r.title,
      startedAt: r.started_at,
      endedAt: r.ended_at,
      distanceMeters: r.distance_meters,
      durationSeconds: r.duration_seconds,
      elevationGainMeters: r.elevation_gain_meters,
      region: r.region,
      description: r.description,
      photos: r.photos ?? [],
      // share_track=false: Statistik bleibt, GPS-Linie wird gezogen.
      track:
        r.share_track === true
          ? (r.track ?? []).map((p) => ({ lat: p.lat, lng: p.lng }))
          : [],
      pois: r.pois ?? [],
      startLabel: r.start_label,
      endLabel: r.end_label,
      // hide_start_end: exakte Koordinaten NIE ausliefern (Labels bleiben).
      start:
        !hideCoords && r.start_lat != null && r.start_lng != null
          ? { lat: r.start_lat, lng: r.start_lng }
          : null,
      end:
        !hideCoords && r.end_lat != null && r.end_lng != null
          ? { lat: r.end_lat, lng: r.end_lng }
          : null,
    }));

    const regions = Array.from(
      new Set(rideViews.map((r) => r.region).filter((x): x is string => Boolean(x))),
    );

    return {
      profile: {
        userId: ownerUserId,
        displayName,
        username: owner.username ?? null,
        avatarUrl: owner.avatar_url ?? null,
        isPrivate: false,
      },
      history: {
        rideCount: rideViews.length,
        totalKm: rideViews.reduce((s, r) => s + r.distanceMeters, 0) / 1000,
        totalHours: rideViews.reduce((s, r) => s + r.durationSeconds, 0) / 3600,
        totalElevationGain: rideViews.reduce((s, r) => s + r.elevationGainMeters, 0),
        regions,
        rides: rideViews,
        places: places.map((p) => ({
          externalId: p.external_id,
          category: p.category,
          label: p.label,
          lat: p.lat,
          lng: p.lng,
          visitCount: p.visit_count,
          lastVisitedAt: p.last_visited_at,
        })),
      },
    };
  }
}
