/**
 * Warn-Algorithmus des Wetter-Radars.
 *
 * Alle Schwellen an einer Stelle, damit sie testbar und nachjustierbar
 * sind. Werte orientieren sich an:"wann wird es für Motorradfahren
 * unbequem/gefährlich" (nicht an "Unwetterwarnung DWD"):
 * - Starkregen: ab 7.6 mm/h (courtesy DWD "heftiger Regen") - Sicht
 *   und Grip brechen hier messbar ein.
 * - Gewitter: JEDER Blitz-Code (OWM 2xx) warnt, Severity skaliert mit
 *   Intensität.
 * - Böen: ab 10.8 m/s (~39 km/h) auffällig, ab 17.2 m/s (~62 km/h,
 *   "Sturmböe" DWD) gefährlich - ein Motorrad wird hier aktiv
 *   vom Wind verschoben.
 */

export interface WeatherSample {
  /** ISO-8601 UTC-Zeitpunkt der Vorhersage. */
  readonly time: string;
  readonly tempC: number;
  /** Niederschlag mm/h (OWM rain['1h']). */
  readonly precipitationMmH: number;
  /** OWM weather condition code (2xx Gewitter, 5xx Regen, 6xx Schnee). */
  readonly conditionCode: number;
  /** Dauerhafte Windgeschwindigkeit m/s. */
  readonly windSpeedMs: number;
  /** Böen m/s (One Call 3.0: Feld 'wind_gust', optional). */
  readonly windGustMs?: number;
}

export type StormSeverity = 'none' | 'advisory' | 'warning' | 'danger';

export interface StormAlert {
  readonly severity: StormSeverity;
  /** Deutsch, für die direkte Anzeige ("In 20 km zieht ein Gewitter auf"). */
  readonly message: string;
  /** Maschinenlesbar für UI-Icons/Tests. */
  readonly kind: 'rain' | 'thunderstorm' | 'gusts' | 'mixed';
}

const RAIN_ADVISORY_MM_H = 2.5;
const RAIN_WARNING_MM_H = 7.6;
const GUST_ADVISORY_MS = 10.8;
const GUST_DANGER_MS = 17.2;

function isThunderstorm(code: number): boolean {
  return code >= 200 && code < 300;
}

function isSnow(code: number): boolean {
  return code >= 600 && code < 700;
}

function rainKind(rainMmH: number): 'none' | 'advisory' | 'danger' {
  if (rainMmH >= RAIN_WARNING_MM_H) return 'danger';
  if (rainMmH >= RAIN_ADVISORY_MM_H) return 'advisory';
  return 'none';
}

function gustKind(gustMs: number | undefined): 'none' | 'advisory' | 'danger' {
  if (gustMs === undefined) return 'none';
  if (gustMs >= GUST_DANGER_MS) return 'danger';
  if (gustMs >= GUST_ADVISORY_MS) return 'advisory';
  return 'none';
}

/**
 * Bewertet einen einzelnen Wetter-Sample als Sturm-Alert (oder none).
 * Reihenfolge der message-Bausteine: Gewitter schlägt Starkregen
 * schlägt Böen - der gefährlichste Faktor führt.
 */
export function detectStorm(sample: WeatherSample): StormAlert {
  const rain = rainKind(sample.precipitationMmH);
  const gust = gustKind(sample.windGustMs);
  const thunder = isThunderstorm(sample.conditionCode);
  const snow = isSnow(sample.conditionCode);

  // Schneefall ist für Motorradfahren eigenständig gefährlich (Grip-
  // Verlust, Unterkühlung) - er allein rechtfertigt eine Advisory.
  if (!thunder && rain === 'none' && gust === 'none' && !snow) {
    return { severity: 'none', message: '', kind: 'rain' };
  }

  const parts: string[] = [];

  if (thunder) parts.push('Gewitter');
  if (rain === 'danger') parts.push('Starkregen');
  else if (rain === 'advisory' && !thunder) parts.push('Regen');
  if (gust === 'danger') parts.push('Sturmböen');
  else if (gust === 'advisory') parts.push('frische Böen');
  if (snow && rain !== 'danger') parts.push('Schneefall');

  // kind konservativ aus den BEIGETRAGENEN Faktoren ableiten - nie
  // aus dem Initialwert, sonst entsteht 'mixed' ohne zweiten Faktor.
  const dangerCount =
    (thunder ? 1 : 0) + (rain === 'danger' ? 1 : 0) + (gust === 'danger' ? 1 : 0);
  const kind: StormAlert['kind'] =
    dangerCount >= 2
      ? 'mixed'
      : thunder
        ? 'thunderstorm'
        : rain === 'danger' || rain === 'advisory'
          ? 'rain'
          : 'gusts';

  // Severity: danger bei Gewitter, Starkregen oder Sturmböen.
  const severity: StormSeverity =
    thunder || rain === 'danger' || gust === 'danger' ? 'danger' : 'advisory';

  const message = parts.length > 0 ? parts.join(' + ') : '';
  return { severity, message, kind };
}

/** Höchste Severity gewinnt; bei Gleichstand der erste (früheste) Alert. */
export function worstAlert(alerts: readonly StormAlert[]): StormAlert | null {
  const order: Record<StormSeverity, number> = {
    none: 0,
    advisory: 1,
    warning: 2,
    danger: 3,
  };
  let worst: StormAlert | null = null;
  for (const a of alerts) {
    if (a.severity === 'none') continue;
    if (worst === null || order[a.severity] > order[worst.severity]) {
      worst = a;
    }
  }
  return worst;
}

/**
 * Distanz-Warnmeldung im Fahrtrichtungs-Stil: "In 20 km zieht ein
 * Gewitter auf". Vor dem Startpunkt: "Am Start"; nach dem Ziel: "am
 * Ziel der Route". > 90 km wird bewusst als "Auf späterem Strecken-
 * abschnitt" formuliert - "in 140 km" ist für die Fahrtentscheidung
 * wertlos.
 */
export function formatDistanceWarning(alert: StormAlert, distanceMeters: number): string {
  if (alert.severity === 'none' || alert.message === '') return '';
  const km = distanceMeters / 1000;
  let where: string;
  if (km < 1) {
    where = 'Am Startpunkt';
  } else if (km <= 90) {
    where = `In ${Math.round(km)} km`;
  } else {
    where = 'Auf späterem Streckenabschnitt';
  }
  const verb =
    alert.kind === 'thunderstorm'
      ? 'zieht ein Gewitter auf'
      : alert.kind === 'mixed'
        ? 'zieht Unwetter auf'
        : alert.kind === 'rain'
          ? 'kommt Regen auf'
          : 'sind Sturmböen möglich';
  return `${where} ${verb}: ${alert.message}`;
}
