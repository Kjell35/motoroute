/**
 * Definierte Schluessel fuer technische Eckdaten (Anforderung 3).
 * Die Liste ist im Code gepflegt - ein neuer Schluessel braucht keine
 * DB-Migration, nur eine Zeile hier. Units sind Anzeige-Hilfen.
 */

export interface SpecKeyDef {
  key: string;
  labelDe: string;
  labelEn: string;
  unit?: string;
  /** Nur fuer Elektrofahrzeuge relevant (Anforderung 3, EV-Zusatzblock). */
  evOnly?: boolean;
}

export const SPEC_KEYS: SpecKeyDef[] = [
  { key: 'engine', labelDe: 'Motor', labelEn: 'Engine' },
  { key: 'engine_displacement_cc', labelDe: 'Hubraum', labelEn: 'Displacement', unit: 'ccm' },
  { key: 'power_hp', labelDe: 'Leistung', labelEn: 'Power', unit: 'PS' },
  { key: 'torque_nm', labelDe: 'Drehmoment', labelEn: 'Torque', unit: 'Nm' },
  { key: 'fuel_type', labelDe: 'Kraftstoffart', labelEn: 'Fuel type' },
  { key: 'gearbox', labelDe: 'Getriebe', labelEn: 'Gearbox' },
  { key: 'weight_kg', labelDe: 'Gewicht', labelEn: 'Weight', unit: 'kg' },
  { key: 'tank_capacity_l', labelDe: 'Tankgröße', labelEn: 'Tank capacity', unit: 'l' },
  { key: 'consumption', labelDe: 'Verbrauch', labelEn: 'Consumption', unit: 'l/100km' },
  { key: 'top_speed_kmh', labelDe: 'Höchstgeschwindigkeit', labelEn: 'Top speed', unit: 'km/h' },
  { key: 'acceleration_0_100_s', labelDe: '0-100 km/h', labelEn: '0-100 km/h', unit: 's' },
  { key: 'drive', labelDe: 'Antrieb', labelEn: 'Drive' },
  { key: 'tire_sizes', labelDe: 'Reifengrößen', labelEn: 'Tire sizes' },
  { key: 'brakes', labelDe: 'Bremsanlage', labelEn: 'Brakes' },
  // --- Elektro-Zusatz (Anforderung 3) ---
  { key: 'battery_capacity_kwh', labelDe: 'Batteriekapazität', labelEn: 'Battery capacity', unit: 'kWh', evOnly: true },
  { key: 'range_km', labelDe: 'Reichweite', labelEn: 'Range', unit: 'km', evOnly: true },
  { key: 'charging_power_kw', labelDe: 'Ladeleistung', labelEn: 'Charging power', unit: 'kW', evOnly: true },
  { key: 'charging_time_h', labelDe: 'Ladezeit', labelEn: 'Charging time', unit: 'h', evOnly: true },
];

export function isSpecKey(key: string): boolean {
  return SPEC_KEYS.some((s) => s.key === key);
}

export function specKeyOf(key: string): SpecKeyDef | undefined {
  return SPEC_KEYS.find((s) => s.key === key);
}
