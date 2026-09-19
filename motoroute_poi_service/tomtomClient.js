/**
 * Roher HTTP-Client für die TomTom Search API.
 *
 * WICHTIG zu categorySet: Die öffentliche REST-API erwartet NUMERISCHE
 * Kategorie-IDs (z.B. 7315 = Restaurant), nicht die sprechenden
 * UPPER_SNAKE_CASE-Codes ("RESTAURANT"), die z.B. TomTom-eigene
 * Connector/SDK-Layer verwenden. Numerische IDs sollten NIE hartcodiert
 * werden (sie sind pro API-Version/Konto nicht öffentlich stabil
 * dokumentiert) – stattdessen holt sich `categoryResolver.js` die
 * aktuell gültigen IDs live über /search/2/poiCategories.json und matcht
 * sie anhand ihres Namens. Siehe README für die Details/Caveats dieses
 * Ansatzes.
 */

const BASE_URL = 'https://api.tomtom.com';

function apiKey() {
  const key = process.env.TOMTOM_API_KEY;
  if (!key) throw new Error('TOMTOM_API_KEY ist nicht gesetzt (.env prüfen)');
  return key;
}

async function request(path, params = {}) {
  const url = new URL(`${BASE_URL}${path}`);
  url.searchParams.set('key', apiKey());
  for (const [k, v] of Object.entries(params)) {
    if (v !== undefined && v !== null && v !== '') url.searchParams.set(k, v);
  }

  const res = await fetch(url.toString());
  if (!res.ok) {
    const body = await res.text().catch(() => '');
    throw new Error(`TomTom-Fehler ${res.status} bei ${path}: ${body.slice(0, 300)}`);
  }
  return res.json();
}

/** Holt den vollständigen POI-Kategoriebaum (numerische IDs + Namen). */
async function fetchPoiCategoryTree() {
  const json = await request('/search/2/poiCategories.json');
  return json.poiCategories || [];
}

/**
 * Kategoriegestützte Suche (Category Search).
 * @param {object} opts
 * @param {string} opts.query      Freitext-Query (z.B. der Kategoriename selbst)
 * @param {number[]} opts.categoryIds  numerische TomTom-Kategorie-IDs
 * @param {string} opts.countryCode ISO-3166-1 alpha-2 (z.B. "DE")
 * @param {number} opts.limit      max. 100 pro Seite
 * @param {number} opts.offset     Paginierung
 */
async function categorySearch({ query, categoryIds, countryCode, limit = 100, offset = 0 }) {
  const q = encodeURIComponent(query || categoryIds?.[0] || 'poi');
  const json = await request(`/search/2/categorySearch/${q}.json`, {
    categorySet: categoryIds?.join(','),
    countrySet: countryCode,
    limit,
    ofs: offset,
    view: 'Unified',
  });
  return json.results || [];
}

/**
 * Freitext-Suche (Fuzzy Search) – Fallback für Kategorien ohne exaktes
 * TomTom-Pendant (z.B. "Gartenlokal"/"Bikertreff", siehe classifier.js).
 */
async function textSearch({ query, categoryIds, countryCode, limit = 100, offset = 0 }) {
  const json = await request(`/search/2/search/${encodeURIComponent(query)}.json`, {
    categorySet: categoryIds?.join(','),
    countrySet: countryCode,
    limit,
    ofs: offset,
    view: 'Unified',
  });
  return json.results || [];
}

module.exports = { fetchPoiCategoryTree, categorySearch, textSearch };
