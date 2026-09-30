import {
  BadRequestException,
  ConflictException,
  ForbiddenException,
  ServiceUnavailableException,
} from '@nestjs/common';
import { CheckinDto } from './badges.controller';
import { BadgesService, MatchedBadgeRow } from './badges.service';

/** Minimaler Supabase-Stub: nur rpc() + die zwei from()-Tabellen. */
function makeClient(overrides: {
  rpcRows?: MatchedBadgeRow[];
  rpcError?: { message: string } | null;
  rpcCalls?: unknown[];
  catalog?: Record<string, unknown>[];
  mine?: { badge_id: string; unlocked_at: string }[];
  catalogError?: { message: string } | null;
}) {
  return {
    rpc: (_fn: string, args: unknown) => {
      overrides.rpcCalls?.push(args);
      return Promise.resolve({ data: overrides.rpcRows ?? [], error: overrides.rpcError ?? null });
    },
    from: (table: string) => {
      if (table === 'badges') {
        return {
          select: () => ({
            order: () => ({
              order: () => Promise.resolve({ data: overrides.catalog ?? [], error: overrides.catalogError ?? null }),
            }),
          }),
        };
      }
      return {
        select: () => ({
          eq: () => Promise.resolve({ data: overrides.mine ?? [], error: null }),
        }),
      };
    },
  } as never;
}

const adminClient = { id: 'u-1', email: 'u@b.c', role: 'user' } as never;

const dto: CheckinDto = { lat: 46.52847, lon: 10.45255 };

describe('BadgesService', () => {
  it('ohne DB: checkin wirft DB_NOT_CONFIGURED (graceful, klar lesbar)', async () => {
    const svc = new BadgesService(null);
    await expect(svc.checkin(adminClient, 46.5, 10.4)).rejects.toThrow(ServiceUnavailableException);
    await expect(svc.myBadges(adminClient)).rejects.toThrow(ServiceUnavailableException);
  });

  it('checkin mappt neue Freischaltungen + Gesamtzahl korrekt', async () => {
    const rows: MatchedBadgeRow[] = [
      {
        badge_id: 'b1',
        title: 'Stilfser Joch',
        description: '48 Kurven',
        icon_url: null,
        required_category: 'pass',
        distance_m: 56,
        unlocked_now: true,
        total_user_badges: 7,
      },
      {
        badge_id: 'b2',
        title: 'Köterberg',
        description: 'Treff',
        icon_url: null,
        required_category: 'meeting',
        distance_m: 12,
        unlocked_now: false,
        total_user_badges: 7,
      },
    ];
    const svc = new BadgesService(makeClient({ rpcRows: rows }));
    const res = await svc.checkin(adminClient, dto.lat, dto.lon);
    expect(res.unlockedNow).toHaveLength(1);
    expect(res.unlockedNow[0]).toMatchObject({ id: 'b1', title: 'Stilfser Joch', distanceMeters: 56 });
    expect(res.revisited).toHaveLength(1);
    expect(res.totalUnlocked).toBe(7);
  });

  it('checkin ohne Treffer liefert leere Ergebnis', async () => {
    const svc = new BadgesService(makeClient({ rpcRows: [] }));
    const res = await svc.checkin(adminClient, 52.5, 13.4);
    expect(res.unlockedNow).toHaveLength(0);
    expect(res.revisited).toHaveLength(0);
    expect(res.totalUnlocked).toBe(0);
  });

  it('INVALID_COORDS aus der RPC wird zu BadRequest 400', async () => {
    const svc = new BadgesService(makeClient({ rpcError: { message: 'INVALID_COORDS' } }));
    await expect(svc.checkin(adminClient, 999, 999)).rejects.toThrow(BadRequestException);
  });

  it('andere RPC-Fehler (z. B. PostGIS fehlt) bleiben 503', async () => {
    const svc = new BadgesService(
      makeClient({ rpcError: { message: 'function match_badge_at does not exist' } }),
    );
    await expect(svc.checkin(adminClient, 46.5, 10.4)).rejects.toThrow(ServiceUnavailableException);
  });

  it('myBadges mischt Katalog + Freischaltungen (unlocked-Flag + Datum)', async () => {
    const catalog = [
      {
        id: 'b1',
        title: 'Stilfser Joch',
        description: '48 Kurven',
        icon_url: null,
        required_category: 'pass',
        pass_lat: 46.52847,
        pass_lon: 10.45255,
        radius_meters: 150,
      },
      {
        id: 'b2',
        title: 'Köterberg',
        description: 'Treff',
        icon_url: null,
        required_category: 'meeting',
        pass_lat: 51.9245,
        pass_lon: 9.3308,
        radius_meters: 120,
      },
    ];
    const mine = [{ badge_id: 'b1', unlocked_at: '2026-09-27T10:00:00Z' }];
    const svc = new BadgesService(makeClient({ catalog, mine }));
    const res = await svc.myBadges(adminClient);
    expect(res.totalCount).toBe(2);
    expect(res.unlockedCount).toBe(1);
    const stilfser = res.badges.find((b) => b.id === 'b1')!;
    expect(stilfser.unlocked).toBe(true);
    expect(stilfser.unlockedAt).toBe('2026-09-27T10:00:00Z');
    expect(res.badges.find((b) => b.id === 'b2')!.unlocked).toBe(false);
  });

  it('myBadges: Katalogfehler wird zu 503 (Wand bricht nicht halb)', async () => {
    const svc = new BadgesService(makeClient({ catalogError: { message: 'relation "badges" does not exist' } }));
    await expect(svc.myBadges(adminClient)).rejects.toThrow(ServiceUnavailableException);
  });
  it('checkin übergibt die verifizierte user_id an die RPC (Service-Role hat kein auth.uid())', async () => {
    const calls: unknown[] = [];
    const svc = new BadgesService(makeClient({ rpcCalls: calls }));
    await svc.checkin(adminClient, 46.52847, 10.45255);
    expect(calls).toEqual([
      { p_user_id: 'u-1', p_lat: 46.52847, p_lon: 10.45255 },
    ]);
  });
  describe('createBadge (Admin)', () => {
    const admin = { id: 'a-1', email: 'a@b.c', role: 'admin' } as never;
    const input = { title: '  Col de Test ', category: 'pass' as const, lat: 45.1, lon: 6.2 };

    function insertClient(result: { data?: unknown; error?: { code?: string; message: string } | null }, sink?: unknown[]) {
      return {
        from: (_t: string) => ({
          insert: (row: unknown) => {
            sink?.push(row);
            return {
              select: () => ({
                single: () => Promise.resolve({ data: result.data ?? null, error: result.error ?? null }),
              }),
            };
          },
        }),
      } as never;
    }

    it('Nicht-Admin bekommt 403 und es wird nichts geschrieben', async () => {
      const sink: unknown[] = [];
      const svc = new BadgesService(insertClient({}, sink));
      await expect(svc.createBadge(adminClient, input)).rejects.toThrow(ForbiddenException);
      expect(sink).toHaveLength(0);
    });

    it('Admin legt Badge an (Titel getrimmt, Default-Radius 150) und bekommt die Zeile gemappt', async () => {
      const sink: Record<string, unknown>[] = [];
      const row = {
        id: 'new-1', title: 'Col de Test', description: '', icon_url: null,
        required_category: 'pass', pass_lat: 45.1, pass_lon: 6.2, radius_meters: 150,
      };
      const svc = new BadgesService(insertClient({ data: row }, sink));
      const res = await svc.createBadge(admin, input);
      expect(sink[0]).toMatchObject({ title: 'Col de Test', required_category: 'pass', radius_meters: 150, icon_url: null });
      expect(res).toMatchObject({ id: 'new-1', title: 'Col de Test', category: 'pass', radiusMeters: 150 });
    });

    it('doppelter Titel (23505) -> 409', async () => {
      const svc = new BadgesService(insertClient({ error: { code: '23505', message: 'dup' } }));
      await expect(svc.createBadge(admin, input)).rejects.toThrow(ConflictException);
    });

    it('sonstiger DB-Fehler -> 503, ohne DB -> 503', async () => {
      const svc = new BadgesService(insertClient({ error: { message: 'boom' } }));
      await expect(svc.createBadge(admin, input)).rejects.toThrow(ServiceUnavailableException);
      await expect(new BadgesService(null).createBadge(admin, input)).rejects.toThrow(ServiceUnavailableException);
    });
  });
});
