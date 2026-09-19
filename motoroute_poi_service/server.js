require('dotenv').config();
const express = require('express');
const http = require('http');
const { Server } = require('socket.io');
const { Client } = require('pg');

const { pool } = require('./db');
const { getDelta } = require('./poiRepository');
const { scheduleDailyScan } = require('./dailyPoiScan');
const { initBikerRadar } = require('./bikerRadar');
const { createRideRelay } = require('./rideRelay');

const app = express();
const server = http.createServer(app);
const io = new Server(server, { cors: { origin: '*' } });

/**
 * GET /api/pois/sync
 * Delta-Sync-Endpunkt für die Flutter-App.
 *
 * Query-Parameter:
 *  - since       ISO-Timestamp der letzten Synchronisierung des Clients
 *                (beim allerersten Aufruf z.B. "1970-01-01T00:00:00Z")
 *  - lat, lon    optional: Umkreis-Filter, Kartenmittelpunkt der App
 *  - radiusKm    optional: Radius in km (Default: kein Radius-Filter)
 *  - categories  optional: kommagetrennte Liste unserer 8 Kategorien
 *
 * Antwort:
 *  {
 *    serverTime: "2026-09-18T10:00:00.000Z",  // vom Client als neues `since` zu speichern
 *    upserted: [ { id, name, category, lat, lon, address, bikerScore, amenities, updatedAt }, ... ],
 *    deletedIds: [ "uuid", ... ]               // seit `since` deaktivierte/entfernte POIs
 *  }
 */
app.get('/api/pois/sync', async (req, res) => {
  // Radar-Positionen sind TRANSIENT (Datenschutz): Es gibt bewusst KEINE
  // GET-Route, die sie ausleitet - sie fließen nur in Socket.IO-Radar-
  // Antworten ein. Nur Sync-Timestamps dürfen gecacht werden.
  try {
    const { since, lat, lon, radiusKm, categories } = req.query;
    if (!since) return res.status(400).json({ error: '`since` ist erforderlich (ISO-Timestamp)' });

    const { upserted, deletedIds, hasMore, cursor } = await getDelta({
      since,
      lat: lat != null ? Number(lat) : null,
      lon: lon != null ? Number(lon) : null,
      radiusKm: radiusKm != null ? Number(radiusKm) : null,
      categories: categories ? categories.split(',') : null,
    });

    res.json({
      serverTime: new Date().toISOString(),
      // cursor: wenn gesetzt, ist dies das SICHERE nächste `since` (an
      // updated_at gekoppelt, nicht an der Serverzeit). Falls null, gilt
      // serverTime.
      serverTime: cursor || new Date().toISOString(),
      hasMore,
      upserted: upserted.map((r) => ({
        id: r.id,
        name: r.name,
        category: r.category,
        lat: r.lat,
        lon: r.lon,
        address: r.address,
        bikerScore: r.biker_score,
        amenities: r.amenities,
        updatedAt: r.updated_at,
      })),
      deletedIds,
    });
  } catch (err) {
    console.error('[api] /api/pois/sync Fehler:', err);
    res.status(500).json({ error: 'internal_error' });
  }
});

// --- Realtime-Push: Postgres LISTEN/NOTIFY -> Socket.IO -----------------
// Entkoppelt den Scan-Prozess (dailyPoiScan.js) vom API-Prozess: sobald
// der DB-Trigger `pois_notify_change` feuert, erfährt JEDER laufende
// API-Server-Prozess (auch bei mehreren Instanzen) sofort davon.
async function startRealtimeBridge() {
  const listener = new Client({ connectionString: process.env.DATABASE_URL });
  await listener.connect();
  await listener.query('LISTEN poi_changes');

  listener.on('notification', async (msg) => {
    const payload = JSON.parse(msg.payload);
    const { rows } = await pool.query(
      `SELECT id, name, category, ST_Y(geog::geometry) AS lat, ST_X(geog::geometry) AS lon,
              address, biker_score, amenities, is_active, updated_at
       FROM pois WHERE id = $1`,
      [payload.id]
    );
    if (rows.length === 0) return;
    const poi = rows[0];

    // Clients können Räumen pro Kategorie und/oder Kachel/Region beitreten
    // (io.on('connection', socket => socket.join(...))), hier vereinfacht
    // als Broadcast an alle sowie in einen kategorie-spezifischen Raum.
    const event = poi.is_active ? 'poi:upsert' : 'poi:delete';
    io.to(`category:${poi.category}`).emit(event, poi);
    io.emit(event, poi);
  });

  listener.on('error', (err) => console.error('[realtime] LISTEN-Verbindung verloren:', err));
  console.log('[realtime] LISTEN poi_changes aktiv');
}

io.on('connection', (socket) => {
  socket.on('subscribe', (categories = []) => {
    categories.forEach((c) => socket.join(`category:${c}`));
  });
});

// --- Live-Radar (Biker Meetup): update_location über Socket.IO ---------
// Eigenes Modul (bikerRadar.js): UPSERT der Position (ghostMode=false),
// ST_DWithin-15-km-Umkreis, Push in den Raum aller Radar-Clients,
// Disconnect-Cleanup und 30-Minuten-Bereinigungs-Job (Datenschutz).
const radar = initBikerRadar(io);

// --- Ride-Relais (Live-Gruppenfahrt) ------------------------------------
// Separate Struktur (Tabelle/Events/Secret): Nur das BFF spricht das
// Relais an (RIDE_RELAY_SECRET), Mitgliedschaft wurde dort gegen RLS
// geprüft. Mitglieder derselben Route sehen einander OHNE Umkreis-Limit.
// Fail-closed: fehlt das Secret, wirft createRideRelay und der Server
// startet nicht mit halb-offenem Relais.
const rideRelay = createRideRelay(io);

const PORT = process.env.PORT || 3000;
server.listen(PORT, () => {
  console.log(`[api] Server läuft auf Port ${PORT}`);
  scheduleDailyScan(process.env.SCAN_CRON || '0 3 * * *');
  startRealtimeBridge().catch((err) => console.error('[realtime] Start fehlgeschlagen:', err));
});

// Graceful shutdown: Radar-Job stoppen, Socket-Server schließen, DB-Pool
// sauber beenden (sonst hängt der Prozess an offenen Clients).
async function shutdown(signal) {
  console.log(`[api] ${signal} empfangen - fahre herunter`);
  radar.stop();
  rideRelay.stop();
  io.close();
  server.close();
  try {
    await pool.end();
  } catch (_) {
    // Pool war evtl. schon zu - weitermachen.
  }
  process.exit(0);
}
process.on('SIGINT', () => shutdown('SIGINT'));
process.on('SIGTERM', () => shutdown('SIGTERM'));
