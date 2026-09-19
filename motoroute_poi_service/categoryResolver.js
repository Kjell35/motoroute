const { fetchPoiCategoryTree } = require('./tomtomClient');

/**
 * Für jede unserer 8 Kategorien: eine Liste möglicher exakter TomTom-
 * Kategorienamen (in der Reihenfolge der Priorität). Diese Namen wurden
 * gegen den echten TomTom-Kategoriebaum verifiziert (Stand: Integration
 * dieses Backends) – Ausnahmen sind unten kommentiert.
 *
 * "imbiss", "kneipe", "hotel", "pension", "restaurant" und "zeltplatz"
 * matchen auf reguläre TomTom-POI-Kategorien. Für "bikertreff" und
 * "gartenlokal" gibt es KEINE eigene TomTom-Kategorie – dafür wird in
 * dailyPoiScan.js zusätzlich eine Freitext-Suche (textSearch) gefahren,
 * siehe CATEGORY_STRATEGIES dort.
 */
const CATEGORY_NAME_CANDIDATES = {
  imbiss: ['Fast Food'],
  kneipe: ['Pub', 'Bar'],
  pension: ['B&B/Guest House', 'Guest House'],
  restaurant: ['Restaurant'], // Achtung: "Fast Food" ist TomTom-seitig ein Kind von "Restaurant" -> siehe EXCLUDE unten
  hotel: ['Hotel'],
  zeltplatz: ['Campground', 'Caravan Site'],
  // bikertreff / gartenlokal: keine categorySet-Einträge, nur Text-Fallback-Kategorien
  bikertreff_shops: ['Motorcycle Dealer', 'Motorcycle Repair'],
  bikertreff_venues: ['Café/Pub', 'Bar', 'Restaurant'], // Basis für die Freitext-Suche "Biker"/"Motorradtreff"
  gartenlokal_venues: ['Restaurant', 'Café/Pub'], // Basis für die Freitext-Suche "Biergarten"/"Gartenlokal"
};

// Wird bei der "restaurant"-Suche ausgeschlossen, weil sonst dieselben
// Orte doppelt (als restaurant UND imbiss) auftauchen würden.
const EXCLUDE_NAME_FOR = {
  restaurant: ['Fast Food'],
};

let cachedCategories = null;
let cachedResolved = null;

/** Findet alle IDs, deren Name (case-insensitive, exakt) zu den Kandidaten passt. */
function findIdsByNames(categories, candidateNames) {
  const wanted = new Set(candidateNames.map((n) => n.toLowerCase()));
  return categories.filter((n) => wanted.has((n.name || '').toLowerCase())).map((n) => n.id);
}

/**
 * Lädt den TomTom-Kategorienkatalog (einmalig, gecacht; poiCategories.json
 * liefert bereits eine FLACHE Liste, in der auch Unterkategorien wie
 * "Fast Food" als eigener Eintrag mit eigener numerischer ID vorkommen)
 * und löst daraus IDs für alle Einträge in CATEGORY_NAME_CANDIDATES auf.
 * Kategorien ohne Treffer werden geloggt, damit ein Namenswechsel bei
 * TomTom sofort auffällt statt still Ergebnisse zu verlieren.
 */
async function resolveCategoryIds() {
  if (cachedResolved) return cachedResolved;

  const categories = cachedCategories || (cachedCategories = await fetchPoiCategoryTree());

  const resolved = {};
  for (const [key, candidateNames] of Object.entries(CATEGORY_NAME_CANDIDATES)) {
    const ids = findIdsByNames(categories, candidateNames);
    if (ids.length === 0) {
      console.warn(
        `[categoryResolver] Keine TomTom-Kategorie-ID gefunden für "${key}" ` +
        `(gesucht: ${candidateNames.join(', ')}) – TomTom hat evtl. Namen geändert.`
      );
    }
    resolved[key] = ids;
  }

  const exclude = {};
  for (const [key, names] of Object.entries(EXCLUDE_NAME_FOR)) {
    exclude[key] = new Set(names.map((n) => n.toLowerCase()));
  }

  cachedResolved = { ids: resolved, exclude };
  return cachedResolved;
}

module.exports = { resolveCategoryIds, CATEGORY_NAME_CANDIDATES };
