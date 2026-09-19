const {
  initBikerRadar,
  validateLocationPayload,
  UPDATE_COOLDOWN_MS,
} = require('./bikerRadar');
const radarRepo = require('./radarRepository');

/**
 * radarRepository wird auf Modulebene gemockt - getestet wird der
 * Handler/Job-Verdrahtung (Verhalten), nicht PostGIS selbst. Die SQL-
 * Verträge sind in radarRepository.js dokumentiert; ein Integrationstest
 * gegen echte Postgres+PostGIS ist der Wichtigster nächster Schritt
 * (siehe Root-README).
 */
jest.mock('./radarRepository', () => ({
  upsertBikerLocation: jest.fn(),
  findNearbyBikers: jest.fn().mockResolvedValue([]),
  pruneStaleLocations: jest.fn().mockResolvedValue(0),
  STALE_AFTER_MINUTES: 30,
  NEARBY_RADIUS_METERS: 15000,
  NEARBY_LIMIT: 200,
}));

jest.mock('./db', () => ({
  pool: { query: jest.fn().mockResolvedValue({ rowCount: 0, rows: [] }) },
}));

function fakeIo() {
  const sockets = new Map();
  return {
    of: () => ({ sockets }),
    on: jest.fn(),
    off: jest.fn(),
    sockets,
  };
}

function fakeSocket() {
  return { id: 's-1', data: {}, on: jest.fn(), emit: jest.fn() };
}

beforeEach(() => {
  jest.clearAllMocks();
});

describe('validateLocationPayload (update_location-Vertrag)', () => {
  test('valide Payload wird akzeptiert und normalisiert', () => {
    const v = validateLocationPayload({ userId: 'u1', latitude: 48.1, longitude: 11.5, ghostMode: false });
    expect(v).toEqual({ ok: true, userId: 'u1', latitude: 48.1, longitude: 11.5, ghostMode: false });
  });

  test('ghostMode als String "false" bleibt FALSE (Boolean-Erzwingung)', () => {
    const v = validateLocationPayload({ userId: 'u1', latitude: 1, longitude: 1, ghostMode: 'false' });
    expect(v.ok).toBe(true);
    expect(v.ghostMode).toBe(false);
  });

  test('userId fehlt/zu lang/kein String -> abgelehnt', () => {
    expect(validateLocationPayload({ latitude: 1, longitude: 1 }).ok).toBe(false);
    expect(validateLocationPayload({ userId: 'x'.repeat(65), latitude: 1, longitude: 1 }).ok).toBe(false);
    expect(validateLocationPayload({ userId: 42, latitude: 1, longitude: 1 }).ok).toBe(false);
  });

  test('Koordinaten außerhalb des Bereichs / nicht-numerisch -> abgelehnt', () => {
    expect(validateLocationPayload({ userId: 'u', latitude: 91, longitude: 0 }).ok).toBe(false);
    expect(validateLocationPayload({ userId: 'u', latitude: 0, longitude: -181 }).ok).toBe(false);
    expect(validateLocationPayload({ userId: 'u', latitude: 'n/a', longitude: 0 }).ok).toBe(false);
    expect(validateLocationPayload(null).ok).toBe(false);
  });
});

describe('update_location-Handler (initBikerRadar)', () => {
  test('Ghost-Mode: NICHTS wird gespeichert, leere nearby-Liste', async () => {
    const radar = initBikerRadar(fakeIo());
    const ack = jest.fn();

    await radar.handleUpdateLocation(
      { userId: 'ghost', latitude: 48.1, longitude: 11.5, ghostMode: true },
      ack,
    );

    expect(radarRepo.upsertBikerLocation).not.toHaveBeenCalled();
    expect(radarRepo.findNearbyBikers).not.toHaveBeenCalled();
    expect(ack).toHaveBeenCalledWith({ ok: true, ghostMode: true, nearbyBikers: [] });
    radar.stop();
  });

  test('ghostMode=false: UPSERT + ST_DWithin-Abfrage, Ack mit nearbyBikers', async () => {
    radarRepo.findNearbyBikers.mockResolvedValueOnce([
      { userId: 'b2', lat: 48.2, lng: 11.6, distanceM: 3500, lastSeen: '2026-09-18T10:00:00Z' },
    ]);
    const radar = initBikerRadar(fakeIo());
    const ack = jest.fn();

    await radar.handleUpdateLocation(
      { userId: 'b1', latitude: 48.1, longitude: 11.5, ghostMode: false },
      ack,
    );

    expect(radarRepo.upsertBikerLocation).toHaveBeenCalledWith('b1', 48.1, 11.5);
    expect(radarRepo.findNearbyBikers).toHaveBeenCalledWith('b1', 48.1, 11.5);
    expect(ack).toHaveBeenCalledWith({
      ok: true,
      ghostMode: false,
      nearbyBikers: [{ userId: 'b2', lat: 48.2, lng: 11.6, distanceM: 3500, lastSeen: '2026-09-18T10:00:00Z' }],
    });
    radar.stop();
  });

  test('ungültige Koordinaten: weder UPSERT noch Abfrage', async () => {
    const radar = initBikerRadar(fakeIo());
    const ack = jest.fn();

    await radar.handleUpdateLocation(
      { userId: 'b1', latitude: 999, longitude: 11.5, ghostMode: false },
      ack,
    );

    expect(radarRepo.upsertBikerLocation).not.toHaveBeenCalled();
    expect(ack).toHaveBeenCalledWith({ ok: false, error: expect.any(String) });
    radar.stop();
  });

  test('Cooldown: zweiter Aufruf innerhalb 2 s -> rate_limited', async () => {
    // setImmediate darf NICHT gefaked werden (Handler-Flush nutzt es).
    jest.useFakeTimers({ doNotFake: ['setImmediate'] });
    const io = fakeIo();
    const radar = initBikerRadar(io);
    const socket = fakeSocket();
    io.on.mock.calls.find(([evt]) => evt === 'connection')[1](socket);

    const registered = socket.on.mock.calls.find(([evt]) => evt === 'update_location')[1];
    const flush = () => new Promise((r) => setImmediate(r));

    const ack1 = jest.fn();
    registered({ userId: 'b1', latitude: 48.1, longitude: 11.5, ghostMode: false }, ack1);
    await flush();
    expect(ack1).toHaveBeenCalledWith(expect.objectContaining({ ok: true }));

    // Zweiter Aufruf unmittelbar darauf (gleicher Socket): gedrosselt.
    const ack2 = jest.fn();
    registered({ userId: 'b1', latitude: 48.2, longitude: 11.6, ghostMode: false }, ack2);
    await flush();
    expect(ack2).toHaveBeenCalledWith({ ok: false, error: 'rate_limited' });

    // Nach Ablauf des Cooldown-Fensters geht wieder etwas.
    jest.setSystemTime(Date.now() + UPDATE_COOLDOWN_MS + 1000);
    const ack3 = jest.fn();
    registered({ userId: 'b1', latitude: 48.3, longitude: 11.7, ghostMode: false }, ack3);
    await flush();
    expect(ack3).toHaveBeenCalledWith(expect.objectContaining({ ok: true }));

    radar.stop();
    jest.useRealTimers();
  });

  test('Bereinigungs-Job löscht veraltete Positionen', async () => {
    jest.useFakeTimers();
    radarRepo.pruneStaleLocations.mockResolvedValueOnce(3);
    const radar = initBikerRadar(fakeIo(), { pruneIntervalMs: 1000 });

    await jest.advanceTimersByTimeAsync(1100);
    expect(radarRepo.pruneStaleLocations).toHaveBeenCalled();
    radar.stop();
    jest.useRealTimers();
  });
});

describe('Disconnect-Cleanup', () => {
  test('connection-Handler registriert update_location + disconnect', () => {
    const io = fakeIo();
    const radar = initBikerRadar(io);
    const socket = fakeSocket();

    expect(io.on).toHaveBeenCalledWith('connection', expect.any(Function));
    // Verbindung simulieren:
    io.on.mock.calls.find(([evt]) => evt === 'connection')[1](socket);

    const events = socket.on.mock.calls.map(([evt]) => evt);
    expect(events).toContain('update_location');
    expect(events).toContain('disconnect');
    radar.stop();
  });
});
