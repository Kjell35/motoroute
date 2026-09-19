import { EventEmitter2 } from '@nestjs/event-emitter';
import { ConfigService } from '@nestjs/config';
import { BikerPoisRealtimeBridge, BikerPoiRealtimeEvent, BATCH_WINDOW_MS } from './biker-pois.realtime';

describe('BikerPoisRealtimeBridge (Socket.IO-Uplink-Koaleszierung)', () => {
  let bridge: BikerPoisRealtimeBridge;
  let emitted: Array<{ event: string; payload: unknown }>;
  let events: EventEmitter2;

  const build = (url: string | undefined) => {
    const config = {
      get: (key: string) => (key === 'BIKER_POI_SERVICE_URL' ? url : undefined),
    } as unknown as ConfigService;
    events = new EventEmitter2();
    emitted = [];
    events.on(BikerPoiRealtimeEvent.BATCH, (payload: unknown) => emitted.push({ event: BikerPoiRealtimeEvent.BATCH, payload }));
    bridge = new BikerPoisRealtimeBridge(config, events);
    bridge.resetForTest();
  };

  beforeEach(() => {
    jest.useFakeTimers();
    build('http://poi-service:3100');
  });

  afterEach(() => {
    bridge.onModuleDestroy();
    jest.useRealTimers();
  });

  it('konfiguriert: verbindungslos lauschend, keine Events', () => {
    // Mit URL initialisiert onModuleInit einen socket.io-Client; hier
    // geht es nur um die Kollektierung - kein Emit ohne Upstream-Events.
    expect(bridge.configured).toBe(true);
    expect(emitted).toHaveLength(0);
  });

  it('nicht konfiguriert (keine URL): warned und emittiert nichts', () => {
    build(undefined);
    expect(bridge.configured).toBe(false);
    bridge.handleUpstream({ id: 'x' }, 'upsert');
    jest.advanceTimersByTime(BATCH_WINDOW_MS + 100);
    expect(emitted).toHaveLength(0);
  });

  it('koalesziert mehrere Upstream-Änderungen in EINEN Batch', () => {
    bridge.handleUpstream({ id: 'p1' }, 'upsert');
    bridge.handleUpstream({ id: 'p2' }, 'upsert');
    bridge.handleUpstream({ id: 'p3' }, 'delete');
    // Innerhalb des Fensters: noch nichts draußen.
    expect(emitted).toHaveLength(0);

    jest.advanceTimersByTime(BATCH_WINDOW_MS + 10);

    expect(emitted).toHaveLength(1);
    const payload = emitted[0].payload as { changes: Array<{ id: string; action: string }> };
    expect(payload.changes).toEqual([
      { id: 'p1', action: 'upsert' },
      { id: 'p2', action: 'upsert' },
      { id: 'p3', action: 'delete' },
    ]);
  });

  it('letzte Aktion pro Id gewinnt (upsert gefolgt von delete)', () => {
    bridge.handleUpstream({ id: 'p1' }, 'upsert');
    bridge.handleUpstream({ id: 'p1' }, 'delete');

    jest.advanceTimersByTime(BATCH_WINDOW_MS + 10);

    expect(emitted).toHaveLength(1);
    const payload = emitted[0].payload as { changes: Array<{ id: string; action: string }> };
    expect(payload.changes).toEqual([{ id: 'p1', action: 'delete' }]);
  });

  it('ignoriert Payloads ohne Id (Datenqualität)', () => {
    bridge.handleUpstream({}, 'upsert');
    bridge.handleUpstream(null, 'delete');
    jest.advanceTimersByTime(BATCH_WINDOW_MS + 10);
    expect(emitted).toHaveLength(0);
  });

  it('kein zweiter Timer nach flush - nächstes Ereignis startet neues Fenster', () => {
    bridge.handleUpstream({ id: 'a' }, 'upsert');
    jest.advanceTimersByTime(BATCH_WINDOW_MS + 10);
    expect(emitted).toHaveLength(1);

    bridge.handleUpstream({ id: 'b' }, 'upsert');
    jest.advanceTimersByTime(BATCH_WINDOW_MS + 10);

    expect(emitted).toHaveLength(2);
    const payload = emitted[1].payload as { changes: Array<{ id: string; action: string }> };
    expect(payload.changes).toEqual([{ id: 'b', action: 'upsert' }]);
  });
});
