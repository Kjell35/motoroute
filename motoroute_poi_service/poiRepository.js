const { pool } = require('./db');

// Umkreis für Duplikatprüfung: gleiche Kategorie innerhalb dieses Radius
// gilt als "derselbe Ort" (z.B. leicht unterschiedliche OSM-Koordinaten
// desselben Gasthauses).
const DUPLICATE_RADIUS_METERS = 75;

/**
 * Prüft per PostGIS ST_DWithin, ob es an dieser Position bereits einen
 * aktiven POI derselben Kategorie gibt.
 * @returns {Promise<string|null>} vorhandene POI-id oder null
 */
async function findNearbyDuplicate({ category, lat, lon }) {
  const { rows } = await pool.query(
    `SELECT id FROM pois
     WHERE category = $1
       AND is_active = TRUE
       AND ST_DWithin(geog, ST_MakePoint($2, $3)::geography, $4)
     ORDER BY ST_Distance(geog, ST_MakePoint($2, $3)::geography) ASC
     LIMIT 1`,
    [category, lon, lat, DUPLICATE_RADIUS_METERS]
  );
  return rows[0]?.id ?? null;
}

/**
 * Legt einen neuen POI an, oder aktualisiert einen bestehenden (per
 * source+source_id ODER erkanntem räumlichen Duplikat).
 * @returns {Promise<{id: string, inserted: boolean}>}
 */
async function upsertPoi(poi) {
  const duplicateId = await findNearbyDuplicate(poi);

  if (duplicateId) {
    await pool.query(
      `UPDATE pois SET
         name = $2, address = $3, country_code = $4,
         biker_score = $5, amenities = $6, source = $7, source_id = $8,
         last_verified_at = now(), is_active = TRUE
       WHERE id = $1`,
      [
        duplicateId,
        poi.name,
        poi.address,
        poi.countryCode,
        poi.bikerScore,
        JSON.stringify(poi.amenities),
        poi.source,
        poi.sourceId,
      ]
    );
    return { id: duplicateId, inserted: false };
  }

  const { rows } = await pool.query(
    `INSERT INTO pois
       (name, category, geog, address, country_code, biker_score, amenities, source, source_id)
     VALUES
       ($1, $2, ST_MakePoint($3, $4)::geography, $5, $6, $7, $8, $9, $10)
     ON CONFLICT (source, source_id) DO UPDATE SET
       last_verified_at = now(), is_active = TRUE
     RETURNING id, (xmax = 0) AS inserted`,
    [
      poi.name,
      poi.category,
      poi.lon,
      poi.lat,
      poi.address,
      poi.countryCode,
      poi.bikerScore,
      JSON.stringify(poi.amenities),
      poi.source,
      poi.sourceId,
    ]
  );
  return { id: rows[0].id, inserted: rows[0].inserted };
}

/**
 * Delta-Sync für die Flutter-App: alle POIs, die sich seit `since`
 * geändert haben (neu, aktualisiert oder deaktiviert/gelöscht),
 * optional gefiltert nach Umkreis und Kategorien.
 */
async function getDelta({ since, lat, lon, radiusKm, categories }) {
  const params = [since];
  let where = 'updated_at > $1';

  if (lat != null && lon != null && radiusKm != null) {
    params.push(lon, lat, radiusKm * 1000);
    where += ` AND ST_DWithin(geog, ST_MakePoint($${params.length - 2}, $${params.length - 1})::geography, $${params.length})`;
  }

  if (categories && categories.length > 0) {
    params.push(categories);
    where += ` AND category = ANY($${params.length}::poi_category[])`;
  }

  // FIX: bewusst > LIMIT, damit der Client an hasMore erkennt, dass es
  // noch mehr gibt - bei == LIMIT wäre unklar, ob es exakt bis zum Limit
  // gefüllt war oder der Rest abgeschnitten wurde.
  const DELTA_LIMIT = 2000;
  const { rows } = await pool.query(
    `SELECT id, name, category,
            ST_Y(geog::geometry) AS lat, ST_X(geog::geometry) AS lon,
            address, country_code, biker_score, amenities,
            is_active, updated_at
     FROM pois
     WHERE ${where}
     ORDER BY updated_at ASC
     LIMIT ${DELTA_LIMIT + 1}`,
    params
  );

  const hasMore = rows.length > DELTA_LIMIT;
  const capped = rows.slice(0, DELTA_LIMIT);

  return {
    upserted: capped.filter((r) => r.is_active),
    deletedIds: capped.filter((r) => !r.is_active).map((r) => r.id),
    hasMore,
    // neuestes updated_at im gelieferten Satz - der Client speichert dies
    // als nächstes `since`, verliert so KEINE Zeile beim Pagination-Abbruch.
    cursor: capped.length ? capped[capped.length - 1].updated_at.toISOString() : null,
  };
}

module.exports = { findNearbyDuplicate, upsertPoi, getDelta, DUPLICATE_RADIUS_METERS };
