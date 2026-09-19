/**
 * Wandelt ein TomTom Search-API-Ergebnis in unser normalisiertes
 * POI-Format um und berechnet einen Biker-Eignungs-Score (0-100).
 *
 * Erwartete Form eines TomTom-Ergebnisses (Standard Search-API-Schema):
 * {
 *   id, poi: { name, categories: ["Restaurant", ...], categorySet: [{id}] },
 *   position: { lat, lon },
 *   address: { freeformAddress, country, countryCode },
 * }
 */

const BIKER_KEYWORDS = /biker|motorrad|motorcycle|harley|\bmc\b/i;

function computeBikerScore({ category, categoryNames = [], name = '' }) {
  let score = 40; // Basiswert: jede POI dieser 8 Kategorien ist grundsätzlich relevant

  if (category === 'bikertreff') score += 35;
  if (categoryNames.some((c) => /motorcycle/i.test(c))) score += 20;
  if (BIKER_KEYWORDS.test(name)) score += 15;
  if (category === 'zeltplatz') score += 5; // Camping ist bei Motorradreisenden traditionell beliebt
  if (category === 'gartenlokal') score += 5; // Außenbereich = gute Anlaufstelle nach der Tour

  return Math.max(0, Math.min(100, score));
}

function buildAmenities({ category, categoryNames = [] }) {
  const isMotorcycleShop = categoryNames.some((c) => /motorcycle/i.test(c));
  return {
    motorcycle_parking: category === 'bikertreff' || isMotorcycleShop,
    workshop_corner: isMotorcycleShop,
    meeting_point: category === 'bikertreff',
    outdoor_seating: category === 'gartenlokal',
  };
}

/**
 * @param {object} result rohes TomTom-Suchergebnis
 * @param {string} category unsere Ziel-Kategorie (wird beim Fetch mitgegeben)
 * @returns {object|null} normalisierter POI oder null bei fehlenden Pflichtfeldern
 */
function normalize(result, category) {
  const name = result.poi?.name;
  const lat = result.position?.lat;
  const lon = result.position?.lon;
  if (!name || lat == null || lon == null) return null;

  const categoryNames = result.poi?.categories || [];

  return {
    name,
    category,
    lat,
    lon,
    address: result.address?.freeformAddress || '',
    countryCode: (result.address?.countryCode || '').toUpperCase().slice(0, 2) || null,
    bikerScore: computeBikerScore({ category, categoryNames, name }),
    amenities: buildAmenities({ category, categoryNames }),
    source: 'tomtom',
    sourceId: result.id,
  };
}

module.exports = { normalize, computeBikerScore, buildAmenities };
