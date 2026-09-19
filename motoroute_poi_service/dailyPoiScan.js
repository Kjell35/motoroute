const cron = require('node-cron');
const COUNTRIES = require('./countries');
const { resolveCategoryIds } = require('./categoryResolver');
const { categorySearch, textSearch } = require('./tomtomClient');
const { normalize } = require('./classifier');
const { upsertPoi } = require('./poiRepository');

const OUR_CATEGORIES = [
  'imbiss', 'bikertreff', 'kneipe', 'pension',
  'restaurant', 'hotel', 'zeltplatz', 'gartenlokal',
];

// Rücksicht auf TomTom-Rate-Limits (Free-Tier: wenige req/s).
const THROTTLE_MS = Number(process.env.SCAN_THROTTLE_MS || 350);
// Obergrenze pro Land x Kategorie, damit ein Lauf zeitlich/kostentechnisch
// begrenzt bleibt (TomTom-Suche ist ohnehin nach einigen hundert
// Ergebnissen pro Query ausgeschöpft). Bei Bedarf erhöhen.
const MAX_RESULTS_PER_COUNTRY_CATEGORY = Number(process.env.SCAN_MAX_RESULTS || 300);
const PAGE_SIZE = 100; // TomTom-Maximum pro Anfrage

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function saveResults(results, category) {
  let inserted = 0;
  let updated = 0;
  for (const raw of results) {
    const poi = normalize(raw, category);
    if (!poi) continue;
    const res = await upsertPoi(poi);
    if (res.inserted) inserted += 1;
    else updated += 1;
  }
  return { inserted, updated };
}

/** Reguläre Kategorien: bezahlte categorySearch mit aufgelösten TomTom-IDs. */
async function scanCategorySearch(category, categoryIds, excludeNames, countryCode) {
  let totals = { inserted: 0, updated: 0 };

  for (let offset = 0; offset < MAX_RESULTS_PER_COUNTRY_CATEGORY; offset += PAGE_SIZE) {
    let results;
    try {
      results = await categorySearch({
        query: category,
        categoryIds,
        countryCode,
        limit: PAGE_SIZE,
        offset,
      });
    } catch (err) {
      console.error(`[scan] ${countryCode}/${category} Fehler:`, err.message);
      break;
    }

    if (excludeNames?.size) {
      results = results.filter(
        (r) => !(r.poi?.categories || []).some((c) => excludeNames.has(c.toLowerCase()))
      );
    }

    const { inserted, updated } = await saveResults(results, category);
    totals.inserted += inserted;
    totals.updated += updated;

    if (results.length < PAGE_SIZE) break; // letzte Seite erreicht
    await sleep(THROTTLE_MS);
  }

  return totals;
}

/**
 * Fallback für Kategorien ohne eigenes TomTom-Pendant (bikertreff,
 * gartenlokal): Freitext-Suche, eingeschränkt auf naheliegende
 * Kategorien, damit das Rauschen begrenzt bleibt.
 */
async function scanTextSearch(category, queries, categoryIds, countryCode) {
  let totals = { inserted: 0, updated: 0 };

  for (const query of queries) {
    let results;
    try {
      results = await textSearch({ query, categoryIds, countryCode, limit: PAGE_SIZE });
    } catch (err) {
      console.error(`[scan] ${countryCode}/${category} ("${query}") Fehler:`, err.message);
      continue;
    }
    const { inserted, updated } = await saveResults(results, category);
    totals.inserted += inserted;
    totals.updated += updated;
    await sleep(THROTTLE_MS);
  }

  return totals;
}

async function scanCountry(countryCode, resolved) {
  let inserted = 0;
  let updated = 0;

  for (const category of OUR_CATEGORIES) {
    let result;

    if (category === 'bikertreff') {
      // 1) offizielle Motorrad-Shops/Werkstätten als Treffpunkt-Kandidaten
      const shops = await scanCategorySearch(
        category, resolved.ids.bikertreff_shops, null, countryCode
      );
      // 2) Kneipen/Bars/Restaurants, die sich per Namen als Bikertreff zu erkennen geben
      const venues = await scanTextSearch(
        category, ['Biker Treff', 'Motorradtreff', 'Biker Bar'],
        resolved.ids.bikertreff_venues, countryCode
      );
      result = { inserted: shops.inserted + venues.inserted, updated: shops.updated + venues.updated };
    } else if (category === 'gartenlokal') {
      result = await scanTextSearch(
        category, ['Biergarten', 'Gartenlokal', 'Beer Garden'],
        resolved.ids.gartenlokal_venues, countryCode
      );
    } else {
      result = await scanCategorySearch(
        category, resolved.ids[category], resolved.exclude[category], countryCode
      );
    }

    inserted += result.inserted;
    updated += result.updated;
    await sleep(THROTTLE_MS);
  }

  return { inserted, updated };
}

async function runDailyScan() {
  console.log(`[scan] Start ${new Date().toISOString()} – ${COUNTRIES.length} Länder`);
  const resolved = await resolveCategoryIds();

  let totalInserted = 0;
  let totalUpdated = 0;

  for (const countryCode of COUNTRIES) {
    try {
      const { inserted, updated } = await scanCountry(countryCode, resolved);
      totalInserted += inserted;
      totalUpdated += updated;
      if (inserted || updated) {
        console.log(`[scan] ${countryCode}: +${inserted} neu, ${updated} aktualisiert`);
      }
    } catch (err) {
      console.error(`[scan] Land ${countryCode} fehlgeschlagen:`, err.message);
    }
  }

  console.log(
    `[scan] Ende ${new Date().toISOString()} – gesamt neu: ${totalInserted}, aktualisiert: ${totalUpdated}`
  );
  // Live-Update der Flutter-App passiert NICHT hier, sondern über den
  // Postgres-Trigger `pois_notify_change` (schema.sql), den der
  // API-Server per LISTEN/NOTIFY abonniert hat (siehe server.js).
}

/** Registriert den täglichen Cron-Job. Aufruf z.B. aus server.js. */
function scheduleDailyScan(cronExpression = '0 3 * * *') {
  cron.schedule(cronExpression, () => {
    runDailyScan().catch((err) => console.error('[scan] Unerwarteter Fehler:', err));
  });
  console.log(`[scan] Cron-Job registriert: "${cronExpression}"`);
}

module.exports = { runDailyScan, scheduleDailyScan };
