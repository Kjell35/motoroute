import { BadRequestException, ServiceUnavailableException } from '@nestjs/common';
import {
  PAIRING_MAX_SECONDS,
  PAIRING_TTL_SECONDS,
  PairingService,
  nextExpiry,
  normalizeToken,
} from './pairing.service';

type Row = { token: string; points: unknown; expires_at: string; created_at?: string };

/**
 * Minimaler Supabase-Ersatz: bildet nur die Aufrufe nach, die der Service
 * macht (insert, select/eq/gt/maybeSingle, update/eq/gt/select/maybeSingle,
 * delete/lt) - inklusive Filter auf expires_at, damit der Ablauf wirklich
 * geprüft wird und nicht nur die Existenz eines WHERE-Blocks.
 */
class FakeQuery {
  private mode: 'select' | 'insert' | 'update' | 'delete' = 'select';
  private payload: Record<string, unknown> | null = null;
  private filters: ((row: Row) => boolean)[] = [];

  constructor(private readonly db: FakeDb) {}

  select(): this {
    return this;
  }

  insert(payload: Record<string, unknown>): this {
    this.mode = 'insert';
    this.payload = payload;
    return this;
  }

  update(payload: Record<string, unknown>): this {
    this.mode = 'update';
    this.payload = payload;
    return this;
  }

  delete(): this {
    this.mode = 'delete';
    return this;
  }

  eq(column: keyof Row, value: unknown): this {
    this.filters.push((row) => row[column] === value);
    return this;
  }

  gt(column: keyof Row, value: string): this {
    this.filters.push((row) => String(row[column]) > value);
    return this;
  }

  lt(column: keyof Row, value: string): this {
    this.filters.push((row) => String(row[column]) < value);
    return this;
  }

  async maybeSingle(): Promise<{ data: Row | null; error: unknown }> {
    if (this.db.error) return { data: null, error: this.db.error };
    const match = this.match();
    if (match.length && this.mode === 'update') Object.assign(match[0], this.payload);
    return { data: match[0] ? { ...match[0] } : null, error: null };
  }

  /** insert/delete werden im Service direkt awaited (ohne maybeSingle). */
  then(resolve: (value: unknown) => void, reject?: (error: unknown) => void): unknown {
    return Promise.resolve(this.run()).then(resolve, reject);
  }

  private match(): Row[] {
    return this.db.rows.filter((row) => this.filters.every((filter) => filter(row)));
  }

  private run(): { error: unknown } {
    if (this.db.error) return { error: this.db.error };
    if (this.mode === 'insert') {
      this.db.rows.push(this.payload as Row);
      return { error: null };
    }
    if (this.mode === 'delete') {
      this.db.rows = this.db.rows.filter((row) => !this.filters.every((filter) => filter(row)));
      return { error: null };
    }
    this.match().forEach((row) => Object.assign(row, this.payload));
    return { error: null };
  }
}

class FakeDb {
  rows: Row[] = [];
  error: { code: string; message: string } | null = null;
  from(_table: string): FakeQuery {
    return new FakeQuery(this);
  }
}

describe('PairingService', () => {
  const origin = 'https://api.example.org';

  function build(): { db: FakeDb; service: PairingService } {
    const db = new FakeDb();
    return { db, service: new PairingService(db as never) };
  }

  describe('start()', () => {
    it('liefert ein 6-stelliges Token aus dem verwechslungssicheren Alphabet', async () => {
      const { service } = build();
      const start = await service.start(origin);

      expect(start.token).toMatch(/^[A-HJ-NP-Z2-9]{6}$/);
      expect(start.token).toHaveLength(6);
      expect(start.plan_url).toBe(`${origin}/plan/${start.token}`);
      expect(start.plan_urls).toEqual([start.plan_url]);
      expect(start.expires_in_seconds).toBe(PAIRING_TTL_SECONDS);
    });

    it('legt eine Zeile mit leerem Plan und Ablauf in zwei Stunden an', async () => {
      const { db, service } = build();
      const before = Date.now();

      const start = await service.start(origin);

      expect(db.rows).toHaveLength(1);
      const [row] = db.rows;
      expect(row.token).toBe(start.token);
      expect(row.points).toEqual([]);
      const ttlSeconds = (Date.parse(row.expires_at) - before) / 1000;
      expect(ttlSeconds).toBeGreaterThan(PAIRING_TTL_SECONDS - 5);
      expect(ttlSeconds).toBeLessThan(PAIRING_TTL_SECONDS + 5);
    });

    it('erzeugt unterschiedliche Tokens', async () => {
      const { service } = build();
      const tokens = new Set<string>();
      for (let index = 0; index < 20; index += 1) {
        tokens.add((await service.start(origin)).token);
      }
      expect(tokens.size).toBe(20);
    });

    it('meldet 503, wenn die Ablage nicht erreichbar ist', async () => {
      const { db, service } = build();
      db.error = { code: 'XX000', message: 'boom' };

      await expect(service.start(origin)).rejects.toBeInstanceOf(
        ServiceUnavailableException,
      );
    });

    it('meldet 503 ohne konfigurierte Datenbank', async () => {
      const service = new PairingService(null);
      await expect(service.start(origin)).rejects.toBeInstanceOf(
        ServiceUnavailableException,
      );
    });
  });

  describe('getPoints() / Ablauf', () => {
    it('unbekanntes Token -> null', async () => {
      const { service } = build();
      expect(await service.getPoints('ZZZZZZ')).toBeNull();
    });

    it('abgelaufener Plan -> null, gültiger Plan -> Punkte', async () => {
      const { db, service } = build();
      db.rows.push({
        token: 'ABC234',
        points: [{ label: 'Alt', detail: null, lat: 47, lon: 11 }],
        expires_at: new Date(Date.now() - 1000).toISOString(),
      });
      db.rows.push({
        token: 'XYZ789',
        points: [{ label: 'Neu', detail: 'Hinweis', lat: 48, lon: 12 }],
        expires_at: new Date(Date.now() + 60_000).toISOString(),
      });

      expect(await service.getPoints('ABC234')).toBeNull();
      expect(await service.getPoints('xyz789')).toEqual([
        { label: 'Neu', detail: 'Hinweis', lat: 48, lon: 12 },
      ]);
    });

    it('speichert nichts in abgelaufene Pläne', async () => {
      const { db, service } = build();
      db.rows.push({
        token: 'ABC234',
        points: [],
        expires_at: new Date(Date.now() - 1000).toISOString(),
      });

      const result = await service.savePoints('ABC234', [
        { lat: 47, lon: 11, label: 'Zu spät' },
      ]);

      expect(result).toBeNull();
      expect(db.rows[0].points).toEqual([]);
    });

    it('meldet 503 bei Lesefehlern', async () => {
      const { db, service } = build();
      db.rows.push({
        token: 'ABC234',
        points: [],
        expires_at: new Date(Date.now() + 60_000).toISOString(),
      });
      db.error = { code: 'XX000', message: 'boom' };

      await expect(service.getPoints('ABC234')).rejects.toBeInstanceOf(
        ServiceUnavailableException,
      );
    });
  });

  describe('savePoints() / Punkte-Validierung', () => {
    function withPlan(): { db: FakeDb; service: PairingService } {
      const built = build();
      built.db.rows.push({
        token: 'ABC234',
        points: [],
        created_at: new Date(Date.now() - 60_000).toISOString(),
        expires_at: new Date(Date.now() + 60_000).toISOString(),
      });
      return built;
    }

    it('übernimmt gültige Punkte inklusive Detail', async () => {
      const { db, service } = withPlan();

      const saved = await service.savePoints('ABC234', [
        { lat: 47.4211, lon: 10.9848, label: 'Eibsee', detail: 'Parkplatz' },
        { lat: 47.49, lon: 11.095 },
      ]);

      expect(saved).toHaveLength(2);
      expect(saved?.[0]).toEqual({
        label: 'Eibsee',
        detail: 'Parkplatz',
        lat: 47.4211,
        lon: 10.9848,
      });
      // Ohne Label greift ein neutraler Name.
      expect(saved?.[1].label).toBe('Wegpunkt 2');
      expect(saved?.[1].detail).toBeNull();
      expect((db.rows[0].points as unknown[]).length).toBe(2);
    });

    it('weist Nicht-Listen mit 400 ab', async () => {
      const { service } = withPlan();
      await expect(service.savePoints('ABC234', 'keine Liste')).rejects.toBeInstanceOf(
        BadRequestException,
      );
      await expect(service.savePoints('ABC234', null)).rejects.toBeInstanceOf(
        BadRequestException,
      );
    });

    it('weist mehr als 50 Punkte mit 400 ab', async () => {
      const { service } = withPlan();
      const tooMany = Array.from({ length: 51 }, (_, index) => ({
        lat: 47 + index * 0.001,
        lon: 11,
        label: `P${index}`,
      }));
      await expect(service.savePoints('ABC234', tooMany)).rejects.toThrow(
        /höchstens 50 Punkte/,
      );
    });

    it('weist ungültige Koordinaten mit 400 ab', async () => {
      const { service } = withPlan();
      await expect(
        service.savePoints('ABC234', [{ lat: 91, lon: 11 }]),
      ).rejects.toThrow(/lat muss zwischen -90 und 90/);
      await expect(
        service.savePoints('ABC234', [{ lat: 47, lon: -181 }]),
      ).rejects.toThrow(/lon muss zwischen -180 und 180/);
      await expect(
        service.savePoints('ABC234', [{ lat: 'abc', lon: 11 }]),
      ).rejects.toThrow(/lat muss zwischen -90 und 90/);
    });

    it('weist Einträge ab, die keine Objekte sind', async () => {
      const { service } = withPlan();
      await expect(service.savePoints('ABC234', [42])).rejects.toThrow(
        /Punkt 1 ist ungültig/,
      );
    });

    it('kürzt überlange Labels und Details', async () => {
      const { service } = withPlan();
      const saved = await service.savePoints('ABC234', [
        { lat: 47, lon: 11, label: 'L'.repeat(200), detail: 'D'.repeat(500) },
      ]);
      expect(saved?.[0].label).toHaveLength(120);
      expect(saved?.[0].detail).toHaveLength(200);
    });

    it('leere Detail-Texte werden zu null', async () => {
      const { service } = withPlan();
      const saved = await service.savePoints('ABC234', [
        { lat: 47, lon: 11, label: 'Punkt', detail: '   ' },
      ]);
      expect(saved?.[0].detail).toBeNull();
    });
  });

  describe('savePoints() / Gültigkeit verlängern', () => {
    it('schiebt den Ablauf um das volle Zeitfenster nach vorn', async () => {
      const { db, service } = build();
      db.rows.push({
        token: 'ABC234',
        points: [],
        created_at: new Date(Date.now() - 30 * 60_000).toISOString(),
        expires_at: new Date(Date.now() + 60_000).toISOString(),
      });

      await service.savePoints('ABC234', [{ lat: 47, lon: 11, label: 'Weiter' }]);

      const restSekunden = (Date.parse(db.rows[0].expires_at) - Date.now()) / 1000;
      // Aus einer Minute Restzeit werden wieder zwei Stunden.
      expect(restSekunden).toBeGreaterThan(PAIRING_TTL_SECONDS - 5);
      expect(restSekunden).toBeLessThan(PAIRING_TTL_SECONDS + 5);
    });

    it('verlängert höchstens acht Stunden ab Anlage', async () => {
      const { db, service } = build();
      const created = Date.now() - 7.9 * 60 * 60_000;
      db.rows.push({
        token: 'ABC234',
        points: [],
        created_at: new Date(created).toISOString(),
        expires_at: new Date(Date.now() + 6 * 60_000).toISOString(),
      });

      await service.savePoints('ABC234', [{ lat: 47, lon: 11, label: 'Spät' }]);

      const restSekunden = (Date.parse(db.rows[0].expires_at) - Date.now()) / 1000;
      // 7,9 Stunden sind vorbei: nur noch bis zur Acht-Stunden-Grenze.
      expect(restSekunden).toBeLessThan(8 * 60);
      expect(restSekunden).toBeGreaterThan(5 * 60);
    });
  });

  describe('nextExpiry()', () => {
    const now = Date.parse('2026-01-01T12:00:00.000Z');

    it('verlängert bis zum vollen Fenster ab jetzt', () => {
      expect(nextExpiry(now, '2026-01-01T11:50:00.000Z', '2026-01-01T12:10:00.000Z'))
        .toBe('2026-01-01T14:00:00.000Z');
    });

    it('stoppt an der Acht-Stunden-Grenze', () => {
      // Anlage 04:10 Uhr -> Grenze 12:10 Uhr, obwohl 14:00 Uhr möglich wäre.
      expect(nextExpiry(now, '2026-01-01T04:10:00.000Z', '2026-01-01T12:05:00.000Z'))
        .toBe('2026-01-01T12:10:00.000Z');
    });

    it('verkürzt einen späteren Ablauf nie', () => {
      expect(nextExpiry(now, '2026-01-01T11:00:00.000Z', '2026-01-01T15:00:00.000Z'))
        .toBe('2026-01-01T15:00:00.000Z');
    });

    it('nimmt ohne Anlagedatum nur das gleitende Fenster', () => {
      expect(nextExpiry(now, undefined, '2026-01-01T12:10:00.000Z'))
        .toBe('2026-01-01T14:00:00.000Z');
    });

    it('bleibt bei der Obergrenze von acht Stunden', () => {
      expect(PAIRING_MAX_SECONDS).toBe(8 * 60 * 60);
    });
  });

  describe('normalizeToken()', () => {
    it('trimmt und schreibt groß', () => {
      expect(normalizeToken('  abC123 ')).toBe('ABC123');
      expect(normalizeToken(undefined)).toBe('');
    });
  });
});
