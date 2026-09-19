import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import axios from 'axios';
import {
  TrafficIncident,
  mapTomTomIncidents,
  tomTomCategoryFilter,
  tomTomFieldsProjection,
} from './tomtom.mapper';

/**
 * Echtzeitverkehr über TomTom Traffic API v5 (incidentDetails).
 *
 * Betriebsregeln (aus Phase 1/2 Teil A.4 + B.5 abgeleitet):
 * - Key NUR im Backend (.env), nie im App-Bundle.
 * - Rohdaten werden NUR TRANSIENT gecacht (60 s TTL, in-memory) -
 *   die TomTom-Lizenz verbietet dauerhaftes Speichern/Caching über
 *   die erlaubte TTL hinaus; es entsteht bewusst KEIN Data-Warehouse
 *   mit Rohereignissen.
 * - Ausfall des Providers darf das Routing NICHT blockieren: die App
 *   bekommt [] und fährt mit der letzten gültigen Route weiter.
 */
@Injectable()
export class TrafficService {
  private readonly logger = new Logger(TrafficService.name);

  /** In-memory Cache mit TTL - bewusst pro Prozess, nicht distributed:
   * die Daten sind 60 s alt genug, dass Konsistenz über Instanzen
   * irrelevant ist. */
  private cache = new Map<string, { expiresAt: number; incidents: TrafficIncident[] }>();

  private static readonly CACHE_TTL_MS = 60_000;

  constructor(private readonly config: ConfigService) {}

  get isEnabled(): boolean {
    return Boolean(this.config.get<string>('TRAFFIC_API_KEY'));
  }

  async getIncidentsInBoundingBox(bbox: number[]): Promise<TrafficIncident[]> {
    if (!this.isEnabled) {
      // Ohne Key: leeres Result (App behandelt das als "keine Vorfälle
      // gemeldet"), kein Fehler - bewusste Degradierung.
      return [];
    }

    const cacheKey = bbox.join(',');
    const cached = this.cache.get(cacheKey);
    if (cached && cached.expiresAt > Date.now()) {
      return cached.incidents;
    }

    const incidents = await this.fetchFromTomTom(bbox);
    this.cache.set(cacheKey, {
      expiresAt: Date.now() + TrafficService.CACHE_TTL_MS,
      incidents,
    });

    // Cache-Hygiene: bei bbox-Vielfalt wachsen sonst tote Einträge.
    if (this.cache.size > 100) {
      const now = Date.now();
      for (const [key, entry] of this.cache) {
        if (entry.expiresAt <= now) this.cache.delete(key);
      }
    }

    return incidents;
  }

  private async fetchFromTomTom(bbox: number[]): Promise<TrafficIncident[]> {
    const apiKey = this.config.get<string>('TRAFFIC_API_KEY');
    // TomTom bbox-Format: minLat,minLng,maxLat,maxLng (unser Format ist
    // minLng,minLat,maxLng,maxLat - bewusst NUR hier tauschen!).
    const [minLng, minLat, maxLng, maxLat] = bbox;

    const url = `https://api.tomtom.com/traffic/services/5/incidentDetails`;
    const params = {
      key: apiKey,
      bbox: `${minLat},${minLng},${maxLat},${maxLng}`,
      fields: tomTomFieldsProjection(),
      language: 'de-DE',
      categoryFilter: tomTomCategoryFilter(),
      timeValidityFilter: 'present',
    };

    try {
      const { data } = await axios.get(url, { params, timeout: 6000 });
      return mapTomTomIncidents(data);
    } catch (err) {
      this.logger.error(`TomTom incidentDetails failed: ${err}`);
      // Provider-Ausfall != App-Fehler: leeres Ergebnis + Log.
      return [];
    }
  }
}
