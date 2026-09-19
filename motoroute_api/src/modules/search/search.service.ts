import { HttpException, HttpStatus, Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import axios from 'axios';
import { SearchQueryDto, SearchResult } from './dto/search-query.dto';
import { TomTomGeocoder } from './tomtom-geocoder';

/**
 * Ortssuche des BFF. Provider-Kette:
 *
 *   1. TomTom Search API v2 (TRAFFIC_API_KEY, immer da wenn Verkehr an)
 *   2. Photon/Nominatim (GEOCODING_URL) - selbst gehostet, Fallback
 *   3. Beide nicht konfiguriert -> 503 mit klarem Fehler
 *
 * Frueher war Photon die einzige Quelle (503 ohne selbst gehosteten
 * Server) - fuer den Praxiseinsatz ("App fuer Papa") ist die Suche
 * Kernfunktion, daher liefert sie jetzt out-of-the-box ueber den
 * vorhandenen TomTom-Key. Die App kennt den Provider nie.
 */
@Injectable()
export class SearchService {
  private readonly logger = new Logger(SearchService.name);

  constructor(
    private readonly config: ConfigService,
    private readonly tomtom: TomTomGeocoder,
  ) {}

  async search(query: SearchQueryDto): Promise<SearchResult[]> {
    const near = parseNear(query.near);

    // 1) TomTom (Key aus dem Verkehrs-Modul) - der schnelle Standardweg.
    if (this.tomtom.isConfigured) {
      const hits = await this.tomtom.search(query.q, {
        ...(near ? { lat: near[0], lng: near[1] } : {}),
      });
      if (hits.length > 0) return hits;
      // Leeres Ergebnis ist legitim (Tippfehler); Netzfehler ebenfalls -
      // beides faellt durch zum Photon, falls vorhanden.
    }

    // 2) Photon-Fallback.
    const geocodingUrl = this.config.get<string>('GEOCODING_URL');
    if (!geocodingUrl) {
      if (!this.tomtom.isConfigured) {
        // Kein Provider konfiguriert: bewusst laut 503 statt stiller
        // Leere - die Zielsuche ist Kern-Screen (Phase 1/2 Teil C.5).
        throw new HttpException(
          {
            error: 'GEOCODING_NOT_CONFIGURED',
            message:
              'Kein Such-Provider konfiguriert (TRAFFIC_API_KEY oder GEOCODING_URL setzen)',
          },
          HttpStatus.SERVICE_UNAVAILABLE,
        );
      }
      // TomTom konfiguriert, aber ohne Treffer: leere Liste ist das
      // ehrliche Ergebnis (kein Fake-Fehler).
      return [];
    }

    return this.searchPhoton(query, geocodingUrl);
  }

  /** Koordinaten -> lesbarer Name (Wegpunkt-Labels, Kartentap). */
  async reverse(lat: number, lng: number): Promise<SearchResult | null> {
    const hit = await this.tomtom.reverse(lat, lng);
    if (!hit) return null;
    return {
      label: hit.label,
      lat: hit.lat,
      lng: hit.lng,
      type: hit.type,
      ...(hit.postcode ? { postcode: hit.postcode } : {}),
      ...(hit.city ? { city: hit.city } : {}),
    };
  }

  /** Photon/Nominatim-Suche (ehemaliger Hauptpfad, jetzt Fallback). */
  private async searchPhoton(
    query: SearchQueryDto,
    geocodingUrl: string,
  ): Promise<SearchResult[]> {
    try {
      const params: Record<string, string | number> = {
        q: query.q,
        limit: 15,
        lang: 'de',
      };

      if (query.near) {
        const [lat, lng] = query.near.split(',').map(Number);
        if (Number.isFinite(lat) && Number.isFinite(lng)) {
          params.lat = lat;
          params.lon = lng;
        }
      }

      const { data } = await axios.get(`${geocodingUrl.replace(/\/$/, '')}/api`, {
        params,
        timeout: 5000,
      });

      return (data.features ?? []).map((f: any) => {
        const props = f.properties ?? {};
        const label =
          props.name ??
          [props.street, props.housenumber].filter(Boolean).join(' ') ??
          props.city ??
          query.q;
        return {
          label,
          lat: f.geometry.coordinates[1],
          lng: f.geometry.coordinates[0],
          type: props.osm_value ? ('POI' as const) : ('ADDRESS' as const),
          ...(props.postcode ? { postcode: props.postcode } : {}),
          ...(props.city ? { city: props.city } : {}),
          ...(props.distance != null ? { distanceMeters: props.distance } : {}),
        };
      });
    } catch (err) {
      this.logger.error(`Geocoding request failed: ${err}`);
      throw new HttpException(
        { error: 'GEOCODING_FAILED', message: 'Search failed' },
        HttpStatus.BAD_GATEWAY,
      );
    }
  }
}

function parseNear(near?: string): [number, number] | null {
  if (!near) return null;
  const [lat, lng] = near.split(',').map(Number);
  return Number.isFinite(lat) && Number.isFinite(lng) ? [lat, lng] : null;
}
