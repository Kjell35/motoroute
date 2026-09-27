import {
  BadRequestException,
  Inject,
  Injectable,
  ServiceUnavailableException,
} from '@nestjs/common';
import { SupabaseClient } from '@supabase/supabase-js';
import { AuthenticatedUser } from '../../guards';
import { SUPABASE_CLIENT } from '../../supabase/supabase.module';

/** Zeile aus der RPC-Funktion match_badge_at (siehe Migration 0009). */
export interface MatchedBadgeRow {
  badge_id: string;
  title: string;
  description: string;
  icon_url: string | null;
  required_category: string;
  distance_m: number;
  unlocked_now: boolean;
  total_user_badges: number;
}

/** Badge-Katalogzeile (für die Trophäenwand "alle verfügbaren"). */
export interface BadgeCatalogRow {
  id: string;
  title: string;
  description: string;
  icon_url: string | null;
  required_category: string;
  pass_lat: number;
  pass_lon: number;
  radius_meters: number;
}

export interface CheckinResult {
  /** Frisch in DIESEM Check-in freigeschaltet (für den Feier-Moment). */
  unlockedNow: {
    id: string;
    title: string;
    description: string;
    iconUrl: string | null;
    category: string;
    distanceMeters: number;
  }[];
  /** Bereits früher freigeschaltet, aber wieder im Radius gewesen. */
  revisited: { id: string; title: string; distanceMeters: number }[];
  /** Gesamtzahl der Badges des Nutzers nach diesem Check-in. */
  totalUnlocked: number;
}

@Injectable()
export class BadgesService {
  constructor(
    @Inject(SUPABASE_CLIENT) private readonly adminClient: SupabaseClient | null,
  ) {}

  /**
   * GPS-Check-in: Position an die PostGIS-RPC übergeben. Die DB macht
   * die Geometrie (ST_DWithin), die Idempotenz (ON CONFLICT) und die
   * Neuheits-Bestimmung in EINEM atomaren Query.
   */
  async checkin(user: AuthenticatedUser, lat: number, lon: number): Promise<CheckinResult> {
    if (!this.adminClient) {
      // Graceful Degradierung (Muster aus SupabaseModule): Ohne DB kein
      // Gamification, aber die App bleibt voll funktionsfähig.
      throw new ServiceUnavailableException({
        error: 'DB_NOT_CONFIGURED',
        message: 'Badges nicht konfiguriert',
      });
    }

    const { data, error } = await this.adminClient.rpc('match_badge_at', {
      p_lat: lat,
      p_lon: lon,
    });
    if (error) {
      // Die RPC wirft 'INVALID_COORDS' als Postgres-Exception -> message
      // enthält den Text. Alles andere (fehlende Funktion/PostGIS) ist
      // ein Deployment-Problem und wird sauber als 503 gemeldet.
      if (typeof error.message === 'string' && error.message.includes('INVALID_COORDS')) {
        throw new BadRequestException({
          error: 'INVALID_COORDS',
          message: 'Koordinaten außerhalb des gültigen Bereichs',
        });
      }
      throw new ServiceUnavailableException({
        error: 'BADGES_RPC_FAILED',
        message: error.message,
      });
    }

    const rows = (data ?? []) as MatchedBadgeRow[];
    const unlockedNow: CheckinResult['unlockedNow'] = [];
    const revisited: CheckinResult['revisited'] = [];
    let total = 0;
    for (const r of rows) {
      total = Number(r.total_user_badges ?? total);
      if (r.unlocked_now) {
        unlockedNow.push({
          id: r.badge_id,
          title: r.title,
          description: r.description,
          iconUrl: r.icon_url,
          category: r.required_category,
          distanceMeters: r.distance_m,
        });
      } else {
        revisited.push({ id: r.badge_id, title: r.title, distanceMeters: r.distance_m });
      }
    }
    return { unlockedNow, revisited, totalUnlocked: total };
  }

  /**
   * Trophäenschrank: Katalog + Freischaltungen gemischt. Badges ohne
   * Freischaltung kommen mit unlocked=false (grau dargestellt), mit
   * unlocked_at=null. Fehlerhafte Teilschläge werden als leer gemeldet,
   * damit die Wand nie halb bricht.
   */
  async myBadges(user: AuthenticatedUser): Promise<{
    badges: {
      id: string;
      title: string;
      description: string;
      iconUrl: string | null;
      category: string;
      lat: number;
      lon: number;
      radiusMeters: number;
      unlocked: boolean;
      unlockedAt: string | null;
    }[];
    unlockedCount: number;
    totalCount: number;
  }> {
    if (!this.adminClient) {
      throw new ServiceUnavailableException({
        error: 'DB_NOT_CONFIGURED',
        message: 'Badges nicht konfiguriert',
      });
    }

    const [catalogRes, mineRes] = await Promise.all([
      this.adminClient
        .from('badges')
        .select(
          'id, title, description, icon_url, required_category, pass_lat, pass_lon, radius_meters',
        )
        .order('required_category')
        .order('title'),
      this.adminClient
        .from('user_badges')
        .select('badge_id, unlocked_at')
        .eq('user_id', user.id),
    ]);
    if (catalogRes.error) {
      throw new ServiceUnavailableException({
        error: 'BADGES_READ_FAILED',
        message: catalogRes.error.message,
      });
    }

    const unlockedMap = new Map<string, string>();
    for (const row of (mineRes.data ?? []) as { badge_id: string; unlocked_at: string }[]) {
      unlockedMap.set(row.badge_id, row.unlocked_at);
    }

    const badges = ((catalogRes.data ?? []) as BadgeCatalogRow[]).map((b) => ({
      id: b.id,
      title: b.title,
      description: b.description,
      iconUrl: b.icon_url,
      category: b.required_category,
      lat: b.pass_lat,
      lon: b.pass_lon,
      radiusMeters: b.radius_meters,
      unlocked: unlockedMap.has(b.id),
      unlockedAt: unlockedMap.get(b.id) ?? null,
    }));

    return {
      badges,
      unlockedCount: badges.filter((b) => b.unlocked).length,
      totalCount: badges.length,
    };
  }
}
