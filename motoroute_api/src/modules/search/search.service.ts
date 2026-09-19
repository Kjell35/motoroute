import { HttpException, HttpStatus, Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import axios from 'axios';
import { SearchQueryDto, SearchResult } from './dto/search-query.dto';

/**
 * Wraps a self-hosted Photon/Nominatim instance (GEOCODING_URL env var,
 * see Phase 1/2 Teil B.3/H). Provider is intentionally injected via
 * config rather than hardcoded - the geocoding backend is one of the
 * "evaluate before committing" items and may change before MVP ships.
 *
 * Konkret implementiert gegen die Photon-API (/api?q=&lat=&lon=&lang=&limit=),
 * da Photon das GraphHopper-Ökosystem-Pendant ist und bias-by-location
 * nativ unterstützt. Nominatim hätte /search?q=&format=jsonv2 - das
 * Response-Mapping unterscheidet sich leicht und würde einen Adapter
 * pro Anbieter bedeuten; falls Nominatim gewählt wird, ist DAS HIER die
 * eine Datei, die sich ändert (gleiche Isolation wie GraphHopperClient).
 */
@Injectable()
export class SearchService {
  private readonly logger = new Logger(SearchService.name);

  constructor(private readonly config: ConfigService) {}

  async search(query: SearchQueryDto): Promise<SearchResult[]> {
    const geocodingUrl = this.config.get<string>('GEOCODING_URL');
    if (!geocodingUrl) {
      // Fails loudly as 503 rather than silently returning [] - unlike
      // the traffic module, search has no "acceptable to be off" state
      // in the MVP scope (Zielsuche is a core screen, Phase 1/2 Teil C.5).
      throw new HttpException(
        { error: 'GEOCODING_NOT_CONFIGURED', message: 'Search is not available' },
        HttpStatus.SERVICE_UNAVAILABLE,
      );
    }

    try {
      const params: Record<string, string | number> = {
        q: query.q,
        limit: 15,
        lang: 'de',
      };

      // Optionaler Standort-Bias: Photon sortiert Ergebnisse näher zum
      // Punkt weiter nach vorn - genau das, was Screen 5 (Zielsuche)
      // für "In der Nähe"-Kontext braucht.
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
      if (err instanceof HttpException) throw err;
      this.logger.error(`Geocoding request failed: ${err}`);
      throw new HttpException(
        { error: 'GEOCODING_UNAVAILABLE', message: 'Search is temporarily unavailable' },
        HttpStatus.SERVICE_UNAVAILABLE,
      );
    }
  }
}
