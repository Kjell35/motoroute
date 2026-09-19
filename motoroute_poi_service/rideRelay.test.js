const { createRideRelay, RIDE_STALE_AFTER_MINUTES } = require('./rideRelay');

jest.mock('./rideRelayRepository', () => ({
  upsertRidePosition: jest.fn().mockResolvedValue(undefined),
  findRideMembers: jest.fn().mockResolvedValue([
    { userId: 'b1', lat: 48.1, lng: 11.5, lastSeen: '2026-09-18T10:00:00Z' },
    { userId: 'b2', lat: 46.5, lng: 9.0, lastSeen: '2026-09-18T09:59:00Z' },
  ]),
  removeRidePosition: jest.fn().mockResolvedValue(undefined),
  pruneStaleRidePositions: jest.fn().mockResolvedValue(0),
  RIDE_STALE_AFTER_MINUTES: 30,
  RIDE_MEMBERS_LIMIT: 500,
}));

jest.mock('./db', () => ({
  pool: { query: jest.fn().mockResolvedValue({ rowCount: 0, rows: [] }) },
}));

const SECRET = 'test-relay-secret';

function fakeIo() {
  return {
    on: jest.fn(),
    off: jest.fn(),
  };
}

function fakeSocket() {
  return { id: 'bff-socket', data: {}, on: jest.fn(), emit: jest.fn() };
}

/** Verbindet einen Fake-BFF-Socket und liefert die registrierten Handler. */
function connectBff(io, socket) {
  io.on.mock.calls.find(([evt]) => evt === 'connection')[1](socket);
  const handlers = {};
  for (const [evt, fn] of socket.on.mock.calls) handlers[evt] = fn;
  return handlers;
}

const flush = () => new Promise((r) => setImmediate(r));

beforeEach(() => jest.clearAllMocks());

describe('createRideRelay (Live-Gruppenfahrt-Relais)', () => {
  test('fehlendes Secret: Start WIRD VERWEIGERT (fail-closed)', () => {
    expect(() => createRideRelay(fakeIo(), { secret: undefined })).toThrow(/RIDE_RELAY_SECRET/);
  });

  test('ride_position mit korrektem Secret: Upsert + direkter Push an das BFF', async () => {
    const io = fakeIo();
    const relay = createRideRelay(io, { secret: SECRET });
    const socket = fakeSocket();
    const h = connectBff(io, socket);
    const ack = jest.fn();

    h['ride_position']({ secret: SECRET, routeId: 'r1', userId: 'b1', lat: 48.1, lng: 11.5 }, ack);
    await flush();

    expect(require('./rideRelayRepository').upsertRidePosition).toHaveBeenCalledWith('r1', 'b1', 48.1, 11.5);
    expect(ack).toHaveBeenCalledWith({ ok: true, members: expect.any(Array) });
    expect(socket.emit).toHaveBeenCalledWith(
      'ride_position_update',
      expect.objectContaining({ routeId: 'r1', members: expect.any(Array) }),
    );
    relay.stop();
  });

  test('FALSCHES Secret: weder DB noch Push, ack unauthorized, Log gedeckelt', async () => {
    const io = fakeIo();
    const relay = createRideRelay(io, { secret: SECRET });
    const socket = fakeSocket();
    const h = connectBff(io, socket);
    const repo = require('./rideRelayRepository');
    const ack = jest.fn();

    for (let i = 0; i < 15; i++) {
      h['ride_position']({ secret: 'wrong', routeId: 'r1', userId: 'x', lat: 1, lng: 2 }, ack);
    }
    await flush();

    expect(repo.upsertRidePosition).not.toHaveBeenCalled();
    expect(ack).toHaveBeenCalledTimes(15);
    expect(ack.mock.calls.every(([r]) => r.error === 'unauthorized')).toBe(true);
    relay.stop();
  });

  test('ungültige Koordinaten -> invalid_payload, kein Upsert', async () => {
    const io = fakeIo();
    const relay = createRideRelay(io, { secret: SECRET });
    const socket = fakeSocket();
    const h = connectBff(io, socket);
    const repo = require('./rideRelayRepository');
    const ack = jest.fn();

    h['ride_position']({ secret: SECRET, routeId: 'r1', userId: 'b1', lat: 200, lng: 11 }, ack);
    await flush();

    expect(ack).toHaveBeenCalledWith({ ok: false, error: 'invalid_payload' });
    expect(repo.upsertRidePosition).not.toHaveBeenCalled();
    relay.stop();
  });

  test('leave_ride: Entfernung + Push an das BFF', async () => {
    const io = fakeIo();
    const relay = createRideRelay(io, { secret: SECRET });
    const socket = fakeSocket();
    const h = connectBff(io, socket);
    const repo = require('./rideRelayRepository');
    const ack = jest.fn();

    h['leave_ride']({ secret: SECRET, routeId: 'r1', userId: 'b2' }, ack);
    await flush();

    expect(repo.removeRidePosition).toHaveBeenCalledWith('r1', 'b2');
    expect(socket.emit).toHaveBeenCalledWith('ride_position_leave', { routeId: 'r1', userId: 'b2' });
    expect(ack).toHaveBeenCalledWith({ ok: true });
    relay.stop();
  });

  test('Bereinigungs-Job läuft (Prune veralteter Beats)', async () => {
    jest.useFakeTimers({ doNotFake: ['setImmediate'] });
    const repo = require('./rideRelayRepository');
    repo.pruneStaleRidePositions.mockResolvedValueOnce(2);
    const io = fakeIo();
    const relay = createRideRelay(io, { secret: SECRET, pruneIntervalMs: 1000 });

    await jest.advanceTimersByTimeAsync(1100);
    expect(repo.pruneStaleRidePositions).toHaveBeenCalled();
    relay.stop();
    jest.useRealTimers();
  });

  test('RIDE_STALE_AFTER_MINUTES bleibt der Datenschutz-Vertrag (30)', () => {
    expect(RIDE_STALE_AFTER_MINUTES).toBe(30);
  });
});
