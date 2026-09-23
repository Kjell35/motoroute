/**
 * Marktplatz-Taxonomie: die EINZIGE Quelle für Haupt-/Unterkategorien.
 * Die Migration 0006 spiegelt diesen Katalog in Tabellen (für Filter-UIs),
 * aber die serverseitige Validierung liest IMMER hier - ein Client kann
 * nichts einschleusen, was nicht in diesem Katalog steht.
 */

export type MarketplaceCategory = 'motorradteile' | 'autoteile' | 'fahrradteile';

export interface SubcategoryDef {
  key: string;
  labelDe: string;
  labelEn: string;
}

export interface CategoryDef {
  key: MarketplaceCategory;
  labelDe: string;
  labelEn: string;
  /** Fahrzeugspezifische Unterkategorien (Reihenfolge = UI-Reihenfolge). */
  subcategories: SubcategoryDef[];
}

const vehicleSubcategories: SubcategoryDef[] = [
  { key: 'motor', labelDe: 'Motor', labelEn: 'Engine' },
  { key: 'motorenteile', labelDe: 'Motorenteile', labelEn: 'Engine parts' },
  { key: 'zylinder', labelDe: 'Zylinder', labelEn: 'Cylinders' },
  { key: 'kolben', labelDe: 'Kolben', labelEn: 'Pistons' },
  { key: 'kupplung', labelDe: 'Kupplung', labelEn: 'Clutch' },
  { key: 'auspuff', labelDe: 'Auspuff', labelEn: 'Exhaust' },
  { key: 'kruemmer', labelDe: 'Krümmer', labelEn: 'Headers' },
  { key: 'schalldaempfer', labelDe: 'Schalldämpfer', labelEn: 'Mufflers' },
  { key: 'fahrwerk', labelDe: 'Fahrwerk', labelEn: 'Suspension' },
  { key: 'stossdaempfer', labelDe: 'Stoßdämpfer', labelEn: 'Shock absorbers' },
  { key: 'gabel', labelDe: 'Gabel', labelEn: 'Forks' },
  { key: 'bremsen', labelDe: 'Bremsen', labelEn: 'Brakes' },
  { key: 'bremsscheiben', labelDe: 'Bremsscheiben', labelEn: 'Brake discs' },
  { key: 'bremsbelaege', labelDe: 'Bremsbeläge', labelEn: 'Brake pads' },
  { key: 'bremssaettel', labelDe: 'Bremssättel', labelEn: 'Calipers' },
  { key: 'bremsleitungen', labelDe: 'Bremsleitungen', labelEn: 'Brake lines' },
  { key: 'elektrik', labelDe: 'Elektrik', labelEn: 'Electrics' },
  { key: 'batterie', labelDe: 'Batterie', labelEn: 'Battery' },
  { key: 'licht', labelDe: 'Licht', labelEn: 'Lights' },
  { key: 'steuergeraete', labelDe: 'Steuergeräte', labelEn: 'ECUs' },
  { key: 'kabel', labelDe: 'Kabel', labelEn: 'Cables' },
  { key: 'elektronik', labelDe: 'Elektronik', labelEn: 'Electronics' },
  { key: 'raeder', labelDe: 'Räder', labelEn: 'Wheels' },
  { key: 'felgen', labelDe: 'Felgen', labelEn: 'Rims' },
  { key: 'reifen', labelDe: 'Reifen', labelEn: 'Tires' },
  { key: 'radteile', labelDe: 'Radteile', labelEn: 'Wheel parts' },
  { key: 'verkleidung', labelDe: 'Verkleidung', labelEn: 'Fairings' },
  { key: 'kotfluegel', labelDe: 'Kotflügel', labelEn: 'Fenders' },
  { key: 'karosserieteile', labelDe: 'Karosserieteile', labelEn: 'Body parts' },
  { key: 'zubehoer', labelDe: 'Zubehör', labelEn: 'Accessories' },
  { key: 'gepaeck', labelDe: 'Gepäck', labelEn: 'Luggage' },
  { key: 'halterungen', labelDe: 'Halterungen', labelEn: 'Mounts' },
  { key: 'schutzteile', labelDe: 'Schutzteile', labelEn: 'Protection' },
  { key: 'sonstiges', labelDe: 'Sonstiges', labelEn: 'Other' },
];

const carOnlySubcategories: SubcategoryDef[] = [
  { key: 'karosserie', labelDe: 'Karosserie', labelEn: 'Body' },
  { key: 'tueren', labelDe: 'Türen', labelEn: 'Doors' },
  { key: 'seitenteile', labelDe: 'Seitenteile', labelEn: 'Side panels' },
  { key: 'innenraum', labelDe: 'Innenraum', labelEn: 'Interior' },
];

const bicycleSubcategories: SubcategoryDef[] = [
  { key: 'antrieb', labelDe: 'Antrieb', labelEn: 'Drivetrain' },
  { key: 'schaltung', labelDe: 'Schaltung', labelEn: 'Gears' },
  { key: 'kette', labelDe: 'Kette', labelEn: 'Chain' },
  { key: 'kurbel', labelDe: 'Kurbel', labelEn: 'Crankset' },
  { key: 'bremsen', labelDe: 'Bremsen', labelEn: 'Brakes' },
  { key: 'bremsscheiben', labelDe: 'Bremsscheiben', labelEn: 'Brake discs' },
  { key: 'bremsbelaege', labelDe: 'Bremsbeläge', labelEn: 'Brake pads' },
  { key: 'raeder', labelDe: 'Räder', labelEn: 'Wheels' },
  { key: 'laufräder', labelDe: 'Laufräder', labelEn: 'Wheelsets' },
  { key: 'felgen', labelDe: 'Felgen', labelEn: 'Rims' },
  { key: 'reifen', labelDe: 'Reifen', labelEn: 'Tires' },
  { key: 'gabel', labelDe: 'Gabel', labelEn: 'Forks' },
  { key: 'federung', labelDe: 'Federung', labelEn: 'Suspension' },
  { key: 'rahmen', labelDe: 'Rahmen', labelEn: 'Frames' },
  { key: 'lenker', labelDe: 'Lenker', labelEn: 'Handlebars' },
  { key: 'sattel', labelDe: 'Sattel', labelEn: 'Saddles' },
  { key: 'pedale', labelDe: 'Pedale', labelEn: 'Pedals' },
  { key: 'beleuchtung', labelDe: 'Beleuchtung', labelEn: 'Lights' },
  { key: 'akku', labelDe: 'Akku (E-Bike)', labelEn: 'Battery (E-Bike)' },
  { key: 'ebike_motor', labelDe: 'E-Bike Motor', labelEn: 'E-Bike motor' },
  { key: 'zubehoer', labelDe: 'Zubehör', labelEn: 'Accessories' },
  { key: 'gepaeck', labelDe: 'Gepäck', labelEn: 'Luggage' },
  { key: 'sonstiges', labelDe: 'Sonstiges', labelEn: 'Other' },
];

export const MARKETPLACE_CATEGORIES: CategoryDef[] = [
  {
    key: 'motorradteile',
    labelDe: 'Motorradteile',
    labelEn: 'Motorcycle parts',
    // Motorrad-spezifisch: keine Karosserie/Türen/Innenraum, dafür Verkleidung
    subcategories: vehicleSubcategories.filter((s) => s.key !== 'karosserie'),
  },
  {
    key: 'autoteile',
    labelDe: 'Autoteile',
    labelEn: 'Car parts',
    subcategories: [...vehicleSubcategories, ...carOnlySubcategories].sort(
      (a, b) => a.labelDe.localeCompare(b.labelDe, 'de'),
    ),
  },
  {
    key: 'fahrradteile',
    labelDe: 'Fahrradteile',
    labelEn: 'Bicycle parts',
    subcategories: bicycleSubcategories,
  },
];

export const MARKETPLACE_CONDITIONS = [
  'neu',
  'sehr_gut',
  'gut',
  'gebraucht',
  'defekt',
] as const;
export type MarketplaceCondition = (typeof MARKETPLACE_CONDITIONS)[number];

export function isCategory(value: unknown): value is MarketplaceCategory {
  return MARKETPLACE_CATEGORIES.some((c) => c.key === value);
}

export function isSubcategory(category: MarketplaceCategory, value: unknown): boolean {
  const def = MARKETPLACE_CATEGORIES.find((c) => c.key === category);
  return !!def && def.subcategories.some((s) => s.key === value);
}

export function isCondition(value: unknown): value is MarketplaceCondition {
  return (MARKETPLACE_CONDITIONS as readonly string[]).includes(value as string);
}
