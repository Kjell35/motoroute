const {
  upsertBikerLocation,
  findNearbyBikers,
  pruneStaleLocations,
  STALE_AFTER_MINUTES,
} = require('./radarRepository');

/**
 * Live-Radar über Socket.IO (Feature: "Biker Meetup / Live Radar").
 *
 * Ablauf bei `update_location`:
 *   1. Payload validieren (userId, Koordinaten, ghostMode-Boolean).
 *   2. ghostMode=true  -> NICHTS speichern, keine Radar-Daten (Ghost
 *      erscheint in keinem anderen Radar - Nicht-Speichern ist der
 *      Schutz, kein Flag in der DB).
 *   3. ghostMode=false -> Position per UPSERT speichern (PostGIS
 *      GEOGRAPHY), dann per ST_DWithin alle Biker im 15-km-Umkreis
 *      suchen (Frische-Filter: 30 Minuten).
 *   4. Antworth_batch an den Sender (`location_result`) UND Push an
 *      die nahen Biker (`location_update`), damit deren Radare ohne
 *      eigenes Update automatisch weiterlaufen.
 *   5. Disconnect: eigener Eintrag wird sofort entfernt (physisch),
 *      zusätzlich läuft der 30-Minuten-Bereinigungs-Job als Netz.
 *
 * Datenschutz: Nur der AKTUELLE Punkt je Biker wird gehalten (UPSERT,
 * keine Historie). Die Koordinaten erscheinen NUR in Radar-Antworten
 * des eigenen Servers - es gibt keine REST-Schnittstelle, die Positionen
 * ausleiten würde. Die userId ist ein Platzhalter (SPÄTER: echte
 * Session-Auth am Socket-Handshake, dann stammt die userId aus dem
 * Token statt aus der Payload).
 *
 * Drosselung: Maximal 1 Positionsupdate je 2 s pro Socket - GPS-Streams
 * feuern sonst mit 1 Hz und das Radar ist kein Live-Tracking.
 */

const UPDATE_COOLDOWN_MS = 2000;

function clamp(n, min, max) {
  return Math.min(Math.max(n, min), max);
}

/**
 * Validiert die Payload von update_location. Rückgabe:
 * { ok: true, userId, latitude, longitude, ghostMode } oder
 * { ok: false, reason }.
 */
function validateLocationPayload(payload) {
  if (payload == null || typeof payload !== 'object') {
    return { ok: false, reason: 'Ungültige Payload' };
  }
  const { userId, latitude, longitude, ghostMode } = payload;
  if (typeof userId !== 'string' || userId.length === 0 || userId.length > 64) {
    return { ok: false, reason: 'userId fehlt oder zu lang (max. 64)' };
  }
  const lat = Number(latitude);
  const lng = Number(longitude);
  if (!Number.isFinite(lat) || lat < -90 || lat > 90) {
    return { ok: false, reason: 'latitude ungültig (-90..90)' };
  }
  if (!Number.isFinite(lng) || lng < -180 || lng > 180) {
    return { ok: false, reason: 'longitude ungültig (-180..180)' };
  }
  return {
    ok: true,
    userId,
    latitude: lat,
    longitude: lng,
    // Der Boolean muss wirklich einer sein - ein truthy String "false"
    // würde sonst den Ghost-Mode unsichtbar einschalten.
    ghostMode: ghostMode === true,
  };
}

/**
 * Verdrahtet das Radar auf dem übergebenen Socket.IO-Server und startet
 * den Bereinigungs-Job. Rückgabe: { stop() } für Tests/graceful shutdown.
 */
function initBikerRadar(io, options = {}) {
  const pruneIntervalMs = options.pruneIntervalMs ?? 5 * 60 * 1000;

  const initRadar = (socket) => {
    socket.data.lastUpdateAt = 0;

    socket.on('update_location', (payload, ack) => {
      void handleUpdateLocation(io, socket, payload, ack).catch((err) => {
        console.error('[radar] update_location fehlgeschlagen:', err.message);
        if (typeof ack === 'function') ack({ ok: false, error: 'internal_error' });
      });
    });

    // Disconnect: eigener Eintrag SOFORT raus (physisch) - wer die App
    // schließt, ist nach dem Verbindungsabbau nicht mehr im Radar. Der
    // 30-Minuten-Job ist nur das Sicherheitsnetz für gekillte Sockets,
    // deren disconnect-Event nie ankam (Funkloch, Akku leer).
    socket.on('disconnect', () => {
      const userId = socket.data.radarUserId;
      if (!userId) return;
      removeRadarEntry(userId).catch((err) =>
        console.error('[radar] disconnect-cleanup fehlgeschlagen:', err.message),
      );
    });
  };

  async function handleUpdateLocation(io, socket, payload, ack) {
    const valid = validateLocationPayload(payload);
    if (!valid.ok) {
      if (typeof ack === 'function') ack({ ok: false, error: valid.reason });
      return;
    }
    const { userId, latitude, longitude, ghostMode } = valid;
    socket.data.radarUserId = userId;

    // Cooldown: GPS-Stürme drosseln (Ausnahme: erster Aufruf je Socket).
    const now = Date.now();
    if (socket.data.lastUpdateAt && now - socket.data.lastUpdateAt < UPDATE_COOLDOWN_MS) {
      if (typeof ack === 'function') ack({ ok: false, error: 'rate_limited' });
      return;
    }
    socket.data.lastUpdateAt = now;

    // GHOST MODE: Nichts speichern, nichts ausspielen. Der Sender bekommt
    // nur die Bestätigung "du bist unsichtbar".
    if (ghostMode) {
      if (typeof ack === 'function') ack({ ok: true, ghostMode: true, nearbyBikers: [] });
      return;
    }

    await upsertBikerLocation(userId, latitude, longitude);
    const nearbyBikers = await findNearbyBikers(userId, latitude, longitude);

    if (typeof ack === 'function') {
      ack({ ok: true, ghostMode: false, nearbyBikers });
    }

    // Push an die nahen Biker: deren Radar aktualisiert den frischen
    // Punkt automatisch (Filter: nur Sockets, die SELBST im Radar sind).
    if (io) {
      for (const [, target] of io.of('/').sockets) {
        if (target.id === socket.id) continue;
        if (target.data.radarUserId && nearbyBikers.some((b) => b.userId === target.data.radarUserId)) {
          target.emit('location_update', {
            userId,
            lat: latitude,
            lng: longitude,
            lastSeen: new Date().toISOString(),
          });
        }
      }
    }
  }

  async function removeRadarEntry(userId) {
    const { pool } = require('./db');
    await pool.query(`delete from active_bikers where user_id = $1`, [userId]);
  }

  // Bereinigungs-Job: löscht Positionen älter als 30 Minuten (Datenschutz).
  const pruneJob = setInterval(async () => {
    try {
      const deleted = await pruneStaleLocations();
      if (deleted > 0) console.log(`[radar] ${deleted} veraltete Position(en) gelöscht (> ${STALE_AFTER_MINUTES} Min.)`);
    } catch (err) {
      console.error('[radar] Bereinigungs-Job fehlgeschlagen:', err.message);
    }
  }, pruneIntervalMs);
  pruneJob.unref();

  io.on('connection', initRadar);

  return {
    stop() {
      clearInterval(pruneJob);
      io.off('connection', initRadar);
    },
    /**
     * Test-Hook: Handler ohne echten Socket aufrufen (socket-Shape
     * minimal nachgebildet, Cooldown aus - Validierung/Ghost/DB-
     * Verhalten bleiben exakt dieselben Codepfade).
     */
    handleUpdateLocation: (payload, ack) =>
      handleUpdateLocation(
        io,
        { id: 'test-socket', data: { lastUpdateAt: 0, radarUserId: null } },
        payload,
        ack,
      ),
  };
}

module.exports = {
  initBikerRadar,
  validateLocationPayload,
  UPDATE_COOLDOWN_MS,
};
