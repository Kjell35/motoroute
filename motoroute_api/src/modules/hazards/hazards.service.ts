import {
  ForbiddenException,
  GoneException,
  Inject,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { createClient, SupabaseClient } from '@supabase/supabase-js';
import { ConfigService } from '@nestjs/config';
import { AuthenticatedUser } from '../../guards';
import { SUPABASE_CLIENT } from '../../supabase/supabase.module';

/**
 * HazardsService - Community-Gefahrenradar (Rollsplitt, Sperrung,
 * Baustelle, Ölspur).
 *
 * Architektur wie im Chat/GroupRides: Supabase wird mit dem USER-JWT
 * aufgerufen, d. h. RLS + SECURITY DEFINER-RPCs bleiben die DURCHSET-
 * ZENDE Schicht (Upvote-Deduplizierung, Ablauf-Validierung, Konsolide-
 * rung passieren in der Datenbank - ein manipulierter Client kann sie
 * nicht umgehen). Der Service übersetzt nur SQL-Fehlercodes in HTTP.
 */
@Injectable()
export class HazardsService {
  private readonly supabaseUrl: string;
  private readonly supabaseAnonKey: string;

  constructor(
    @Inject(SUPABASE_CLIENT) private readonly adminClient: SupabaseClient | null,
    config: ConfigService,
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

  /** Neue Gefahrenmeldung (Konsolidierung passiert im RPC). */
  async createReport(
    user: AuthenticatedUser,
    dto: { reportType: string; lat: number; lng: number; description?: string },
  ): Promise<unknown> {
    const db = this.scoped(user);
    const { data, error } = await db.rpc('hazard_report_create', {
      p_type: dto.reportType,
      p_lat: dto.lat,
      p_lng: dto.lng,
      p_description: dto.description ?? '',
    });
    if (error) this.mapError(error);
    return data;
  }

  /** Aktive Gefahren im Umkreis (24-h-Ablauf im RPC). */
  async nearby(
    user: AuthenticatedUser,
    query: { lat: number; lon: number; radiusKm?: number },
  ): Promise<unknown[]> {
    const db = this.scoped(user);
    const { data, error } = await db.rpc('hazard_report_nearby', {
      p_lat: query.lat,
      p_lng: query.lon,
      p_radius_m: (query.radiusKm ?? 50) * 1000,
    });
    if (error) this.mapError(error);
    return (data as unknown[]) ?? [];
  }

  /** Upvote mit "Gefahr existiert noch"-Validierung (im RPC). */
  async upvote(user: AuthenticatedUser, id: string): Promise<unknown> {
    const db = this.scoped(user);
    const { data, error } = await db.rpc('hazard_report_upvote', { p_id: id });
    if (error) this.mapError(error);
    return data;
  }

  private mapError(error: { code?: string; message?: string }): never {
    const msg = error.message ?? '';
    if (msg.includes('NOT_FOUND') || error.code === 'P0002') {
      throw new NotFoundException({ error: 'HAZARD_NOT_FOUND', message: 'Meldung nicht gefunden' });
    }
    if (msg.includes('EXPIRED')) {
      // 410 Gone: die Meldung existiert nicht mehr als aktive Gefahr -
      // der Client entfernt den Marker statt den Upvote zu wiederholen.
      throw new GoneException({
        error: 'HAZARD_EXPIRED',
        message: 'Diese Meldung ist abgelaufen - die Gefahr wurde vermutlich beseitigt',
      });
    }
    if (msg.includes('not authenticated')) {
      throw new ForbiddenException({ error: 'AUTH_REQUIRED', message: 'Token ungültig' });
    }
    throw new Error(`hazard RPC failed: ${error.code} ${msg}`);
  }
}
