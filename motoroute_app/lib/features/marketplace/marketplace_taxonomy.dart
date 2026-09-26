import 'marketplace_repository.dart';

/// Lokaler Spiegel der Server-Taxonomie (marketplace.taxonomy.ts).
///
/// Zweck: Das Erstell-Formular zeigt die Unterkategorien SOFORT, auch wenn
/// der Katalog-Fetch vom Server scheitert (offline, 401 vor Refresh ...).
/// Die serverseitige Validierung bleibt massgeblich - dieser Katalog ist
/// nur ein Fallback fuer die UI und deckt exakt dieselben Keys ab.

const List<MpSubcategoryDef> _vehicleSubcategories = [
  MpSubcategoryDef(key: 'motor', labelDe: 'Motor', labelEn: 'Engine'),
  MpSubcategoryDef(key: 'motorenteile', labelDe: 'Motorenteile', labelEn: 'Engine parts'),
  MpSubcategoryDef(key: 'zylinder', labelDe: 'Zylinder', labelEn: 'Cylinders'),
  MpSubcategoryDef(key: 'kolben', labelDe: 'Kolben', labelEn: 'Pistons'),
  MpSubcategoryDef(key: 'kupplung', labelDe: 'Kupplung', labelEn: 'Clutch'),
  MpSubcategoryDef(key: 'auspuff', labelDe: 'Auspuff', labelEn: 'Exhaust'),
  MpSubcategoryDef(key: 'kruemmer', labelDe: 'Krümmer', labelEn: 'Headers'),
  MpSubcategoryDef(key: 'schalldaempfer', labelDe: 'Schalldämpfer', labelEn: 'Mufflers'),
  MpSubcategoryDef(key: 'fahrwerk', labelDe: 'Fahrwerk', labelEn: 'Suspension'),
  MpSubcategoryDef(key: 'stossdaempfer', labelDe: 'Stoßdämpfer', labelEn: 'Shock absorbers'),
  MpSubcategoryDef(key: 'gabel', labelDe: 'Gabel', labelEn: 'Forks'),
  MpSubcategoryDef(key: 'bremsen', labelDe: 'Bremsen', labelEn: 'Brakes'),
  MpSubcategoryDef(key: 'bremsscheiben', labelDe: 'Bremsscheiben', labelEn: 'Brake discs'),
  MpSubcategoryDef(key: 'bremsbelaege', labelDe: 'Bremsbeläge', labelEn: 'Brake pads'),
  MpSubcategoryDef(key: 'bremssaettel', labelDe: 'Bremssättel', labelEn: 'Calipers'),
  MpSubcategoryDef(key: 'bremsleitungen', labelDe: 'Bremsleitungen', labelEn: 'Brake lines'),
  MpSubcategoryDef(key: 'elektrik', labelDe: 'Elektrik', labelEn: 'Electrics'),
  MpSubcategoryDef(key: 'batterie', labelDe: 'Batterie', labelEn: 'Battery'),
  MpSubcategoryDef(key: 'licht', labelDe: 'Licht', labelEn: 'Lights'),
  MpSubcategoryDef(key: 'steuergeraete', labelDe: 'Steuergeräte', labelEn: 'ECUs'),
  MpSubcategoryDef(key: 'kabel', labelDe: 'Kabel', labelEn: 'Cables'),
  MpSubcategoryDef(key: 'elektronik', labelDe: 'Elektronik', labelEn: 'Electronics'),
  MpSubcategoryDef(key: 'raeder', labelDe: 'Räder', labelEn: 'Wheels'),
  MpSubcategoryDef(key: 'felgen', labelDe: 'Felgen', labelEn: 'Rims'),
  MpSubcategoryDef(key: 'reifen', labelDe: 'Reifen', labelEn: 'Tires'),
  MpSubcategoryDef(key: 'radteile', labelDe: 'Radteile', labelEn: 'Wheel parts'),
  MpSubcategoryDef(key: 'verkleidung', labelDe: 'Verkleidung', labelEn: 'Fairings'),
  MpSubcategoryDef(key: 'kotfluegel', labelDe: 'Kotflügel', labelEn: 'Fenders'),
  MpSubcategoryDef(key: 'karosserieteile', labelDe: 'Karosserieteile', labelEn: 'Body parts'),
  MpSubcategoryDef(key: 'zubehoer', labelDe: 'Zubehör', labelEn: 'Accessories'),
  MpSubcategoryDef(key: 'gepaeck', labelDe: 'Gepäck', labelEn: 'Luggage'),
  MpSubcategoryDef(key: 'halterungen', labelDe: 'Halterungen', labelEn: 'Mounts'),
  MpSubcategoryDef(key: 'schutzteile', labelDe: 'Schutzteile', labelEn: 'Protection'),
  MpSubcategoryDef(key: 'sonstiges', labelDe: 'Sonstiges', labelEn: 'Other'),
];

const List<MpSubcategoryDef> _carOnlySubcategories = [
  MpSubcategoryDef(key: 'karosserie', labelDe: 'Karosserie', labelEn: 'Body'),
  MpSubcategoryDef(key: 'tueren', labelDe: 'Türen', labelEn: 'Doors'),
  MpSubcategoryDef(key: 'seitenteile', labelDe: 'Seitenteile', labelEn: 'Side panels'),
  MpSubcategoryDef(key: 'innenraum', labelDe: 'Innenraum', labelEn: 'Interior'),
];

const List<MpSubcategoryDef> _bicycleSubcategories = [
  MpSubcategoryDef(key: 'antrieb', labelDe: 'Antrieb', labelEn: 'Drivetrain'),
  MpSubcategoryDef(key: 'schaltung', labelDe: 'Schaltung', labelEn: 'Gears'),
  MpSubcategoryDef(key: 'bremsen', labelDe: 'Bremsen', labelEn: 'Brakes'),
  MpSubcategoryDef(key: 'bremsscheiben', labelDe: 'Bremsscheiben', labelEn: 'Brake discs'),
  MpSubcategoryDef(key: 'bremsbelaege', labelDe: 'Bremsbeläge', labelEn: 'Brake pads'),
  MpSubcategoryDef(key: 'raeder', labelDe: 'Räder', labelEn: 'Wheels'),
  MpSubcategoryDef(key: 'felgen', labelDe: 'Felgen', labelEn: 'Rims'),
  MpSubcategoryDef(key: 'reifen', labelDe: 'Reifen', labelEn: 'Tires'),
  MpSubcategoryDef(key: 'gabel', labelDe: 'Gabel', labelEn: 'Forks'),
  MpSubcategoryDef(key: 'federung', labelDe: 'Federung', labelEn: 'Suspension'),
  MpSubcategoryDef(key: 'rahmen', labelDe: 'Rahmen', labelEn: 'Frames'),
  MpSubcategoryDef(key: 'lenker', labelDe: 'Lenker', labelEn: 'Handlebars'),
  MpSubcategoryDef(key: 'sattel', labelDe: 'Sattel', labelEn: 'Saddles'),
  MpSubcategoryDef(key: 'pedale', labelDe: 'Pedale', labelEn: 'Pedals'),
  MpSubcategoryDef(key: 'beleuchtung', labelDe: 'Beleuchtung', labelEn: 'Lights'),
  MpSubcategoryDef(key: 'akku', labelDe: 'Akku (E-Bike)', labelEn: 'Battery (E-Bike)'),
  MpSubcategoryDef(key: 'ebike_motor', labelDe: 'E-Bike Motor', labelEn: 'E-Bike motor'),
  MpSubcategoryDef(key: 'zubehoer', labelDe: 'Zubehör', labelEn: 'Accessories'),
  MpSubcategoryDef(key: 'gepaeck', labelDe: 'Gepäck', labelEn: 'Luggage'),
  MpSubcategoryDef(key: 'sonstiges', labelDe: 'Sonstiges', labelEn: 'Other'),
];

/// Fallback-Katalog: Hauptkategorien mit ihren Unterkategorien.
/// (Reihenfolge wie im Server: Auto alphabetisch sortiert.)
final List<MpCategoryDef> fallbackCatalog = [
  const MpCategoryDef(
    key: 'motorradteile',
    labelDe: 'Motorradteile',
    labelEn: 'Motorcycle parts',
    subcategories: _vehicleSubcategories,
  ),
  MpCategoryDef(
    key: 'autoteile',
    labelDe: 'Autoteile',
    labelEn: 'Car parts',
    subcategories: [..._vehicleSubcategories, ..._carOnlySubcategories]..sort(
        (a, b) => a.labelDe.compareTo(b.labelDe),
      ),
  ),
  const MpCategoryDef(
    key: 'fahrradteile',
    labelDe: 'Fahrradteile',
    labelEn: 'Bicycle parts',
    subcategories: _bicycleSubcategories,
  ),
];
