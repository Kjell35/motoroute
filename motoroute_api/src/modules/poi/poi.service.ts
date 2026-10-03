import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { Inject, HttpException, HttpStatus } from '@nestjs/common';
import { SUPABASE_CLIENT } from '../../supabase/supabase.module';
import { SupabaseClient } from '@supabase/supabase-js';
import axios from 'axios';
import { Poi, PoiSource } from './entities/poi.entity';
import { PoiDetail } from './poi.detail';
import { QueryPoisDto, PoiCategory } from './dto/query-pois.dto';

const OVERPASS_TIMEOUT_MS = 8000;
const TOMTOM_TIMEOUT_MS = 6000;
const CURATED_CACHE_TTL_MS = 30 * 60 * 1000; // 30 min: Karten-Daten, kein Echtzeitfall

/**
 * Overpass-Queries je Kategorie.
 *
 * FUEL/CAMPSITE/ICE_CREAM: OSM liefert diese Kategorien zuverlässig.
 * SPEED_CAMERA: `highway=speed_camera` und `enforcement=maxspeed` -
 * in DE legal nutzbar (keine Störfall-Verordnung wie für Radarfalle-
 * Apps), trotzdem bewusst als Warnhinweis gekennzeichnet.
 * MOTO_HOTEL/BIKER_MEETUP: OSM-Tags sind SPÄRLICH - die Queries
 * fangen, was da ist; die Lücke füllt die TomTom-Kuratierung
 * (queryCurated), die parallel läuft und in der poi-Tabelle cacht.
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
 * TomTom-Kuratierung: Biker-Kategorien, die Overpass nicht (zuverlässig)
 * liefert, kommen on-demand aus der TomTom Search API (categorySearch).
 * Mapping: App-Kategorie -> TomTom-Category-Set-ID + Suchbegriff.
 *
 * Category-Set-IDs (TomTom v2, stabil dokumentiert):
 *   7315 = German Restaurant, 7315014 = Restaurant, 9376006 = Pub,
 *   9376046 = Fast Food, 7316 = Hotel, 9361063 = Campsite/Parking,
 *   Eisdielen (7319 Eiscafé) über Textsuche.
 */
const CURATED_TOMTOM: Partial<Record<PoiCategory, { setId: string; query: string }>> = {
  [PoiCategory.MOTO_HOTEL]: { setId: '7316', query: 'hotel' },
  [PoiCategory.BIKER_MEETUP]: { setId: '7315014', query: 'restaurant' },
  [PoiCategory.RESTAURANT]: { setId: '7315014', query: 'restaurant' },
  [PoiCategory.PUB]: { setId: '9376006', query: 'pub' },
  [PoiCategory.SNACK]: { setId: '9376046', query: 'fast food' },
};

/**
 * Biker-Score (Port aus motoroute_poi_service/classifier.js): 0-100,
 * wie bikertauglich ist der Ort. Heuristik bewusst einfach - der Wert
 * ist ein Sortier-/Anzeige-Merkmal, keine Entscheidung.
 */
const BIKER_KEYWORDS = /biker|motorrad|motorcycle|harley|\bmc\b/i;

/** Google Places API (New): Timeout + TTL-Cache für Detail-Anreicherung. */
const GOOGLE_TIMEOUT_MS = 6000;
const GOOGLE_ENRICH_TTL_MS = 24 * 60 * 60 * 1000; // Detail-Daten ändern sich selten
const GOOGLE_ENRICH_CACHE_MAX = 2000;

// Wikimedia-Policy: aussagekräftiger User-Agent ist Pflicht (WMF UA-Policy).
const WIKIMEDIA_UA = 'MotoRoute-Backend/1.0 (https://github.com/Kjell35/motoroute)';

interface GoogleEnrichment {
  description: string | null;
  website: string | null;
  imageUrl: string | null; // Backend-relativer Foto-Proxy-Pfad
  googleMapsUri: string | null;
  googleSummary: string | null;
  photoAttribution: string | null;
  matched: boolean;
}

interface WikiImage {
  imageUrl: string; // Direkte Commons-Thumbnail-URL (keyless, frei)
  photoAttribution: string;
}

function computeBikerScore(category: PoiCategory, name: string): number {
  let score = 40;
  if (category === PoiCategory.BIKER_MEETUP) score += 35;
  if (category === PoiCategory.MOTO_HOTEL) score += 10;
  if (category === PoiCategory.CAMPSITE) score += 5;
  if (BIKER_KEYWORDS.test(name)) score += 15;
  return Math.max(0, Math.min(100, score));
}

/**
 * Deduplizierung: gleicher Name (normalisiert) im ~75-m-Radius gilt als
 * derselbe Ort (Port der 75-m-Regel aus dem POI-Dienst). OSM gewinnt -
 * seine IDs sind stabiler und community-gepflegt.
 */
function nameKey(name: string): string {
  return name.toLowerCase().replace(/[^a-z0-9äöüß]/g, '');
}

function haversineMeters(aLat: number, aLng: number, bLat: number, bLng: number): number {
  const R = 6_371_000;
  const dLat = ((bLat - aLat) * Math.PI) / 180;
  const dLng = ((bLng - aLng) * Math.PI) / 180;
  const s =
    Math.sin(dLat / 2) ** 2 +
    Math.cos((aLat * Math.PI) / 180) * Math.cos((bLat * Math.PI) / 180) * Math.sin(dLng / 2) ** 2;
  return 2 * R * Math.asin(Math.sqrt(s));
}

function dedupe(pois: Poi[]): Poi[] {
  const kept: Poi[] = [];
  for (const poi of pois) {
    const dup = kept.find(
      (k) =>
        k.nameKey === poi.nameKey &&
        haversineMeters(k.lat, k.lng, poi.lat, poi.lng) <= 75,
    );
    if (!dup) kept.push(poi);
  }
  return kept;
}

// Poi um ein internes Dedup-Feld erweitern (nicht serialisiert):
declare module './entities/poi.entity' {
  interface Poi {
    nameKey?: string;
  }
}

@Injectable()
export class PoiService {
  private readonly logger = new Logger(PoiService.name);
  private readonly tomtomKey: string;
  private readonly googleKey: string;

  /** TTL-Cache für TomTom-Antworten pro Kategorie+BBox-Rasterzelle. */
  private curatedCache = new Map<string, { data: Poi[]; expiresAt: number }>();

  /** TTL-Cache für Google-Detail-Anreicherung pro poi-id. */
  private googleEnrichCache = new Map<string, { data: GoogleEnrichment | null; expiresAt: number }>();

  /** TTL-Cache für Wikimedia-Bilder pro poi-id (keyless, kostenlos). */
  private wikiImageCache = new Map<string, { data: WikiImage | null; expiresAt: number }>();

  constructor(
    private readonly config: ConfigService,
    @Inject(SUPABASE_CLIENT) private readonly supabase: SupabaseClient | null,
  ) {
    // Gleicher Key wie der Verkehrsdienst: Der Betreiber gibt EINEN
    // TomTom-Key an, der für Traffic UND Kuratierung arbeitet.
    this.tomtomKey = config.get<string>('TRAFFIC_API_KEY') ?? '';
    // Google Places (New) für die Detail-Anreicherung (Name/Bild/Beschreibung/
    // Website). Ohne Key degradiert der Endpunkt auf OSM/DB-Daten.
    this.googleKey = config.get<string>('GOOGLE_PLACES_API_KEY') ?? '';
  }

  async findInBoundingBox(query: QueryPoisDto): Promise<Poi[]> {
    const [minLng, minLat, maxLng, maxLat] = query.bbox;
    const categories = query.categories;

    const [osmResults, dbResults, curatedResults] = await Promise.all([
      this.queryOsm(categories, minLng, minLat, maxLng, maxLat),
      this.queryDatabase(categories, minLng, minLat, maxLng, maxLat),
      this.queryCurated(categories, minLng, minLat, maxLng, maxLat),
    ]);

    // OSM zuerst, dann DB, dann Kuratierung - dedupe wirft Doppel-
    // fänger raus (OSM gewinnt wegen stabilerer IDs).
    const all = dedupe([...osmResults, ...dbResults, ...curatedResults]);
    for (const p of all) delete p.nameKey;
    return all;
  }

  /**
   * POI-Detail für das Detail-Sheet der App (GET /v1/pois/:id).
   *
   * Drei Quellen je nach ID-Präfix:
   *  - "osm-<type>-<id>": Live aus der poi-Tabelle (falls gespiegelt),
   *    sonst nicht auflösbar -> null (App zeigt Basis-Sheet).
   *  - "curated-<cat>-<tomtomId>": Zeile aus der poi-Tabelle (die
   *    Kuratierung spiegelt ihre Funde dorthin).
   *  - sonst (Biker-Service/UUID): direkt aus der poi-Tabelle.
   *
   * Die Herkunftsangabe ("Veröffentlicht am/von") ist ehrlich: kuratierte
   * POIs stammen vom Biker-POI-Dienst (TomTom-Kuratierung), OSM-POIs von
   * OpenStreetMap - wir erfinden keine Nutzer-Ersteller.
   */
  async findDetail(
    id: string,
    lat?: number,
    lng?: number,
    categoryHint?: string,
  ): Promise<PoiDetail | null> {
    let row: Record<string, unknown> | null = null;
    if (this.supabase) {
      const { data, error } = await this.supabase
        .from('poi')
        .select('*')
        .eq('id', id)
        .maybeSingle();
      if (!error && data) row = data as Record<string, unknown>;
    }

    const meta = (row?.metadata ?? {}) as Record<string, unknown>;
    const websiteRaw = typeof meta['website'] === 'string' ? meta['website'] : null;
    let website = websiteRaw
      ? websiteRaw.startsWith('http')
        ? websiteRaw
        : `https://${websiteRaw}`
      : null;

    const opening = typeof meta['opening_hours'] === 'string' ? meta['opening_hours'] : null;
    const address = typeof meta['address'] === 'string' ? meta['address'] : null;
    const descriptionParts = [opening, address].filter(Boolean) as string[];
    let description = descriptionParts.length > 0 ? descriptionParts.join(' · ') : null;
    let imageUrl = typeof meta['image_url'] === 'string' ? meta['image_url'] : null;

    const source = String(row?.source ?? 'OSM');
    const category = String(row?.category ?? categoryHint ?? 'FUEL');
    const name = String(row?.name ?? '');
    const poiLat = row ? Number(row.lat) : lat;
    const poiLng = row ? Number(row.lng) : lng;

    // Ohne DB-Zeile UND ohne Koordinaten gibt es keine verlässliche
    // Quelle - ehrlich null statt ein Detail erfinden.
    if (!row && (poiLat == null || poiLng == null)) return null;

    // Google-Anreicherung (Detail-Abrufe sind selten -> Kosten ok).
    const enrich = await this.enrichFromGoogle(
      id,
      name,
      category,
      poiLat as number,
      poiLng as number,
    );
    if (enrich) {
      if (!description && enrich.description) description = enrich.description;
      if (!website && enrich.website) website = enrich.website;
      if (!imageUrl && enrich.imageUrl) imageUrl = enrich.imageUrl;
    }

    // Kostenlose Bild-Kette: ohne eigenes Bild UND ohne Google-Foto holt
    // Wikimedia Commons per Geo-Search ein freies Foto (keyless, CC +
    // Artist-Attribution). Läuft auch ohne Google-Key - dann sind Bilder
    // für viele POIs trotzdem da.
    let wikiImage: WikiImage | null = null;
    if (!imageUrl) {
      wikiImage = await this.enrichImageFromWikimedia(id, poiLat as number, poiLng as number);
      if (wikiImage) imageUrl = wikiImage.imageUrl;
    }

    // Vertrag: Ohne DB-Zeile lohnt die Antwort nur MIT Anreicherung
    // (sonst enthält sie nichts, was die App nicht schon hat) - dann null
    // (404), das Sheet zeigt die Basis-Daten aus dem Karten-Treffer.
    if (!row && !enrich?.matched && !wikiImage) return null;

    const publishedBy =
      source === 'CURATED'
        ? 'Biker-POI-Kuratierung (TomTom)'
        : source === 'COMMUNITY'
          ? 'MotoRoute Community'
          : enrich?.matched
            ? 'Google Places'
            : 'OpenStreetMap';

    return {
      id: String(row?.id ?? id),
      category,
      name: name || (enrich?.googleSummary ?? '') || 'POI',
      lat: Number(poiLat),
      lng: Number(poiLng),
      source: enrich?.matched ? `${source}+GOOGLE` : source,
      description,
      website,
      imageUrl,
      bikerScore: typeof meta['bikerScore'] === 'number' ? (meta['bikerScore'] as number) : null,
      originTag: typeof meta['origin_tag'] === 'string' ? meta['origin_tag'] : null,
      publishedAt:
        typeof row?.created_at === 'string'
          ? (row.created_at as string)
          : enrich?.matched
            ? new Date().toISOString()
            : null,
      publishedBy,
      googleMapsUri: enrich?.googleMapsUri ?? null,
      googleSummary: enrich?.matched ? enrich.description : null,
      photoAttribution: enrich?.photoAttribution ?? wikiImage?.photoAttribution ?? null,
    };
  }

  /**
   * Google Places Foto-Proxy: lädt ein Foto serverseitig (der API-Key
   * bleibt im Backend) und streamt die Bytes. Die App löst die relative
   * Proxy-URL gegen ihre API-Basis auf - Google-Key landet nie im Client.
   */
  async fetchGooglePhoto(name: string): Promise<{ data: Buffer; contentType: string } | null> {
    if (!this.googleKey) return null;
    // Strenges Format: der Query-Param darf kein SSRF-/Key-Träger sein.
    if (!/^places\/[A-Za-z0-9_-]+\/photos\/[A-Za-z0-9_-]+\/media$/.test(name)) return null;
    try {
      const response = await axios.get<ArrayBuffer>(
        `https://places.googleapis.com/v1/${name}`,
        {
          params: { key: this.googleKey, maxHeightPx: 800, maxWidthPx: 800, skipHttpRedirect: true },
          timeout: GOOGLE_TIMEOUT_MS,
          responseType: 'arraybuffer',
        },
      );
      const contentType = String(response.headers['content-type'] ?? 'image/jpeg');
      if (!contentType.startsWith('image/')) return null;
      return { data: Buffer.from(response.data), contentType };
    } catch (e) {
      this.logger.warn(`Google-Foto fehlgeschlagen: ${String(e)}`);
      return null;
    }
  }

  /**
   * OSM-ID-Format "osm-<type>-<id>" erkennen (node/way/relation). Die
   * sachliche Kategorie kommt aus dem App-Kontext (Kategorien-Filter) -
   * der ID-Typ allein sagt nichts über FUEL/RESTAURANT/... aus.
   */
  private isOsmId(id: string): boolean {
    return /^osm-[a-z]+-[0-9]+$/.test(id);
  }

  /**
   * Google Places (New) Detail-Anreicherung: Nearby-Match an den
   * POI-Koordinaten (50 m) liefert Foto, Summary, Website, Maps-Deeplink.
   * 24-h-Cache pro poi-id; Fehler und "kein Key" degradieren zu null
   * (App zeigt die OSM/DB-Daten), wirft niemals.
   */
  private async enrichFromGoogle(
    id: string,
    name: string,
    category: string,
    lat: number,
    lng: number,
  ): Promise<GoogleEnrichment | null> {
    if (!this.googleKey) return null;
    if (!Number.isFinite(lat) || !Number.isFinite(lng)) return null;

    const cached = this.googleEnrichCache.get(id);
    if (cached && cached.expiresAt > Date.now()) return cached.data;

    let result: GoogleEnrichment | null = null;
    try {
      // Google-Typ passend zur POI-Kategorie. Blitzer (SPEED_CAMERA)
      // hat bei Google keine Entsprechung -> gar nicht erst suchen.
      const typeFor: Record<string, string | undefined> = {
        FUEL: 'gas_station',
        MOTO_HOTEL: 'hotel',
        BIKER_MEETUP: 'bar',
        CAMPSITE: 'campground',
        ICE_CREAM: 'ice_cream_shop',
        RESTAURANT: 'restaurant',
        PUB: 'bar',
        SNACK: 'fast_food',
      };
      const googleType = typeFor[category];
      if (!googleType) return null;

      const search = await axios.post(
        'https://places.googleapis.com/v1/places:searchNearby',
        {
          includedTypes: [googleType],
          maxResultCount: 5,
          locationRestriction: {
            circle: { center: { latitude: lat, longitude: lng }, radius: 50 },
          },
        },
        {
          headers: {
            'Content-Type': 'application/json',
            'X-Goog-Api-Key': this.googleKey,
            'X-Goog-FieldMask':
              'places.id,places.displayName,places.formattedAddress,places.websiteUri,places.googleMapsUri,places.photos,places.editorialSummary',
          },
          timeout: GOOGLE_TIMEOUT_MS,
        },
      );

      const places: Array<Record<string, unknown>> = search.data?.places ?? [];
      // Nächster Treffer mit gleichem/ähnlichem Namen - ein reiner
      // 50-m-Näherungs-Treffer mit ganz anderem Namen wäre falsch.
      const norm = (s: string) =>
        s.toLowerCase().replace(/[^a-z0-9äöüß]/g, '');
      const want = norm(name);
      const chosen =
        places.find((p) => {
          const dn = (p['displayName'] as { text?: string } | undefined)?.text ?? '';
          return want && (norm(dn).includes(want) || want.includes(norm(dn)));      }) ?? places[0];

      if (chosen) {
        const photo = (chosen['photos'] as Array<Record<string, unknown>> | undefined)?.[0];
        const photoName = typeof photo?.['name'] === 'string' ? (photo['name'] as string) : null;
        const summaryText =
          (chosen['editorialSummary'] as { text?: string } | undefined)?.text ?? null;
        const addr = (chosen['formattedAddress'] as string | undefined) ?? null;
        const gSummary = summaryText ?? addr;
        const authorAttr =
          (photo?.['authorAttributions'] as Array<Record<string, unknown>> | undefined)?.[0];
        result = {
          description: gSummary,
          website: (chosen['websiteUri'] as string | undefined) ?? null,
          imageUrl: photoName ? `/v1/pois/photo?name=${encodeURIComponent(photoName)}` : null,
          googleMapsUri: (chosen['googleMapsUri'] as string | undefined) ?? null,
          googleSummary: summaryText ?? null,
          photoAttribution:
            typeof authorAttr?.['displayName'] === 'string'
              ? (authorAttr['displayName'] as string)
              : null,
          matched: true,
        };
      }
    } catch (e) {
      // Degradation: kein Google -> OSM/DB-Daten reichen; Log sichtbar.
      this.logger.warn(`Google-Enrichment fehlgeschlagen: ${String(e)}`);
      result = null;
    }

    this.googleEnrichCache.set(id, {
      data: result,
      expiresAt: Date.now() + GOOGLE_ENRICH_TTL_MS,
    });
    if (this.googleEnrichCache.size > GOOGLE_ENRICH_CACHE_MAX) {
      const now = Date.now();
      for (const [k, v] of this.googleEnrichCache) {
        if (v.expiresAt <= now) this.googleEnrichCache.delete(k);
      }
    }
    return result;
  }

  /**
   * Wikimedia Commons Geo-Search: freies Foto in ~80 m um den POI -
   * keyless und kostenlos (Community-Daten). Attribution ist bei CC-
   * Lizenzen Pflicht und wird als photoAttribution zurückgegeben.
   * 24-h-Cache pro poi-id; Fehler degradieren zu null, wirft nie.
   */
  private async enrichImageFromWikimedia(
    id: string,
    lat: number,
    lng: number,
  ): Promise<WikiImage | null> {
    if (!Number.isFinite(lat) || !Number.isFinite(lng)) return null;

    const cacheKey = `wiki:${id}`;
    const cached = this.wikiImageCache.get(cacheKey);
    if (cached && cached.expiresAt > Date.now()) return cached.data;

    let result: WikiImage | null = null;
    try {
      const { data } = await axios.get('https://commons.wikimedia.org/w/api.php', {
        params: {
          action: 'query',
          format: 'json',
          formatversion: '2',
          generator: 'geosearch',
          ggscoord: `${lat}|${lng}`,
          ggsradius: 150,
          // WICHTIG: Namespace 6 (File:) - ohne ihn liefert der Geo-
          // Generator nur Commons-Artikel/Galerien ohne Bild-URLs.
          ggsnamespace: 6,
          ggslimit: 5,
          prop: 'imageinfo',
          iiprop: 'url|extmetadata',
          iiurlwidth: 640,
        },
        headers: { 'User-Agent': WIKIMEDIA_UA },
        timeout: GOOGLE_TIMEOUT_MS,
      });
      // formatversion: 2 -> query.pages ist ein Array.
      const pages =
        (data as { query?: { pages?: Array<Record<string, unknown>> } })?.query?.pages ?? [];
      for (const page of pages) {
        const info = (page['imageinfo'] as Array<Record<string, unknown>> | undefined)?.[0];
        if (!info) continue;
        const thumb = typeof info['thumburl'] === 'string' ? (info['thumburl'] as string) : null;
        if (!thumb) continue;
        const extmeta = (info['extmetadata'] ?? {}) as Record<string, { value?: string }>;
        const artistHtml = extmeta['Artist']?.value ?? '';
        const artist = artistHtml
          .replace(/<[^>]*>/g, '')
          .replace(/\s+/g, ' ')
          .trim()
          .slice(0, 60);
        result = {
          imageUrl: thumb,
          photoAttribution: artist ? `${artist} / Wikimedia Commons` : 'Wikimedia Commons',
        };
        break;
      }
    } catch (e) {
      this.logger.warn(`Wikimedia-Bild fehlgeschlagen: ${String(e)}`);
      result = null;
    }

    this.wikiImageCache.set(cacheKey, {
      data: result,
      expiresAt: Date.now() + GOOGLE_ENRICH_TTL_MS,
    });
    if (this.wikiImageCache.size > GOOGLE_ENRICH_CACHE_MAX) {
      const now = Date.now();
      for (const [k, v] of this.wikiImageCache) {
        if (v.expiresAt <= now) this.wikiImageCache.delete(k);
      }
    }
    return result;
  }

  /**
   * Abfrage über die Overpass API für OSM-Daten.
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

    if (!selectors.trim()) return [];

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
   * Kuratierte Biker-POIs aus der eigenen poi-Tabelle. Kategorien, die
   * Overpass nicht liefert (RESTAURANT/PUB/SNACK), kommen ausschließlich
   * von hier + TomTom; für MOTO_HOTEL/BIKER_MEETUP ergänzt sie die
   * dünnen OSM-Funde.
   *
   * Die Tabelle existiert erst ab Migration 0005 - fehlt sie, wird das
   * einmalig erkannt und dann nicht mehr versucht (kein Log-Spam).
   */
  private tableMissing = false;

  private async queryDatabase(
    categories: PoiCategory[],
    minLng: number,
    minLat: number,
    maxLng: number,
    maxLat: number,
  ): Promise<Poi[]> {
    if (this.supabase == null || this.tableMissing) return [];
    if (categories.length === 0) return [];

    const { data, error } = await this.supabase
      .from('poi')
      .select('*')
      .in('category', categories)
      .gte('lat', minLat)
      .lte('lat', maxLat)
      .gte('lng', minLng)
      .lte('lng', maxLng);

    if (error) {
      // 404/PGRST205 = Tabelle fehlt (Migration noch nicht gelaufen) -
      // kontrolliert degradieren statt 500er an den Karten-Layer.
      const code = (error as { code?: string }).code ?? '';
      if (code === 'PGRST205' || code === '42P01') {
        this.tableMissing = true;
        this.logger.warn('poi-Tabelle fehlt - Migration 0005 ausführen (Kuratierung deaktiviert)');
        return [];
      }
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

  /**
   * TOMTOM-KURATIERUNG ON-DEMAND: Für Kategorien ohne Overpass-Query
   * (oder ergänzend zu dünnen OSM-Funden) fragt der Service die TomTom
   * Search API nach dem aktuellen Kartenausschnitt. Ergebnisse wandern
   * in die poi-Tabelle (Cache + späterer Massenabgleich) und direkt in
   * die Antwort. Ohne Key/Tabelle degradiert es sauber zu [].
   *
   * Lizenz-Regel wie beim Verkehr: Ergebnisse werden nur transient im
   * RAM gecacht (30 min), nie dauerhaft außerhalb der eigenen Tabelle
   * weiterverteilt - die poi-Tabelle ist der eigene Kuratierungs-Bestand
   * (ToS-konform: Kuratierung = eigene Wertschöpfung auf eigener Quelle).
   */
  private async queryCurated(
    categories: PoiCategory[],
    minLng: number,
    minLat: number,
    maxLng: number,
    maxLat: number,
  ): Promise<Poi[]> {
    const wanted = categories.filter((c) => CURATED_TOMTOM[c]);
    if (wanted.length === 0) return [];
    if (!this.tomtomKey) return [];

    // Rasterzelle als Cache-Schlüssel: ~0.05° Kacheln halten TomTom-
    // Requests drosselbar, auch wenn Nutzer die Karte zittern lassen.
    const cell = (v: number) => Math.round(v * 20) / 20;
    const cellKey = `${cell(minLng)},${cell(minLat)},${cell(maxLng)},${cell(maxLat)}`;

    const perCategory = await Promise.all(
      wanted.map(async (category) => {
        const spec = CURATED_TOMTOM[category]!;
        const cacheKey = `${category}:${cellKey}`;
        const hit = this.curatedCache.get(cacheKey);
        if (hit && hit.expiresAt > Date.now()) return hit.data;

        const centerLat = (minLat + maxLat) / 2;
        const centerLng = (minLng + maxLng) / 2;
        // Diagonale in km, grob: 111 km pro Grad.
        const spanKm =
          Math.max(maxLat - minLat, maxLng - minLng) * 111 * 1.5;

        try {
          const { data } = await axios.get(
            `https://api.tomtom.com/search/2/categorySearch/${encodeURIComponent(spec.query)}.json`,
            {
              params: {
                key: this.tomtomKey,
                limit: 100,
                lat: centerLat.toFixed(5),
                lon: centerLng.toFixed(5),
                radius: Math.min(50_000, Math.round(spanKm * 1000)),
                categorySet: spec.setId,
              },
              timeout: TOMTOM_TIMEOUT_MS,
            },
          );

          const pois: Poi[] = (data.results ?? [])
            .map((r: any) => {
              const name = r.poi?.name;
              const lat = r.position?.lat;
              const lng = r.position?.lon;
              if (!name || lat == null || lng == null) return null;
              const poi: Poi = {
                id: `curated-${category.toLowerCase()}-${r.id}`,
                category,
                name,
                lat,
                lng,
                source: PoiSource.CURATED,
                metadata: {
                  address: r.address?.freeformAddress,
                  bikerScore: computeBikerScore(category, name),
                  curated: true,
                },
              };
              poi.nameKey = nameKey(name);
              return poi;
            })
            .filter((p: Poi | null): p is Poi => p !== null);

          this.curatedCache.set(cacheKey, {
            data: pois,
            expiresAt: Date.now() + CURATED_CACHE_TTL_MS,
          });
          // Cache-Begrenzung: ältesten Eintrag verwerfen.
          if (this.curatedCache.size > 200) {
            const oldest = this.curatedCache.keys().next().value;
            if (oldest) this.curatedCache.delete(oldest);
          }
          // Async in die poi-Tabelle spiegeln (best effort, Fehler egal -
          // der Karten-Layer wartet nicht darauf).
          void this.persistCurated(pois);
          return pois;
        } catch (err: unknown) {
          const msg = err instanceof Error ? err.message : String(err);
          this.logger.debug(`TomTom-Kuratierung ${category} fehlgeschlagen: ${msg}`);
          // Negativ-Cache: 5 min nicht erneut versuchen.
          this.curatedCache.set(cacheKey, {
            data: [],
            expiresAt: Date.now() + 5 * 60 * 1000,
          });
          return [];
        }
      }),
    );

    return perCategory.flat();
  }

  /** Kuratierte Funde in die poi-Tabelle spiegeln (best effort, async). */
  private async persistCurated(pois: Poi[]): Promise<void> {
    if (this.supabase == null || this.tableMissing || pois.length === 0) return;
    try {
      await this.supabase.from('poi').upsert(
        pois.map((p) => ({
          id: p.id,
          category: p.category,
          name: p.name,
          lat: p.lat,
          lng: p.lng,
          source: p.source,
          metadata: p.metadata ?? {},
        })),
        { onConflict: 'id' },
      );
    } catch {
      // Cache-Tabellen-Spiegelung ist optional - die Antwort ist schon raus.
    }
  }
}
