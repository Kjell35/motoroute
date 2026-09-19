import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { Inject, HttpException, HttpStatus } from '@nestjs/common';
import { SUPABASE_CLIENT } from '../../supabase/supabase.module';
import { SupabaseClient } from '@supabase/supabase-js';
import axios from 'axios';
import { Poi, PoiSource } from './entities/poi.entity';
import { QueryPoisDto, PoiCategory } from './dto/query-pois.dto';

const OVERPASS_TIMEOUT_MS = 8000;

/**
 * Overpass-Queries je Kategorie.
 *
 * FUEL/CAMPSITE/ICE_CREAM: OSM liefert diese Kategorien zuverlässig.
 * SPEED_CAMERA: `highway=speed_camera` und `enforcement=maxspeed` -
 * in DE legal nutzbar (keine Störfall-Verordnung wie für Radarfalle-
 * Apps), trotzdem bewusst als Warnhinweis gekennzeichnet.
 * MOTO_HOTEL/BIKER_MEETUP: OSM-Tags sind SPÄRLICH - die Queries
 * fangen, was da ist; die Lücke füllt die eigene poi-Tabelle
 * (CURATED/COMMUNITY), die parallel abgefragt wird. Siehe Phase 1/2
 * Herausforderung A.2 Punkt 2.
 */
const OVERPASS_QUERIES: Record<string, string> = {
  [PoiCategory.FUEL]: 'node["amenity"="fuel"]',
  [PoiCategory.CAMPSITE]: 'node["tourism"="camp_site"]',
  [PoiCategory.ICE_CREAM]: 'node["amenity"="ice_cream"]',
  [PoiCategory.SPEED_CAMERA]:
    'node["highway"="speed_camera"]',
  [PoiCategory.MOTO_HOTEL]:
    'node["tourism"="hotel"]["motorcycle:yes"="yes"]',
  [PoiCategory.BIKER_MEETUP]:
    'node["amenity"="biker_meetup"]',
};

/**
 * Zusätzlich akzeptierte OSM-Tags pro Kategorie für die Anzeige -
 * z. B. ein `tourism=hotel` ohne Motorrad-Tag bleibt trotzdem ein
 * Hotel, wird aber nur bei aktivem Motorradhotels-Layer mitgeliefert,
 * wenn es das explizite Tag trägt.
 */
@Injectable()
export class PoiService {
  private readonly logger = new Logger(PoiService.name);

  constructor(
    private readonly config: ConfigService,
    @Inject(SUPABASE_CLIENT) private readonly supabase: SupabaseClient | null,
  ) {}

  async findInBoundingBox(query: QueryPoisDto): Promise<Poi[]> {
    const [minLng, minLat, maxLng, maxLat] = query.bbox;
    const categories = query.categories;

    const results: Poi[] = [];

    // Kategorien, die aus OSM kommen (Overpass) - alle 6 Kategorien
    // haben jetzt eine Query; die eigene Tabelle ergänzt kuratierte
    // Motorradhotels/Biker-Treffs, die OSM nicht (zuverlässig) hat.
    const osmCategories = categories;
    const dbCategories = categories;

    // Beide Quellen parallel abfragen
    const [osmResults, dbResults] = await Promise.all([
      this.queryOsm(osmCategories, minLng, minLat, maxLng, maxLat),
      this.queryDatabase(dbCategories, minLng, minLat, maxLng, maxLat),
    ]);

    return [...osmResults, ...dbResults];
  }

  /**
   * Abfrage über die Overpass API für OSM-Daten (Tankstellen).
   * Die Overpass-URL wird über die ENV-Variable OVERPASS_URL konfiguriert.
   * Fallback: wenn Overpass nicht konfiguriert ist, wird leere Liste
   * zurückgegeben (kein Crash, siehe Phase 1/2 Teil B.5 für den
   * bewusst offenen Verkehr-Provider).
   */
  private async queryOsm(
    categories: PoiCategory[],
    minLng: number,
    minLat: number,
    maxLng: number,
    maxLat: number,
  ): Promise<Poi[]> {
    if (categories.length === 0) return [];

    const overpassUrl = this.config.get<string>('OVERPASS_URL');
    if (!overpassUrl) {
      this.logger.warn('OVERPASS_URL is not configured - skipping OSM POI query');
      return [];
    }

    const bbox = `(${minLat},${minLng},${maxLat},${maxLng})`;
    const selectors = categories
      .map((c) => OVERPASS_QUERIES[c])
      .filter(Boolean)
      .map((selector) => `${selector}${bbox};`)
      .join('\n          ');

    try {
      // Eine Overpass-Anfrage für alle aktiven Kategorien statt einer
      // pro Kategorie - Overpass ist das Engpass-Backend, Rate-Limits
      // respektieren ist Betriebskosten- und Durability-Frage.
      const query = `
        [out:json][timeout:25];
        (
          ${selectors}
        );
        out body;`;

      const { data } = await axios.post(
        overpassUrl,
        `data=${encodeURIComponent(query)}`,
        { timeout: OVERPASS_TIMEOUT_MS },
      );

      return (data.elements ?? [])
        .map((el: any) => this.mapOsmElement(el))
        .filter((poi: Poi | null): poi is Poi => poi !== null);
    } catch (err) {
      this.logger.error(`Overpass query failed: ${err}`);
      return [];
    }
  }

  /**
   * Ordnet ein Overpass-Element seiner MotoRoute-Kategorie zu.
   * Returns null, wenn das Element keine aktive Kategorie matcht.
   */
  private mapOsmElement(el: any): Poi | null {
    const tags = el.tags ?? {};
    const lat = el.lat;
    const lng = el.lon;
    if (lat == null || lng == null) return null;

    let category: PoiCategory | null = null;
    let name = 'Unbenannt';

    if (tags['amenity'] === 'fuel') {
      category = PoiCategory.FUEL;
      name = tags['name'] ?? 'Tankstelle';
    } else if (tags['tourism'] === 'camp_site') {
      category = PoiCategory.CAMPSITE;
      name = tags['name'] ?? 'Campingplatz';
    } else if (tags['amenity'] === 'ice_cream') {
      category = PoiCategory.ICE_CREAM;
      name = tags['name'] ?? 'Eisdiele';
    } else if (tags['highway'] === 'speed_camera' || tags['enforcement']) {
      category = PoiCategory.SPEED_CAMERA;
      name = 'Blitzer';
    } else if (tags['tourism'] === 'hotel') {
      category = PoiCategory.MOTO_HOTEL;
      name = tags['name'] ?? 'Motorradhotel';
    } else if (tags['amenity'] === 'biker_meetup') {
      category = PoiCategory.BIKER_MEETUP;
      name = tags['name'] ?? 'Biker-Treff';
    }

    if (!category) return null;

    return {
      id: `osm-${el.type ?? 'node'}-${el.id}`,
      category,
      name,
      lat,
      lng,
      source: PoiSource.OSM,
      metadata: {
        brand: tags['brand'],
        opening_hours: tags['opening_hours'],
        website: tags['website'],
        maxspeed: tags['maxspeed'],
      },
    };
  }

  /**
   * Abfrage gegen die eigene `poi`-Tabelle in Supabase/PostGIS.
   * Nutzt PostGIS-Funktionen für effiziente räumliche Abfragen.
   */
  private async queryDatabase(
    categories: PoiCategory[],
    minLng: number,
    minLat: number,
    maxLng: number,
    maxLat: number,
  ): Promise<Poi[]> {
    // Kein Supabase konfiguriert (lokale Dev ohne echte Keys): die
    // kuratierten Kategorien liefern dann einfach nichts - OSM-POIs
    // laufen unbeeinträchtigt weiter.
    if (this.supabase == null) return [];
    if (categories.length === 0) return [];

    const { data, error } = await this.supabase
      .from('poi')
      .select('*')
      .in('category', categories)
      .filter('geom', 'st_within', `ST_MakeEnvelope(${minLng},${minLat},${maxLng},${maxLat},4326)`);

    if (error) {
      this.logger.error(`POI database query failed: ${error.message}`);
      throw new HttpException(
        { error: 'DB_ERROR', message: error.message },
        HttpStatus.INTERNAL_SERVER_ERROR,
      );
    }

    return (data ?? []).map((row: any) => ({
      id: row.id,
      category: row.category as PoiCategory,
      name: row.name,
      lat: row.lat,
      lng: row.lng,
      source: row.source,
      metadata: row.metadata,
    }));
  }
}