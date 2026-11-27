import {
  BadRequestException,
  Inject,
  Injectable,
  Logger,
  ServiceUnavailableException,
} from '@nestjs/common';
import { SupabaseClient } from '@supabase/supabase-js';
import { randomInt } from 'crypto';
import { SUPABASE_CLIENT } from '../../supabase/supabase.module';

/**
 * „Route am Computer planen": Die App fordert ein Token an, zeigt es als
 * QR-Code; am Rechner werden die Punkte unter /plan/{TOKEN} eingetragen und
 * die App holt sie über GET /api/v1/pairing/{TOKEN} ab.
 *
 * Die Punkte liegen in `pairing_plans` (Supabase, Service-Role-Zugriff).
 * Der Ablauf ist zeitlich begrenzt: Nach PAIRING_TTL_SECONDS antworten
 * beide Endpunkte mit 404, damit alte Links nicht ewig offen bleiben.
 */
export interface PairingPoint {
  label: string;
  detail: string | null;
  lat: number;
  lon: number;
}

export interface PairingStart {
  token: string;
  plan_url: string;
  plan_urls: string[];
  expires_in_seconds: number;
}

/** 6 Zeichen aus einem Alphabet ohne I/O/0/1 (verwechslungssicher beim Abtippen). */
const TOKEN_ALPHABET = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
const TOKEN_LENGTH = 6;
export const PAIRING_TTL_SECONDS = 7200; // 2 Stunden
const MAX_POINTS = 50;
const MAX_LABEL = 120;
const MAX_DETAIL = 200;

@Injectable()
export class PairingService {
  private readonly logger = new Logger(PairingService.name);

  constructor(@Inject(SUPABASE_CLIENT) private readonly db: SupabaseClient | null) {}

  async start(origin: string): Promise<PairingStart> {
    const db = this.requireDb();
    const token = this.newToken();
    const expiresAt = new Date(Date.now() + PAIRING_TTL_SECONDS * 1000);
    const { error } = await db.from('pairing_plans').insert({
      token,
      points: [],
      expires_at: expiresAt.toISOString(),
    });
    if (error) {
      this.logger.error(`pairing start failed: ${error.code} ${error.message}`);
      throw new ServiceUnavailableException('Pairing konnte nicht gestartet werden.');
    }
    // Aufräumen ist Nebenwirkung, kein Grund den Start scheitern zu lassen.
    void this.purgeExpired(db);
    const planUrl = `${origin}/plan/${token}`;
    return {
      token,
      plan_url: planUrl,
      plan_urls: [planUrl],
      expires_in_seconds: PAIRING_TTL_SECONDS,
    };
  }

  /** Punkte des Tokens; `null` wenn unbekannt oder abgelaufen. */
  async getPoints(token: string): Promise<PairingPoint[] | null> {
    const db = this.requireDb();
    const { data, error } = await db
      .from('pairing_plans')
      .select('points')
      .eq('token', normalizeToken(token))
      .gt('expires_at', new Date().toISOString())
      .maybeSingle();
    if (error) {
      this.logger.error(`pairing read failed: ${error.code} ${error.message}`);
      throw new ServiceUnavailableException('Pairing ist derzeit nicht verfügbar.');
    }
    if (!data) return null;
    return parsePoints(data.points as unknown);
  }

  /** Speichert die Punkte; `null` wenn unbekannt oder abgelaufen. */
  async savePoints(token: string, raw: unknown): Promise<PairingPoint[] | null> {
    const points = parsePoints(raw);
    const db = this.requireDb();
    const { data, error } = await db
      .from('pairing_plans')
      .update({ points })
      .eq('token', normalizeToken(token))
      .gt('expires_at', new Date().toISOString())
      .select('token')
      .maybeSingle();
    if (error) {
      this.logger.error(`pairing save failed: ${error.code} ${error.message}`);
      throw new ServiceUnavailableException('Punkte konnten nicht gespeichert werden.');
    }
    if (!data) return null;
    return points;
  }

  private requireDb(): SupabaseClient {
    if (!this.db) {
      throw new ServiceUnavailableException(
        'Pairing ist nicht konfiguriert (Supabase-Zugang fehlt).',
      );
    }
    return this.db;
  }

  private newToken(): string {
    let out = '';
    for (let i = 0; i < TOKEN_LENGTH; i += 1) {
      out += TOKEN_ALPHABET[randomInt(TOKEN_ALPHABET.length)];
    }
    return out;
  }

  private async purgeExpired(db: SupabaseClient): Promise<void> {
    const { error } = await db
      .from('pairing_plans')
      .delete()
      .lt('expires_at', new Date().toISOString());
    if (error) {
      this.logger.warn(`pairing purge failed: ${error.code} ${error.message}`);
    }
  }
}

export function normalizeToken(token: string | undefined): string {
  return (token ?? '').trim().toUpperCase();
}

function parsePoints(raw: unknown): PairingPoint[] {
  if (!Array.isArray(raw)) {
    throw new BadRequestException('points muss eine Liste sein');
  }
  if (raw.length > MAX_POINTS) {
    throw new BadRequestException(`höchstens ${MAX_POINTS} Punkte pro Plan`);
  }
  return raw.map((entry, index) => {
    if (typeof entry !== 'object' || entry === null) {
      throw new BadRequestException(`Punkt ${index + 1} ist ungültig`);
    }
    const item = entry as Record<string, unknown>;
    const lat = Number(item.lat);
    const lon = Number(item.lon);
    if (!Number.isFinite(lat) || lat < -90 || lat > 90) {
      throw new BadRequestException(`Punkt ${index + 1}: lat muss zwischen -90 und 90 liegen`);
    }
    if (!Number.isFinite(lon) || lon < -180 || lon > 180) {
      throw new BadRequestException(`Punkt ${index + 1}: lon muss zwischen -180 und 180 liegen`);
    }
    const label = typeof item.label === 'string' ? item.label.trim() : '';
    const detail = typeof item.detail === 'string' ? item.detail.trim() : '';
    return {
      label: (label || `Wegpunkt ${index + 1}`).slice(0, MAX_LABEL),
      detail: detail ? detail.slice(0, MAX_DETAIL) : null,
      lat,
      lon,
    };
  });
}
