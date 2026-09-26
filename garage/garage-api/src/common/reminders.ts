/**
 * Automatische Erinnerungslogik (Anforderung 6).
 *
 * Aus der letzten Wartung eines Typs + dem Intervall (km und/oder Tage)
 * wird der Fälligkeitsstatus berechnet:
 *   green  = alles in Ordnung (noch > 10 % Intervall bzw. > 30 Tage)
 *   yellow = bald fällig (Schwellen unterschritten)
 *   red    = überfällig
 *   none   = kein Intervall definiert / noch nie gewartet
 */

export type ReminderStatus = 'green' | 'yellow' | 'red' | 'none';

export interface LastMaintenance {
  type: string;
  performedAt: Date;
  odometerKm: number;
  nextDueDate: Date | null;
  nextDueOdometerKm: number | null;
}

export interface Interval {
  intervalKm?: number;
  intervalDays?: number;
}

export interface Reminder {
  type: string;
  /** Letzte Wartung als Referenz (null = noch nie gewartet). */
  lastPerformedAt: string | null;
  lastOdometerKm: number | null;
  /** Fällig am (ISO) bzw. bei (km) - jeweils der NÄCHSTE Termin. */
  dueAt: string | null;
  dueAtKm: number | null;
  status: ReminderStatus;
  /** Menschliche Kurzinfo: "Ölwechsel in 800 km", "HU in 45 Tagen". */
  messageDe: string;
}

/** Tage bis zu einem Datum (auf ganze Tage gerundet). */
function daysUntil(date: Date, now: Date): number {
  return Math.ceil((date.getTime() - now.getTime()) / 86_400_000);
}

/**
 * Status fuer EINEN Wartungstyp. currentOdometer = aktueller Km-Stand des
 * Fahrzeugs. Das Intervall kommt aus nextDue*-Feldern der letzten Wartung,
 * wenn vorhanden, sonst aus dem Standard-Katalog.
 */
export function computeReminder(
  typeDef: { key: string; labelDe: string } & Interval,
  last: LastMaintenance | null,
  currentOdometer: number,
  now: Date = new Date(),
): Reminder {
  // Nutzer-Overrides schlagen Katalog-Intervalle.
  const dueDate = last?.nextDueDate ?? (last && typeDef.intervalDays ? new Date(last.performedAt.getTime() + typeDef.intervalDays * 86_400_000) : null);
  const dueKm = last?.nextDueOdometerKm ?? (last && typeDef.intervalKm ? last.odometerKm + typeDef.intervalKm : null);

  const kmRemaining = dueKm != null ? dueKm - currentOdometer : null;
  const daysRemaining = dueDate != null ? daysUntil(dueDate, now) : null;

  if (kmRemaining == null && daysRemaining == null) {
    return {
      type: typeDef.key,
      lastPerformedAt: last ? last.performedAt.toISOString() : null,
      lastOdometerKm: last ? last.odometerKm : null,
      dueAt: null,
      dueAtKm: null,
      status: 'none',
      messageDe: `${typeDef.labelDe}: noch nie erfasst`,
    };
  }

  // Ueberfaellig, wenn EINE Dimension verletzt ist.
  const overKm = kmRemaining != null && kmRemaining <= 0;
  const overDays = daysRemaining != null && daysRemaining <= 0;
  const soonKm = kmRemaining != null && kmRemaining <= Math.max(500, (typeDef.intervalKm ?? 10000) * 0.1);
  const soonDays = daysRemaining != null && daysRemaining <= 30;

  const status: ReminderStatus = overKm || overDays ? 'red' : soonKm || soonDays ? 'yellow' : 'green';

  // Nachricht: die kritischere Dimension zuerst nennen.
  const parts: string[] = [];
  if (kmRemaining != null) {
    parts.push(kmRemaining > 0 ? `in ${kmRemaining.toLocaleString('de-DE')} km` : `${Math.abs(kmRemaining).toLocaleString('de-DE')} km überfällig`);
  }
  if (daysRemaining != null) {
    parts.push(daysRemaining > 0 ? `in ${daysRemaining} Tagen` : `${Math.abs(daysRemaining)} Tage überfällig`);
  }
  const messageDe = `${typeDef.labelDe} ${parts.join(', ')}`;

  return {
    type: typeDef.key,
    lastPerformedAt: last ? last.performedAt.toISOString() : null,
    lastOdometerKm: last ? last.odometerKm : null,
    dueAt: dueDate ? dueDate.toISOString() : null,
    dueAtKm: dueKm,
    status,
    messageDe,
  };
}

/** Gesamtbild: schlimmster Status gewinnt (rot > gelb > gruen). */
export function worstStatus(statuses: ReminderStatus[]): ReminderStatus {
  if (statuses.includes('red')) return 'red';
  if (statuses.includes('yellow')) return 'yellow';
  if (statuses.includes('green')) return 'green';
  return 'none';
}
