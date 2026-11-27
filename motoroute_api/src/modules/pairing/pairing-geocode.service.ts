import {
  BadGatewayException,
  HttpException,
  Injectable,
  Logger,
  ServiceUnavailableException,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import axios from 'axios';

export interface GeocodeResult {
  /** Kurzer Name für die Wegpunkt-Zeile ("Eibsee"). */
  label: string;
  /** Volle Adresse für die Trefferliste. */
  detail: string;
  lat: number;
  lon: number;
}

interface CacheEntry {
  at: number;
  results: GeocodeResult[];
}

/** Nominatim verlangt max. 1 Anfrage pro Sekunde - wir halten uns daran. */
const MIN_INTERVAL_MS = 1100;
/** So viele Anfragen dürfen gleichzeitig warten, danach gibt es 429. */
const MAX_QUEUED = 3;
const CACHE_TTL_MS = 30 * 60 * 1000;
const CACHE_MAX_ENTRIES = 200;
const UPSTREAM_TIMEOUT_MS = 6000;
const MAX_RESULTS = 5;

/**
 * Ortssuche für die Plan-Seite.
 *
 * Warum über das Backend und nicht direkt aus dem Browser: Nominatim
 * verlangt einen aussagekräftigen User-Agent, den ein Browser nicht setzen
 * darf. Hier läuft alles mit eigenem User-Agent, eigenem Cache und einer
 * seriellen Warteschlange, damit wir den Dienst nicht überfahren.
 *
 * Fehlerbild nach außen:
 *   429  zu viele Anfragen (unser Limit oder Nominatim drosselt)
 *   502  Nominatim antwortet mit Fehler
 *   503  Nominatim nicht erreichbar / Zeitüberschreitung
 */
@Injectable()
export class PairingGeocodeService {
  private readonly logger = new Logger(PairingGeocodeService.name);
  private readonly cache = new Map<string, CacheEntry>();
  private chain: Promise<void> = Promise.resolve();
  private lastCallAt = 0;
  private queued = 0;

  constructor(private readonly config: ConfigService) {}

  async search(query: string): Promise<GeocodeResult[]> {
    const key = query.trim().toLowerCase().replace(/\s+/g, ' ');
    const cached = this.cache.get(key);
    if (cached && Date.now() - cached.at < CACHE_TTL_MS) {
      return cached.results;
    }

    const results = await this.queuedCall(() => this.fetchNominatim(key));
    this.remember(key, results);
    return results;
  }

  /** Serielle Ausführung mit Mindestabstand - schützt den Fremddienst. */
  private async queuedCall<T>(work: () => Promise<T>): Promise<T> {
    if (this.queued >= MAX_QUEUED) {
      throw new HttpException(
        {
          statusCode: 429,
          code: 'GEOCODE_BUSY',
          message: 'Zu viele Ortssuchen gleichzeitig. Bitte kurz warten.',
        },
        429,
      );
    }
    this.queued += 1;
    const previous = this.chain;
    let release: () => void = () => undefined;
    this.chain = new Promise<void>((resolve) => {
      release = resolve;
    });
    try {
      await previous;
      const wait = this.lastCallAt + MIN_INTERVAL_MS - Date.now();
      if (wait > 0) {
        await new Promise((resolve) => setTimeout(resolve, wait));
      }
      this.lastCallAt = Date.now();
      return await work();
    } finally {
      this.queued -= 1;
      release();
    }
  }

  private async fetchNominatim(query: string): Promise<GeocodeResult[]> {
    const base = (
      this.config.get<string>('NOMINATIM_URL') ??
      'https://nominatim.openstreetmap.org'
    ).replace(/\/+$/, '');
    const contact =
      this.config.get<string>('NOMINATIM_CONTACT') ??
      'https://github.com/Kjell35/motoroute';

    let response;
    try {
      response = await axios.get(`${base}/search`, {
        params: {
          q: query,
          format: 'jsonv2',
          limit: MAX_RESULTS,
          'accept-language': 'de',
          addressdetails: 0,
        },
        headers: {
          'User-Agent': `MotoRoute-Planer/1.0 (${contact})`,
          Accept: 'application/json',
        },
        timeout: UPSTREAM_TIMEOUT_MS,
        validateStatus: () => true,
      });
    } catch (error) {
      const message = error instanceof Error ? error.message : 'unbekannt';
      this.logger.warn(`Nominatim nicht erreichbar: ${message}`);
      throw new ServiceUnavailableException(
        'Ortssuche gerade nicht erreichbar. Bitte später erneut versuchen.',
      );
    }

    if (response.status === 429 || response.status === 403) {
      this.logger.warn(`Nominatim drosselt (${response.status})`);
      throw new HttpException(
        {
          statusCode: 429,
          code: 'GEOCODE_UPSTREAM_LIMIT',
          message: 'Ortssuche ist ausgelastet. Bitte einen Moment warten.',
        },
        429,
      );
    }
    if (response.status < 200 || response.status >= 300) {
      this.logger.warn(`Nominatim antwortet ${response.status}`);
      throw new BadGatewayException('Ortssuche lieferte einen Fehler.');
    }

    const raw: unknown = response.data;
    if (!Array.isArray(raw)) return [];

    const results: GeocodeResult[] = [];
    for (const item of raw) {
      if (!item || typeof item !== 'object') continue;
      const entry = item as Record<string, unknown>;
      const lat = Number(entry.lat);
      const lon = Number(entry.lon);
      if (!Number.isFinite(lat) || lat < -90 || lat > 90) continue;
      if (!Number.isFinite(lon) || lon < -180 || lon > 180) continue;
      const detail = String(entry.display_name ?? '').trim();
      const name = String(entry.name ?? '').trim();
      const label = name || detail.split(',')[0]?.trim() || query;
      results.push({ label, detail: detail || label, lat, lon });
      if (results.length >= MAX_RESULTS) break;
    }
    return results;
  }

  private remember(key: string, results: GeocodeResult[]): void {
    if (this.cache.size >= CACHE_MAX_ENTRIES) {
      const oldest = this.cache.keys().next();
      if (!oldest.done) this.cache.delete(oldest.value);
    }
    this.cache.set(key, { at: Date.now(), results });
  }
}
