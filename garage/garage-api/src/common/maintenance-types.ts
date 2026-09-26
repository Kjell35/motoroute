/**
 * Wartungstypen-Katalog (Anforderung 5) mit Standard-Intervallen fuer die
 * automatische Erinnerungslogik (Anforderung 6).
 *
 * Ein Intervall ist optional: intervalKm ODER intervalDays ODER beides.
 * Hat ein Typ kein Standard-Intervall, muss der Nutzer beim Erfassen
 * selbst "next due" angeben (z. B. bei "Sonstige Wartung").
 */

export interface MaintenanceTypeDef {
  key: string;
  labelDe: string;
  labelEn: string;
  /** Standard-Intervall in Kilometern (falls km-basiert). */
  intervalKm?: number;
  /** Standard-Intervall in Tagen (falls zeitbasiert). */
  intervalDays?: number;
  /** Reine Terminsache ohne km (z. B. HU/TUEV/AU). */
  dateOnly?: boolean;
  appliesTo: 'both' | 'motorcycle' | 'car';
}

export const MAINTENANCE_TYPES: MaintenanceTypeDef[] = [
  { key: 'OIL_CHANGE', labelDe: 'Ölwechsel', labelEn: 'Oil change', intervalKm: 10000, intervalDays: 365, appliesTo: 'both' },
  { key: 'OIL_FILTER', labelDe: 'Ölfilter', labelEn: 'Oil filter', intervalKm: 10000, intervalDays: 365, appliesTo: 'both' },
  { key: 'AIR_FILTER', labelDe: 'Luftfilter', labelEn: 'Air filter', intervalKm: 20000, intervalDays: 730, appliesTo: 'both' },
  { key: 'BRAKE_PADS', labelDe: 'Bremsbeläge', labelEn: 'Brake pads', intervalKm: 20000, appliesTo: 'both' },
  { key: 'BRAKE_DISCS', labelDe: 'Bremsscheiben', labelEn: 'Brake discs', intervalKm: 50000, appliesTo: 'both' },
  { key: 'TIRES', labelDe: 'Reifen', labelEn: 'Tires', intervalKm: 30000, intervalDays: 1825, appliesTo: 'both' },
  { key: 'BATTERY', labelDe: 'Batterie', labelEn: 'Battery', intervalDays: 1460, appliesTo: 'both' },
  { key: 'COOLANT', labelDe: 'Kühlmittel', labelEn: 'Coolant', intervalKm: 40000, intervalDays: 1460, appliesTo: 'both' },
  { key: 'BRAKE_FLUID', labelDe: 'Bremsflüssigkeit', labelEn: 'Brake fluid', intervalDays: 730, appliesTo: 'both' },
  { key: 'SPARK_PLUGS', labelDe: 'Zündkerzen', labelEn: 'Spark plugs', intervalKm: 20000, appliesTo: 'both' },
  { key: 'CHAIN', labelDe: 'Kette (spannen/schmieren)', labelEn: 'Chain (tension/lube)', intervalKm: 1000, appliesTo: 'motorcycle' },
  { key: 'CHAIN_OIL', labelDe: 'Kettenöl', labelEn: 'Chain oil', intervalKm: 1000, appliesTo: 'motorcycle' },
  { key: 'TIMING_BELT', labelDe: 'Zahnriemen', labelEn: 'Timing belt', intervalKm: 90000, intervalDays: 1825, appliesTo: 'car' },
  { key: 'INSPECTION', labelDe: 'Inspektion', labelEn: 'Inspection', intervalKm: 15000, intervalDays: 365, appliesTo: 'both' },
  { key: 'HU', labelDe: 'HU/TÜV', labelEn: 'Roadworthiness test', intervalDays: 730, dateOnly: true, appliesTo: 'car' },
  { key: 'AU', labelDe: 'AU (Abgasuntersuchung)', labelEn: 'Emissions test', intervalDays: 730, dateOnly: true, appliesTo: 'car' },
  { key: 'OTHER', labelDe: 'Sonstige Wartung', labelEn: 'Other maintenance', appliesTo: 'both' },
];

export function isMaintenanceType(key: string): boolean {
  return MAINTENANCE_TYPES.some((t) => t.key === key);
}

export function maintenanceTypeOf(key: string): MaintenanceTypeDef | undefined {
  return MAINTENANCE_TYPES.find((t) => t.key === key);
}

/** Wartungstypen, die zu einer Fahrzeugkategorie passen. */
export function maintenanceTypesFor(category: 'motorcycle' | 'car'): MaintenanceTypeDef[] {
  return MAINTENANCE_TYPES.filter((t) => t.appliesTo === 'both' || t.appliesTo === category);
}
