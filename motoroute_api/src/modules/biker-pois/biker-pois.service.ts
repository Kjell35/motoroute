import { Inject, Injectable, Logger } from '@nestjs/common';
import axios from 'axios';
import { ConfigService } from '@nestjs/config';
import { SUPABASE_CLIENT } from '../../supabase/supabase.module';
import type { SupabaseClient } from '@supabase/supabase-js';

/**
 * Kategorie-Mapping: Biker-POI-Dienst (deutsche, kleingeschriebene
 * Kategorien) -> MotoRoute-App-Kategorien (UPPER_SNAKE). Die drei neuen
 * App-Kategorien (RESTAURANT/PUB/SNACK) ergänzen die bestehenden 6 -
 * GARTENLOKAL und PENSION werden auf Bestandskategorien abgebildet
 * (Biker-Treff bzw. Moto-Hotel), damit die App-UI stabil bleibt.
 */
const CATEGORY_MAP: Record<string, string> = {
  restaurant: 'RESTAURANT',
  kneipe: 'PUB',
  imbiss: 'SNACK',
  bikertreff: 'BIKER_MEETUP',
  gartenlokal: 'BIKER_MEETUP',
  pension: 'MOTO_HOTEL',
  hotel: 'MOTO_HOTEL',
  zeltplatz: 'CAMPSITE',
};

interface BikerPoiDto {
  id: string;
  name: string;
  category: string;
  lat: number;
  lon: number;
  address?: string;
  bikerScore: number;
  amenities: Record<string, unknown>;
  updatedAt: string;
}

/**
 * BikerPoisService - BFF-Proxy zum eigenständigen Biker-POI-Dienst
 * (motoroute_poi_service, TomTom-basierte Kuratierung mit Biker-Score).
 *
 * Architektur-Regeln:
 * - Der Dienst hat SEINEN eigenen TomTom-Key und seine eigene DB; das BFF
 *   besitzt nur die SERVER_BIKER_POI_URL - es kennt keine POI-Datenbank.
 * - Nur ANMELDETE Nutzer dürfen den Delta-Sync nutzen (Auth-Enforcement
 *   passiert hier am BFF; der POI-Dienst selbst prüft im eigenen Netz).
 * - 60-s-TTL-Cache: identische Delta-Anfragen mehrerer Clients in kurzer
 *   Zeit kosten nur EINE Weiterleitung (der Scan aktualisiert die POIs
 *   ohnehin nur einmal täglich; Echtzeit läuft im Dienst über Socket.IO).
 * - Ausfall des Dienstes degradiert sauber zu einer leeren Antwort - die
 *   OSM-POIs der Karte laufen unabhängig davon weiter.
 */
@Injectable()
export class BikerPoisService {
  private readonly logger = new Logger(BikerPoisService.name);
  private readonly baseUrl: string;

  /** TTL-Cache: Delta-Antworten sind 60 s frisch (transient, Lizenz). */
  private cache = new Map<string, { data: unknown; expiresAt: number }>();
  private static readonly CACHE_TTL_MS = 60_000;

  constructor(
    @Inject(SUPABASE_CLIENT) private readonly adminClient: SupabaseClient | null,
    config: ConfigService,
  ) {
    this.baseUrl = (config.get<string>('BIKER_POI_SERVICE_URL') ?? '').replace(/\/$/, '');
  }

  get configured(): boolean {
    return this.baseUrl.length > 0 && this.adminClient != null;
  }

  private cacheKey(path: string, params: Record<string, string | undefined>): string {
    return path + '?' + JSON.stringify(params);
  }

  private async cached(path: string, params: Record<string, string | undefined>): Promise<unknown> {
    const key = this.cacheKey(path, params);
    const hit = this.cache.get(key);
    if (hit && hit.expiresAt > Date.now()) return hit.data;

    const res = await axios.get(`${this.baseUrl}${path}`, {
      params: Object.fromEntries(Object.entries(params).filter(([, v]) => v !== undefined)),
      timeout: 8000,
    });
    this.cache.set(key, { data: res.data, expiresAt: Date.now() + BikerPoisService.CACHE_TTL_MS });
    // Cache-Größe begrenzen: Delta-Sync kommt mit wenigen Parameter-
    // Kombinationen vor; bei Überschreitung ältestes Element verwerfen.
    if (this.cache.size > 100) {
      const oldest = this.cache.keys().next().value;
      if (oldest) this.cache.delete(oldest);
    }
    return res.data;
  }

  /**
   * Delta-Sync: Änderungen seit `since`, optional umkreis-/kategorien-
   * gefiltert. Liefert app-seitige Kategorienamen (gemappt) und ein
   * `since`-Feld als neuen Cursor.
   */
  async sync(query: {
    since: string;
    lat?: number;
    lon?: number;
    radiusKm?: number;
    categories?: string;
  }): Promise<{ since: string; hasMore: boolean; pois: BikerPoiDto[]; deletedIds: string[] }> {
    const params: Record<string, string | undefined> = {
      since: query.since,
      lat: query.lat?.toString(),
      lon: query.lon?.toString(),
      radiusKm: query.radiusKm?.toString(),
      categories: query.categories,
    };

    const data = (await this.cached('/api/pois/sync', params)) as {
      serverTime: string;
      hasMore: boolean;
      upserted: Array<Record<string, unknown>>;
      deletedIds: string[];
    };

    const pois: BikerPoiDto[] = (data.upserted ?? [])
      .map((r) => ({
        id: `biker-${r['id']}`, // Namensraum-Trennung zu OSM-POI-UUIDs
        name: String(r['name'] ?? ''),
        category: CATEGORY_MAP[String(r['category'] ?? '')] ?? 'OTHER',
        lat: Number(r['lat']),
        lon: Number(r['lon']),
        address: r['address'] as string | undefined,
        bikerScore: Number(r['bikerScore'] ?? 0),
        amenities: (r['amenities'] ?? {}) as Record<string, unknown>,
        updatedAt: String(r['updatedAt'] ?? ''),
      }))
      .filter((p) => Number.isFinite(p.lat) && Number.isFinite(p.lon));

    return {
      since: data.serverTime,
      hasMore: data.hasMore ?? false,
      pois,
      deletedIds: (data.deletedIds ?? []).map((id) => `biker-${id}`),
    };
  }

  /** Service-Status für Health/Debugging. */
  status(): { configured: boolean; cacheSize: number } {
    return { configured: this.baseUrl.length > 0, cacheSize: this.cache.size };
  }
}
