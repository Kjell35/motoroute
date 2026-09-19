const { pool } = require('./db');

/**
 * Radar-Datenzugriff. Alle räumlichen Operationen laufen in PostGIS
 * (GEOGRAPHY-Typ: Distanzen in Metern, ST_DWithin indexgestützt über
 * den GiST-Index). Positionen sind TRANSIENT: Eine Zeile pro Biker,
 * jede Aktualisierung überschreibt - keine Historie, kein Tracking.
 */

/** Sichtbar im Radar bleiben: Positionen jünger als 30 Minuten. */
const STALE_AFTER_MINUTES = 30;
/** Radar-Umkreis (Meter). */
const NEARBY_RADIUS_METERS = 15000;
/** Sicherheitsdeckel der Antwortgröße pro Update. */
const NEARBY_LIMIT = 200;

/**
 * Speichert/aktualisiert die Position eines Bikers (UPSERT).
 * User ohne Ghost-Mode only - der Handler prüft das vorher.
 */
async function upsertBikerLocation(userId, latitude, longitude) {
  await pool.query(
    `insert into active_bikers (user_id, location, latitude, longitude, last_seen)
     values ($1, st_setsrid(st_makepoint($2, $3), 4326)::geography, $2, $3, now())
     on conflict (user_id) do update
       set location = excluded.location,
           latitude = excluded.latitude,
           longitude = excluded.longitude,
           last_seen = now()`,
    [userId, longitude, latitude],
  );
}

/**
 * Andere Biker im 15-km-Umkreis, die in den letzten 30 Minuten aktiv
 * waren. PostGIS-ST_DWithin über den GiST-Index; der eigene Datensatz
 * wird ausgeschlossen, die Distanz in Metern mitgeliefert.
 */
async function findNearbyBikers(userId, latitude, longitude) {
  const { rows } = await pool.query(
    `select b.user_id,
            b.latitude,
            b.longitude,
            st_distance(b.location, st_setsrid(st_makepoint($2, $3), 4326)::geography)::int as distance_m,
            b.last_seen
     from active_bikers b
     where b.user_id <> $1
       and b.last_seen > now() - interval '30 minutes'
       and st_dwithin(
             b.location,
             st_setsrid(st_makepoint($2, $3), 4326)::geography,
             $4)
     order by b.last_seen desc
     limit $5`,
    [userId, longitude, latitude, NEARBY_RADIUS_METERS, NEARBY_LIMIT],
  );
  return rows.map((r) => ({
    userId: r.user_id,
    lat: r.latitude,
    lng: r.longitude,
    distanceM: r.distance_m,
    lastSeen: r.last_seen,
  }));
}

/**
 * Bereinigungs-Job (Datenschutz): löscht Positionen, die älter als
 * 30 Minuten sind - PHYSISCH. Rückgabe: Anzahl gelöschter Zeilen
 * (für Monitoring/Logging).
 */
async function pruneStaleLocations() {
  const { rowCount } = await pool.query(
    `delete from active_bikers where last_seen < now() - interval '30 minutes'`,
  );
  return rowCount;
}

module.exports = {
  STALE_AFTER_MINUTES,
  NEARBY_RADIUS_METERS,
  NEARBY_LIMIT,
  upsertBikerLocation,
  findNearbyBikers,
  pruneStaleLocations,
};
