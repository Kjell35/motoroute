import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import axios from 'axios';

export interface GeocodeHit {
  label: string;
  lat: number;
  lng: number;
  type: 'ADDRESS' | 'POI';
  postcode?: string;
  city?: string;
}

/**
 * TomTom-Geocoder (Search API v2): Orts-/Adress-/POI-Suche und
 * Reverse-Geocoding. Nutzt denselben TRAFFIC_API_KEY wie das Verkehrs-
 * Modul (Ein Key fuer alle TomTom-Zwecke, wie im Projekt vorgesehen).
 *
 * Der Key liegt NUR hier im BFF - die App kennt ihn nie. Antworten
 * werden transient gecacht (Suchbegriffe wiederholen sich beim Tippen,
 * Reverse-Lookups beim Wegpunkt-Setzen ebenso), um Rate-Limits zu
 * schonen. Ausfall degradiert: Der Aufrufer entscheidet, ob die Suche
 * dann noch eine Fallback-Quelle anbietet.
 */
@Injectable()
export class TomTomGeocoder {
  private readonly logger = new Logger(TomTomGeocoder.name);
  private readonly cache = new Map<
    string,
    { expiresAt: number; hits: GeocodeHit[] }
  >();

  private static readonly CACHE_TTL_MS = 5 * 60_000;
  private static readonly CACHE_MAX = 300;

  constructor(private readonly config: ConfigService) {}

  get isConfigured(): boolean {
    return Boolean(this.config.get<string>('TRAFFIC_API_KEY'));
  }

  private get apiKey(): string {
    return this.config.get<string>('TRAFFIC_API_KEY') ?? '';
  }

  /** Orts-/Adress-/POI-Suche (fwdGeocode, mit Standort-Bias). */
  async search(
    query: string,
    opts: { lat?: number; lng?: number; limit?: number } = {},
  ): Promise<GeocodeHit[]> {
    if (!this.isConfigured) return [];

    const cacheKey = `fwd:${query}:${opts.lat ?? ''},${opts.lng ?? ''}`;
    const cached = this.cache.get(cacheKey);
    if (cached && cached.expiresAt > Date.now()) return cached.hits;

    try {
      const { data } = await axios.get(
        `https://api.tomtom.com/search/2/search/${encodeURIComponent(query)}.json`,
        {
          params: {
            key: this.apiKey,
            limit: opts.limit ?? 15,
            language: 'de-DE',
            // Standort-Bias: naehere Ergebnisse weiter vorn (wie der
            // Photon-Bias zuvor - die App-Reihenfolge bleibt gleich).
            ...(opts.lat != null && opts.lng != null
              ? { lat: opts.lat, lon: opts.lng, radius: 50_000 }
              : {}),
          },
          timeout: 6000,
        },
      );

      const hits: GeocodeHit[] = (data.results ?? [])
        .map((r: any) => this.toHit(r))
        .filter(Boolean);
      this.cacheSet(cacheKey, hits);
      return hits;
    } catch (e) {
      this.logger.warn(`TomTom-Suche fehlgeschlagen: ${String(e)}`);
      return [];
    }
  }

  /** Koordinaten -> lesbarer Name (reverseGeocode). */
  async reverse(lat: number, lng: number): Promise<GeocodeHit | null> {
    if (!this.isConfigured) return null;

    // Auf 4 Dezimalen runden (~11 m): identische Punkte teilen den Cache.
    const cacheKey = `rev:${lat.toFixed(4)},${lng.toFixed(4)}`;
    const cached = this.cache.get(cacheKey);
    if (cached && cached.expiresAt > Date.now()) return cached.hits[0] ?? null;

    try {
      const { data } = await axios.get(
        `https://api.tomtom.com/search/2/reverseGeocode/${encodeURIComponent(
          `${lat},${lng}`,
        )}.json`,
        {
          params: { key: this.apiKey, language: 'de-DE' },
          timeout: 5000,
        },
      );

      const first = (data.addresses ?? [])[0];
      if (!first?.address) return null;
      const a = first.address;
      const hit: GeocodeHit = {
        label:
          a.freeformAddress ??
          [a.streetName, a.municipality].filter(Boolean).join(', ') ??
          'Kartenpunkt',
        lat,
        lng,
        type: 'ADDRESS',
        ...(a.postalCode ? { postcode: a.postalCode } : {}),
        ...(a.municipality ? { city: a.municipality } : {}),
      };
      this.cacheSet(cacheKey, [hit]);
      return hit;
    } catch (e) {
      this.logger.warn(`TomTom-Reverse-Geocoding fehlgeschlagen: ${String(e)}`);
      return null;
    }
  }

  private toHit(r: any): GeocodeHit | null {
    const pos = r.position ?? {};
    const lat = Number(pos.lat);
    const lng = Number(pos.lon);
    if (!Number.isFinite(lat) || !Number.isFinite(lng)) return null;
    const isPoi = r.poi != null;
    const address = r.address ?? {};
    const label: string =
      r.poi?.name ??
      address.freeformAddress ??
      [address.streetName, address.streetNumber]
        .filter(Boolean)
        .join(' ') ??
      'Unbekannter Ort';
    return {
      label,
      lat,
      lng,
      type: isPoi ? 'POI' : 'ADDRESS',
      ...(address.postalCode ? { postcode: address.postalCode } : {}),
      ...(address.municipality ? { city: address.municipality } : {}),
    };
  }

  private cacheSet(key: string, hits: GeocodeHit[]): void {
    this.cache.set(key, {
      expiresAt: Date.now() + TomTomGeocoder.CACHE_TTL_MS,
      hits,
    });
    if (this.cache.size > TomTomGeocoder.CACHE_MAX) {
      const now = Date.now();
      for (const [k, entry] of this.cache) {
        if (entry.expiresAt <= now) this.cache.delete(k);
      }
    }
  }
}
