const {
  upsertRidePosition,
  findRideMembers,
  removeRidePosition,
  pruneStaleRidePositions,
  RIDE_STALE_AFTER_MINUTES,
} = require('./rideRelayRepository');

/**
 * Ride-Relais (Live-Gruppenfahrt im POI-Dienst).
 *
 * Wer hier sprechen darf: NUR das BFF - jedes Frame muss das Relay-Secret
 * mitbringen (Feld `secret`). End-Clients erreichen diese Events NIE
 * (sie sprechen ausschließlich das BFF); würde das Secret leaken, ist es
 * ein Betreiber-Problem, kein Client-Zugriffsweg. Fail-closed: Ohne
 * konfiguriertes Secret startet das Relais gar nicht erst.
 *
 * Kanäle sind bewusst NICHT der öffentliche Radar-Pfad (bikerRadar.js):
 * - Eigene Tabelle (active_ride_bikers, schema_ride_relay.sql)
 * - Eigene Events (ride_position_update / ride_position_leave)
 * - KEIN Umkreis-Filter: Mitglieder derselben Route sehen einander
 *   unabhängig von der Distanz. Die Autorisierung ("ist Mitglied dieser
 *   Route?") wurde bereits im BFF gegen Supabase-RLS geprüft - das
 *   Relais speichert und verteilt nur noch.
 *
 * Protokoll (BFF -> Dienst):
 *   emit('ride_position', { secret, routeId, userId, lat, lng })
 *   emit('leave_ride',    { secret, routeId, userId })
 *
 * Dienst -> BFF (direkt auf dem BFF-Socket - das BFF ist DER eine
 * Relay-Client, Rooms bräuchte es nur bei mehreren):
 *   emit('ride_position_update', { routeId, members: [{ userId, lat, lng, lastSeen }] })
 *   emit('ride_position_leave',  { routeId, userId })
 */

/** Log-Kappung: ein durchgehender Angreifer soll das Log nicht fluten. */
const RELAY_REJECT_LOG_LIMIT = 10;

function isValidId(value) {
  return typeof value === 'string' && value.length > 0 && value.length <= 64;
}

function isValidLatLng(value) {
  const n = Number(value);
  return Number.isFinite(n) && n >= -90 && n <= 90;
}

function isValidLng(value) {
  const n = Number(value);
  return Number.isFinite(n) && n >= -180 && n <= 180;
}

function createRideRelay(io, options = {}) {
  const secret = options.secret ?? process.env.RIDE_RELAY_SECRET;
  const pruneIntervalMs = options.pruneIntervalMs ?? 5 * 60 * 1000;

  if (!secret) {
    throw new Error(
      'RIDE_RELAY_SECRET fehlt - Ride-Relais deaktiviert. Setze RIDE_RELAY_SECRET im POI-Dienst UND im BFF.',
    );
  }

  const rejectUnauthenticated = (socket, ack) => {
    if (socket.data.rejectLogCount < RELAY_REJECT_LOG_LIMIT) {
      socket.data.rejectLogCount += 1;
      console.warn('[ride-relay] Unautentifizierter Relay-Frame abgelehnt');
    }
    if (typeof ack === 'function') ack({ ok: false, error: 'unauthorized' });
  };

  const initRideRelay = (socket) => {
    socket.data.rejectLogCount = 0;

    socket.on('ride_position', (payload = {}, ack) => {
      if (payload.secret !== secret) {
        rejectUnauthenticated(socket, ack);
        return;
      }
      const { routeId, userId, lat, lng } = payload;
      if (!isValidId(routeId) || !isValidId(userId) || !isValidLatLng(lat) || !isValidLng(lng)) {
        if (typeof ack === 'function') ack({ ok: false, error: 'invalid_payload' });
        return;
      }

      upsertRidePosition(routeId, userId, Number(lat), Number(lng))
        .then(() => findRideMembers(routeId))
        .then((members) => {
          socket.emit('ride_position_update', { routeId, members });
          if (typeof ack === 'function') ack({ ok: true, members });
        })
        .catch((err) => {
          console.error('[ride-relay] ride_position fehlgeschlagen:', err.message);
          if (typeof ack === 'function') ack({ ok: false, error: 'internal_error' });
        });
    });

    socket.on('leave_ride', (payload = {}, ack) => {
      if (payload.secret !== secret) {
        rejectUnauthenticated(socket, ack);
        return;
      }
      const { routeId, userId } = payload;
      if (!isValidId(routeId) || !isValidId(userId)) {
        if (typeof ack === 'function') ack({ ok: false, error: 'invalid_payload' });
        return;
      }

      removeRidePosition(routeId, userId)
        .then(() => {
          socket.emit('ride_position_leave', { routeId, userId });
          if (typeof ack === 'function') ack({ ok: true });
        })
        .catch((err) => {
          console.error('[ride-relay] leave_ride fehlgeschlagen:', err.message);
          if (typeof ack === 'function') ack({ ok: false, error: 'internal_error' });
        });
    });

    // Disconnect des BFF-Sockets: keine Sonderbehandlung - das Relais
    // hält nur transiente Beats, der Prune-Job räumt verlässlich auf.
  };

  io.on('connection', initRideRelay);

  const pruneJob = setInterval(() => {
    pruneStaleRidePositions().catch((err) =>
      console.error('[ride-relay] Bereinigungs-Job fehlgeschlagen:', err.message),
    );
  }, pruneIntervalMs);
  pruneJob.unref();

  return {
    stop() {
      clearInterval(pruneJob);
      io.off('connection', initRideRelay);
    },
  };
}

module.exports = { createRideRelay, RIDE_STALE_AFTER_MINUTES };
