import { HttpException, Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import axios from 'axios';
import { PoiCategory } from '../poi/dto/query-pois.dto';
import { Poi } from '../poi/entities/poi.entity';
import { PoiService } from '../poi/poi.service';
import {
  StormAlert,
  StormSeverity,
  WeatherSample,
  detectStorm,
  formatDistanceWarning,
  worstAlert,
} from './storm-detector';

/** Antwort-Form des Wetter-Radars (POST /v1/weather/route). */
export interface RouteWeatherSegment {
  /** Distanz ab Routenstart (Meter) - Position des Abschnitts. */
  distanceFromStartM: number;
  /** ISO-8601: vorhergesagter Zeitpunkt (Startzeit + ETA). */
  time: string;
  tempC: number;
  precipitationMmH: number;
  windGustMs?: number;
  conditionCode: number;
  severity: StormSeverity;
}

export interface ShelterPoi {
  id: string;
  name: string;
  category: string;
  lat: number;
  lng: number;
  /** Luftlinie zum kritischsten Streckenabschnitt (Meter). */
  distanceFromRouteM: number;
}

export interface RouteWeatherReport {
  isEnabled: boolean;
  segments: RouteWeatherSegment[];
  /** Der schlimmste Alert entlang der Route (null = unauffällig). */
  alert: {
    severity: StormSeverity;
    kind: StormAlert['kind'];
    /** Fahrtrichtungs-Meldung: "In 20 km zieht ein Gewitter auf: ..." */
    message: string;
    /** Distanz ab Start zum kritischen Abschnitt (Meter). */
    distanceFromStartM: number;
  } | null;
  /** Schutz-POIs nahe des kritischen Abschnitts (nur bei Alert). */
  shelters: ShelterPoi[];
}

interface OwmHourly {
  dt: number;
  temp: number;
  wind_speed: number;
  wind_gust?: number;
  rain?: { '1h'?: number };
  weather: { id: number }[];
}

/**
 * Open-Meteo-Antwort (keyless, Default-Provider): WMO weathercode je
 * Stunde. Wird 1:1 in die interne OwmHourly-Form gemappt - detectStorm
 * (OWM-Code-Semantik) bleibt unveraendert, der WMO-Compat-Layer
 * (wmoCodeToOwm) uebersetzt.
 */
interface OpenMeteoResponse {
  hourly?: {
    time: string[];
    temperature_2m: (number | null)[];
    precipitation: (number | null)[];
    wind_gusts_10m: (number | null)[];
    weathercode: (number | null)[];
  };
}

/**
 * WMO weathercode -> OWM-Condition-Id (Kompatibilitaetsschicht):
 * 2xx = Gewitter, 5xx/3xx = Regen, 6xx = Schnee, 800 = klar.
 * Konservativ: unklare Codes werden zu "bewoelkt" (801).
 */
export function wmoCodeToOwm(code: number | null): number {
  if (code == null) return 800;
  if (code >= 0 && code <= 1) return 800; // klar / ueberwiegend klar
  if (code === 2 || code === 3) return 801; // bewoelkt
  if (code === 45 || code === 48) return 701; // Nebel (OWM-Gruppe 7xx)
  if (code >= 51 && code <= 57) return 300; // Nieselregen -> OWM-Drizzle
  if (code >= 61 && code <= 65) return 500; // Regen
  if (code === 66 || code === 67) return 502; // gefrierender Regen (heavy)
  if (code >= 71 && code <= 77) return 600; // Schnee
  if (code === 85 || code === 86) return 601; // Schneeschauer
  if (code === 80 || code === 81) return 520; // leichte/moderate Schauer
  if (code === 82) return 522; // heftige Schauer (danger-Naehe)
  if (code >= 95) return 201; // Gewitter (OWM-Gruppe 2xx)
  return 801;
}

interface OwmOneCallResponse {
  hourly: OwmHourly[];
}

const WEATHER_CACHE_TTL_MS = 10 * 60_000;
const WEATHER_CACHE_MAX = 200;

/** Alle ~25 km ein Sample, mindestens Start/Ziel, max. 12 API-Calls-Budget. */
const SAMPLE_SPACING_M = 25_000;
const MAX_SAMPLES = 12;

/** Schutz-POIs im Umkreis des kritischen Abschnitts. */
const SHELTER_SEARCH_RADIUS_M = 15_000;
const SHELTER_CATEGORIES: PoiCategory[] = [
  PoiCategory.MOTO_HOTEL,
  PoiCategory.BIKER_MEETUP,
  PoiCategory.CAMPSITE,
];

function haversineMeters(
  lat1: number,
  lng1: number,
  lat2: number,
  lng2: number,
): number {
  const R = 6_371_000;
  const dLat = ((lat2 - lat1) * Math.PI) / 180;
  const dLng = ((lng2 - lng1) * Math.PI) / 180;
  const a =
    Math.sin(dLat / 2) ** 2 +
    Math.cos((lat1 * Math.PI) / 180) *
      Math.cos((lat2 * Math.PI) / 180) *
      Math.sin(dLng / 2) ** 2;
  return 2 * R * Math.asin(Math.sqrt(a));
}

@Injectable()
export class WeatherService {
  private readonly logger = new Logger(WeatherService.name);

  /** Transienter Cache (Koordinate gerundet -> One-Call-Antwort). */
  private cache = new Map<
    string,
    { expiresAt: number; hourly: OwmHourly[] }
  >();

  constructor(
    private readonly config: ConfigService,
    private readonly poiService: PoiService,
  ) {}

  /**
   * Wetter-Radar ist ab Werk aktiv: Open-Meteo ist keyless (Attribution-
   * Pflicht erfuellt der Widget-Text). Ein gesetzter OPENWEATHER_API_KEY
   * schaltet auf OWM One Call 3.0 um (hoehere Aufloesung, Lizenz-Pflichten
   * laut OWM). Ausnahme: OWM-Key ist gesetzt, aber empty string -> bleibt
   * keyless (kein "Key-loeschen schaltet das Feature aus").
   */
  get isEnabled(): boolean {
    return true;
  }

  private get provider(): 'open-meteo' | 'owm' {
    const key = this.config.get<string>('OPENWEATHER_API_KEY');
    return key && key.trim().length > 0 ? 'owm' : 'open-meteo';
  }

  /**
   * Wetter entlang einer Route: Polyline wird gleichmäßig gesampelt,
   * jeder Sample bekommt seine ETA (Startzeit + Fahrzeit-Anteil) und
   * daraus die OWM-Stunde mit dem kleinsten Zeitabstand.
   */
  async getRouteWeather(
    geometry: number[][],
    durationSeconds: number,
  ): Promise<RouteWeatherReport> {
    if (!this.isEnabled) {
      return {
        isEnabled: false,
        segments: [],
        alert: null,
        shelters: [],
      };
    }

    const samples = sampleRoute(geometry, durationSeconds);
    const segments: RouteWeatherSegment[] = [];

    for (const sample of samples) {
      const hourly = await this.fetchHourly(sample.lat, sample.lng);
      if (!hourly) continue;

      const targetMs = Date.now() + sample.etaSeconds * 1000;
      const hour = pickClosestHour(hourly, targetMs);
      if (!hour) continue; // außerhalb des 48-h-Fensters: nicht erfinden

      const weatherSample: WeatherSample = {
        time: new Date(hour.dt * 1000).toISOString(),
        tempC: hour.temp,
        precipitationMmH: hour.rain?.['1h'] ?? 0,
        conditionCode: hour.weather[0]?.id ?? 800,
        windSpeedMs: hour.wind_speed,
        windGustMs: hour.wind_gust,
      };
      const alert = detectStorm(weatherSample);

      segments.push({
        distanceFromStartM: sample.distanceFromStartM,
        time: weatherSample.time,
        tempC: weatherSample.tempC,
        precipitationMmH: weatherSample.precipitationMmH,
        windGustMs: weatherSample.windGustMs,
        conditionCode: weatherSample.conditionCode,
        severity: alert.severity,
      });
    }

    return this.buildReport(segments, samples);
  }

  /**
   * Der schlimmste Alert bestimmt die Meldung (Fahrtrichtungs-Stil) und
   * die Schutz-POI-Suche. POI-Ausfall darf die Wetterantwort NICHT
   * kippen - Shelter sind eine Ergänzung, keine harte Abhängigkeit.
   */
  private async buildReport(
    segments: RouteWeatherSegment[],
    samples: RouteSample[],
  ): Promise<RouteWeatherReport> {
    const alerts = segments
      .map((s) => ({ segment: s, alert: detectStorm(toWeatherSample(s)) }))
      .filter((x) => x.alert.severity !== 'none');

    const worst = worstAlert(alerts.map((x) => x.alert));
    if (!worst) {
      return { isEnabled: true, segments, alert: null, shelters: [] };
    }

    // Erster Abschnitt mit genau dieser (schlimmsten) Severity - bei
    // Gleichstand der früheste, das ist der, den man noch erreichen kann.
    const critical = alerts.find((x) => x.alert === worst)!;
    const criticalSample = nearestSample(samples, critical.segment);

    const message = formatDistanceWarning(worst, critical.segment.distanceFromStartM);

    let shelters: ShelterPoi[] = [];
    try {
      shelters = await this.findShelters(criticalSample.lat, criticalSample.lng);
    } catch (e) {
      this.logger.warn(`Shelter-Suche fehlgeschlagen (Wetterwarnung bleibt aktiv): ${String(e)}`);
    }

    return {
      isEnabled: true,
      segments,
      alert: {
        severity: worst.severity,
        kind: worst.kind,
        message,
        distanceFromStartM: critical.segment.distanceFromStartM,
      },
      shelters,
    };
  }

  /** Schutz-POIs (Hotels, Bikertreffs, Camping) um den kritischen Punkt. */
  private async findShelters(lat: number, lng: number): Promise<ShelterPoi[]> {
    const pad = 0.2; // ~18-22 km, darüber hinaus filtert der Radius
    const pois: Poi[] = await this.poiService.findInBoundingBox({
      bbox: [lng - pad, lat - pad, lng + pad, lat + pad],
      categories: SHELTER_CATEGORIES,
    } as never);

    return pois
      .map((poi) => ({
        id: poi.id,
        name: poi.name,
        category: poi.category as string,
        lat: poi.lat,
        lng: poi.lng,
        distanceFromRouteM: haversineMeters(lat, lng, poi.lat, poi.lng),
      }))
      .filter((p) => p.distanceFromRouteM <= SHELTER_SEARCH_RADIUS_M)
      .sort((a, b) => a.distanceFromRouteM - b.distanceFromRouteM)
      .slice(0, 3);
  }

  private async fetchHourly(lat: number, lng: number): Promise<OwmHourly[] | null> {
    // Auf 2 Dezimalen runden (~1 km): Stauprofil und Kurvenroute teilen
    // sich so denselben Cache-Eintrag.
    const key = `${lat.toFixed(2)},${lng.toFixed(2)}`;
    const cached = this.cache.get(key);
    if (cached && cached.expiresAt > Date.now()) {
      return cached.hourly;
    }

    try {
      let hourly: OwmHourly[];
      if (this.provider === 'owm') {
        hourly = await this.fetchOwm(lat, lng);
      } else {
        hourly = await this.fetchOpenMeteo(lat, lng);
      }
      this.cache.set(key, {
        expiresAt: Date.now() + WEATHER_CACHE_TTL_MS,
        hourly,
      });
      if (this.cache.size > WEATHER_CACHE_MAX) {
        const now = Date.now();
        for (const [k, entry] of this.cache) {
          if (entry.expiresAt <= now) this.cache.delete(k);
        }
      }
      return hourly;
    } catch (e) {
      // Provider-Ausfall degradiert bewusst: Navigation darf nicht
      // blockieren, die App zeigt einfach "kein Wetter" (vgl. Traffic).
      this.logger.warn(`Wetter-Provider nicht erreichbar: ${String(e)}`);
      this.cache.set(key, { expiresAt: Date.now() + 60_000, hourly: [] });
      return null;
    }
  }

  /** OpenWeatherMap One Call 3.0 - wenn OPENWEATHER_API_KEY gesetzt ist. */
  private async fetchOwm(lat: number, lng: number): Promise<OwmHourly[]> {
    const response = await axios.get<OwmOneCallResponse>(
      'https://api.openweathermap.org/data/3.0/onecall',
      {
        params: {
          lat,
          lon: lng,
          exclude: 'minutely,daily,alerts',
          units: 'metric',
          appid: this.config.get<string>('OPENWEATHER_API_KEY'),
        },
        timeout: 8000,
      },
    );
    return response.data.hourly ?? [];
  }

  /** Open-Meteo (Default, keyless) - forecast API, WMO-Code-Mapping. */
  private async fetchOpenMeteo(lat: number, lng: number): Promise<OwmHourly[]> {
    const response = await axios.get<OpenMeteoResponse>(
      'https://api.open-meteo.com/v1/forecast',
      {
        params: {
          latitude: lat,
          longitude: lng,
          hourly: 'temperature_2m,precipitation,wind_gusts_10m,weathercode',
          forecast_days: 2,
          timezone: 'UTC',
        },
        timeout: 8000,
      },
    );
    const h = response.data.hourly;
    if (!h?.time?.length) return [];
    return h.time.map((iso, i) => ({
      dt: Math.floor(new Date(`${iso}Z`).getTime() / 1000),
      temp: h.temperature_2m[i] ?? 0,
      wind_speed: 0, // Open-Meteo: Böen sind der relevante Wert
      wind_gust: h.wind_gusts_10m[i] ?? undefined,
      rain: { '1h': h.precipitation[i] ?? 0 },
      weather: [{ id: wmoCodeToOwm(h.weathercode[i]) }],
    }));
  }
}

export interface RouteSample {
  lat: number;
  lng: number;
  distanceFromStartM: number;
  etaSeconds: number;
}

/** Gleichmäßiges Sampling der Polyline inkl. ETA je Sample. */
export function sampleRoute(
  geometry: number[][],
  durationSeconds: number,
): RouteSample[] {
  if (geometry.length < 2 || !Number.isFinite(durationSeconds)) return [];

  // Kumulierte Distanzen (Euklidisch in Grad überschätzt Meridiane
  // minimal - für die Sample-Verteilung irrelevant).
  const cumulative: number[] = [0];
  for (let i = 1; i < geometry.length; i++) {
    const [lng1, lat1] = geometry[i - 1];
    const [lng2, lat2] = geometry[i];
    cumulative.push(
      cumulative[i - 1] + haversineMeters(lat1, lng1, lat2, lng2),
    );
  }
  const total = cumulative[cumulative.length - 1];
  if (total <= 0) return [];

  const sampleCount = Math.max(
    2,
    Math.min(MAX_SAMPLES, Math.ceil(total / SAMPLE_SPACING_M) + 1),
  );

  const samples: RouteSample[] = [];
  for (let i = 0; i < sampleCount; i++) {
    const target = (total * i) / (sampleCount - 1);
    const point = interpolateAt(geometry, cumulative, target);
    if (!point) continue;
    samples.push({
      lat: point[1],
      lng: point[0],
      distanceFromStartM: target,
      etaSeconds: (durationSeconds * target) / total,
    });
  }
  return samples;
}

/** Punkt an kumulierter Distanz (linear zwischen den Stützpunkten). */
function interpolateAt(
  geometry: number[][],
  cumulative: number[],
  targetM: number,
): number[] | null {
  for (let i = 1; i < cumulative.length; i++) {
    if (cumulative[i] >= targetM) {
      const segLen = cumulative[i] - cumulative[i - 1];
      const t = segLen <= 0 ? 0 : (targetM - cumulative[i - 1]) / segLen;
      const [lng1, lat1] = geometry[i - 1];
      const [lng2, lat2] = geometry[i];
      return [lng1 + (lng2 - lng1) * t, lat1 + (lat2 - lat1) * t];
    }
  }
  return geometry[geometry.length - 1] ?? null;
}

function pickClosestHour(hourly: OwmHourly[], targetMs: number): OwmHourly | null {
  let best: OwmHourly | null = null;
  let bestDelta = Number.POSITIVE_INFINITY;
  for (const hour of hourly) {
    const delta = Math.abs(hour.dt * 1000 - targetMs);
    if (delta < bestDelta) {
      bestDelta = delta;
      best = hour;
    }
  }
  // Größer als 45 min Abstand = keine belastbare Vorhersage für die ETA.
  return bestDelta <= 45 * 60_000 ? best : null;
}

function toWeatherSample(s: RouteWeatherSegment): WeatherSample {
  return {
    time: s.time,
    tempC: s.tempC,
    precipitationMmH: s.precipitationMmH,
    conditionCode: s.conditionCode,
    windSpeedMs: 0,
    windGustMs: s.windGustMs,
  };
}

function nearestSample(
  samples: RouteSample[],
  segment: RouteWeatherSegment,
): RouteSample {
  let best = samples[0];
  let bestDelta = Number.POSITIVE_INFINITY;
  for (const s of samples) {
    const delta = Math.abs(s.distanceFromStartM - segment.distanceFromStartM);
    if (delta < bestDelta) {
      bestDelta = delta;
      best = s;
    }
  }
  return best;
}
