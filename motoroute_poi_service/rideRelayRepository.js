const { pool } = require('./db');

/**
 * Ride-Relais-Datenzugriff (Live-Gruppenfahrt im POI-Dienst).
 *
 * Strukturell GETRENNT vom öffentlichen Radar (radarRepository.js):
 * eigene Tabelle (active_ride_bikers), eigener Umkreis-Verzicht (Mitglieder
 * derselben Route sehen einander UNABHÄNGIG von der Distanz - auch über
 * Kontinente hinweg, z. B. Alpentour-Gruppe auf Anreise), eigene Events.
 * Nur das BFF schreibt/liest (Relay-Secret im Handler); ein manipulierter
 * Client erreicht diese Codepfade NIE (Autorisierung lebt im BFF/RLS).
 */

/** Sichtbar im Ride-Kanal: Beats jünger als 30 Minuten. */
const RIDE_STALE_AFTER_MINUTES = 30;
/** Sicherheitsdeckel der Antwortgröße je Route. */
const RIDE_MEMBERS_LIMIT = 500;

/**
 * Speichert/aktualisiert den Beat eines Fahrers je (route_id, user_id).
 */
async function upsertRidePosition(routeId, userId, latitude, longitude) {
  await pool.query(
    `insert into active_ride_bikers (route_id, location, latitude, longitude, last_seen, user_id)
     values ($1, st_setsrid(st_makepoint($3, $2), 4326)::geography, $2, $3, now(), $4)
     on conflict (route_id, user_id) do update
       set location = excluded.location,
           latitude = excluded.latitude,
           longitude = excluded.longitude,
           last_seen = now()`,
    [routeId, latitude, longitude, userId],
  );
}

/**
 * Alle aktiven Fahrer EINER Route - ohne ST_DWithin-Umkreis, dafür mit
 * 30-Minuten-Frische-Filter. Sortiert nach last_seen (frischeste zuerst).
 */
async function findRideMembers(routeId) {
  const { rows } = await pool.query(
    `select user_id, latitude, longitude, last_seen
     from active_ride_bikers
     where route_id = $1
       and last_seen > now() - interval '30 minutes'
     order by last_seen desc
     limit $2`,
    [routeId, RIDE_MEMBERS_LIMIT],
  );
  return rows.map((r) => ({
    userId: r.user_id,
    lat: r.latitude,
    lng: r.longitude,
    lastSeen: r.last_seen,
  }));
}

/**
 * Entfernt EINEN Fahrer von EINER Route (leave/disconnect).
 */
async function removeRidePosition(routeId, userId) {
  await pool.query(
    `delete from active_ride_bikers where route_id = $1 and user_id = $2`,
    [routeId, userId],
  );
}

/**
 * Bereinigungs-Job: löscht Beats älter als 30 Minuten PHYSISCH.
 * Rückgabe: Anzahl gelöschter Zeilen (Monitoring).
 */
async function pruneStaleRidePositions() {
  const { rowCount } = await pool.query(
    `delete from active_ride_bikers where last_seen < now() - interval '30 minutes'`,
  );
  return rowCount;
}

module.exports = {
  RIDE_STALE_AFTER_MINUTES,
  RIDE_MEMBERS_LIMIT,
  upsertRidePosition,
  findRideMembers,
  removeRidePosition,
  pruneStaleRidePositions,
};
