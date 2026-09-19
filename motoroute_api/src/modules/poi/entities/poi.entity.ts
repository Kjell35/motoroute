import { PoiCategory } from '../dto/query-pois.dto';

export enum PoiSource {
  OSM = 'OSM',
  COMMUNITY = 'COMMUNITY',
  CURATED = 'CURATED',
}

/**
 * Mirrors the POI entity from Phase 1/2 Teil E. FUEL will initially be
 * served straight from OSM at query time; MOTO_HOTEL/BIKER_MEETUP are
 * not reliably tagged in OSM (see Phase 1/2, Herausforderung A.2 Punkt
 * 2) and are expected to live mostly in the CURATED/COMMUNITY rows of
 * our own poi table once persistence is built - this entity shape
 * already accounts for that split via `source`.
 */
export class Poi {
  id: string;
  category: PoiCategory;
  name: string;
  lat: number;
  lng: number;
  source: PoiSource;
  metadata?: Record<string, unknown>;
}
