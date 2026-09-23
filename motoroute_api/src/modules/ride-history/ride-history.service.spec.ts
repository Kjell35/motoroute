import { HttpException } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import { ConfigService } from '@nestjs/config';

/**
 * Der Service erzeugt in scoped() einen NEUEN Supabase-Client mit dem
 * User-JWT (RLS bleibt Durchsetzungsschicht). Wir mocken createClient
 * auf Modulebene und steuern pro Test, was PostgREST liefern wuerde -
 * der fluent Query-Builder wird per Ketten-Mock simuliert (kein
 * echter Netzcall).
 */

interface ClientConfig {
  /** users-Zeile (Privacy-Flags). */
  profileRow?: Record<string, unknown> | null;
  profileError?: { code?: string; message?: string } | null;
  /** ride_history-Zeilen fuer .select().eq().order(). */
  rideRows?: Array<Record<string, unknown>>;
  rideRowsError?: { code?: string; message?: string } | null;
  placeRows?: Array<Record<string, unknown>>;
  placeRowsError?: { code?: string; message?: string } | null;
  /** Fehler fuer upsert/update/insert. */
  writeError?: { code?: string; message?: string } | null;
}

let clientConfig: ClientConfig = {};
const upsertCalls: Array<Record<string, unknown>> = [];

function makeClient() {
  const resolveFor = (table: string) => (cfg: ClientConfig) => {
    if (table === 'users') return { data: cfg.profileRow ?? null, error: cfg.profileError ?? null };
    if (table === 'ride_history') return { data: cfg.rideRows ?? null, error: cfg.rideRowsError ?? null };
    if (table === 'place_visits') return { data: cfg.placeRows ?? null, error: cfg.placeRowsError ?? null };
    return { data: null, error: null };
  };
  const builder = (table: string) => ({
    select: (_cols?: string) => builder(table),
    eq: (_col: string, _val: unknown) => builder(table),
    order: (_col: string, _opts?: unknown) => builder(table),
    limit: (_n: number) => builder(table),
    update: (_patch: Record<string, unknown>) => ({
      eq: () => Promise.resolve({ data: null, error: clientConfig.writeError ?? null }),
    }),
    insert: (_row: Record<string, unknown>) =>
      Promise.resolve({ data: null, error: clientConfig.writeError ?? null }),
    upsert: (row: Record<string, unknown>) => {
      upsertCalls.push(row);
      return Promise.resolve({ data: null, error: clientConfig.writeError ?? null });
    },
    maybeSingle: () => Promise.resolve(resolveFor(table)(clientConfig)),
    // Thenable: await auf einer Query-Kette loest mit den Tabellen-Daten.
    then: (onF: (v: unknown) => unknown, onR?: (e: unknown) => unknown) =>
      Promise.resolve(resolveFor(table)(clientConfig)).then(onF, onR),
  });
  return { from: (table: string) => builder(table) };
}

jest.mock('@supabase/supabase-js', () => ({
  createClient: jest.fn(() => makeClient()),
}));

import { SearchService } from '../search/search.service';
import { RideHistoryService, PrivacyUpdateDto, RideSyncDto } from './ride-history.service';

async function buildService(): Promise<RideHistoryService> {
  const moduleRef = await Test.createTestingModule({
    providers: [
      RideHistoryService,
      { provide: 'SUPABASE_CLIENT', useValue: {} },
      { provide: SearchService, useValue: { reverse: async () => null } },
      {
        provide: ConfigService,
        useValue: {
          get: (key: string) =>
            key === 'SUPABASE_URL'
              ? 'https://test.supabase.co'
              : 'anon-key-0123456789abcdefghij',
        },
      },
    ],
  }).compile();
  return moduleRef.get(RideHistoryService);
}

const user = { id: 'u-1', token: 'jwt-token' };

const validSync: RideSyncDto = {
  externalId: 'tour-2026-09-23-1',
  title: 'Alpentour',
  startedAt: '2026-09-23T08:00:00.000Z',
  endedAt: '2026-09-23T12:30:00.000Z',
  distanceMeters: 185000,
  durationSeconds: 16200,
  elevationGainMeters: 2400,
  track: [
    { lat: 47.56, lng: 10.74, elevationMeters: 1100, secondsSinceStart: 0 },
    { lat: 47.58, lng: 10.78, elevationMeters: 1180, secondsSinceStart: 600 },
  ],
  pois: [
    { externalId: 'poi-bikertreff-1', category: 'bikertreff', label: 'Bikertreff Kurve', lat: 47.57, lng: 10.76 },
  ],
  startLabel: 'Garmisch',
  endLabel: 'Füssen',
  startLat: 47.56,
  startLng: 10.74,
  endLat: 47.58,
  endLng: 10.78,
};

describe('RideHistoryService', () => {
  beforeEach(() => {
    clientConfig = {};
    upsertCalls.length = 0;
  });

  it('syncRide upsertet die Tour und leitet Orte ab', async () => {
    clientConfig = {
      profileRow: { auth_privacy: 'private', share_rides: false },
      placeRows: [],
    };
    const service = await buildService();

    const result = await service.syncRide(user, validSync);
    expect(result.synced).toBe(true);
    expect(upsertCalls).toHaveLength(1);
    expect(upsertCalls[0].external_id).toBe('tour-2026-09-23-1');
    expect(upsertCalls[0].user_id).toBe('u-1');
    expect(upsertCalls[0].is_public).toBe(false);
    expect(upsertCalls[0].share_track).toBe(true);
  });

  it('syncRide setzt neue Touren oeffentlich, wenn Profil oeffentlich + shareRides', async () => {
    clientConfig = {
      profileRow: { auth_privacy: 'public', share_rides: true },
      placeRows: [],
    };
    const service = await buildService();
    await service.syncRide(user, validSync);
    expect(upsertCalls[0].is_public).toBe(true);
  });

  it('syncRide ohne Pflichtfelder -> 400', async () => {
    const service = await buildService();
    await expect(
      service.syncRide(user, { ...validSync, externalId: '' } as never),
    ).rejects.toMatchObject({ status: 400 });
  });

  it('syncRide ohne Migration -> 503 SCHEMA_NOT_MIGRATED', async () => {
    clientConfig = {
      profileRow: null,
      profileError: { code: 'PGRST205', message: "relation 'users' does not exist" },
    };
    const service = await buildService();
    await expect(service.syncRide(user, validSync)).rejects.toMatchObject({ status: 503 });
  });

  it('getMyHistory liefert Settings mit sicheren Defaults (privat)', async () => {
    clientConfig = {
      profileRow: null,
      rideRows: [
        {
          external_id: 't-1',
          title: 'X',
          is_public: false,
          share_track: true,
          track: [{ lat: 1, lng: 2, secondsSinceStart: 0 }],
          pois: [],
          photos: [],
        },
      ],
      placeRows: [],
    };
    const service = await buildService();
    const res = await service.getMyHistory(user);
    expect(res.settings.authPrivacy).toBe('private');
    expect(res.settings.shareRides).toBe(false);
    expect(res.settings.hideStartEnd).toBe(true);
    expect(res.rides).toHaveLength(1);
  });

  it('updatePrivacy schreibt die 5 Flags auf users', async () => {
    const service = await buildService();
    const dto: PrivacyUpdateDto = {
      authPrivacy: 'public',
      shareRides: true,
      sharePlaces: false,
      hideStartEnd: true,
      rideHistoryEnabled: true,
    };
    const res = await service.updatePrivacy(user, dto);
    expect(res.updated).toBe(true);
  });

  it('getPublicProfile: privates Profil -> nur Basisdaten, keine Historie', async () => {
    clientConfig = {
      profileRow: {
        id: 'u-2',
        username: 'maxi',
        display_name: 'Maxi',
        avatar_url: null,
        auth_privacy: 'private',
        share_rides: true,
        share_places: true,
        hide_start_end: false,
      },
    };
    const service = await buildService();
    const res = await service.getPublicProfile(user, 'u-2');
    expect(res.profile.isPrivate).toBe(true);
    expect(res.history.rideCount).toBe(0);
    expect(res.history.rides).toHaveLength(0);
    expect(res.history.places).toHaveLength(0);
  });

  it('getPublicProfile: oeffentlich + shareRides -> Touren mit Track, hide_start_end entfernt Koordinaten', async () => {
    clientConfig = {
      profileRow: {
        id: 'u-2',
        username: 'maxi',
        display_name: 'Maxi',
        avatar_url: null,
        auth_privacy: 'public',
        share_rides: true,
        share_places: false,
        hide_start_end: true,
      },
      rideRows: [
        {
          external_id: 't-9',
          title: 'Kurventour',
          started_at: '2026-09-01T08:00:00Z',
          ended_at: '2026-09-01T10:00:00Z',
          distance_meters: 120000,
          duration_seconds: 7200,
          elevation_gain_meters: 900,
          track: [{ lat: 47.5, lng: 10.7, secondsSinceStart: 0 }],
          pois: [{ label: 'Tanke', lat: 47.51, lng: 10.71 }],
          start_label: 'Startort',
          end_label: 'Zielort',
          start_lat: 47.5,
          start_lng: 10.7,
          end_lat: 47.9,
          end_lng: 10.9,
          region: 'Bayern',
          description: 'Schöne Runde',
          photos: [],
          is_public: true,
          share_track: true,
        },
      ],
    };
    const service = await buildService();
    const res = await service.getPublicProfile(user, 'u-2');
    expect(res.profile.isPrivate).toBe(false);
    expect(res.history.rideCount).toBe(1);
    const ride = res.history.rides[0];
    expect(ride.title).toBe('Kurventour');
    expect(ride.track).toHaveLength(1);
    expect(ride.startLabel).toBe('Startort');
    // hide_start_end: exakte Koordinaten werden NIE ausgeliefert.
    expect(ride.start).toBeNull();
    expect(ride.end).toBeNull();
    expect(res.history.totalKm).toBeCloseTo(120, 1);
    expect(res.history.regions).toEqual(['Bayern']);
    // share_places=false: Orte bleiben privat.
    expect(res.history.places).toHaveLength(0);
  });

  it('getPublicProfile: share_track=false -> Statistik bleibt, Track leer', async () => {
    clientConfig = {
      profileRow: {
        id: 'u-2',
        username: 'maxi',
        display_name: null,
        avatar_url: null,
        auth_privacy: 'public',
        share_rides: true,
        share_places: true,
        hide_start_end: false,
      },
      rideRows: [
        {
          external_id: 't-10',
          title: 'Privatroute',
          started_at: '2026-09-01T08:00:00Z',
          ended_at: '2026-09-01T09:00:00Z',
          distance_meters: 50000,
          duration_seconds: 3600,
          elevation_gain_meters: 300,
          track: [{ lat: 48.1, lng: 11.5, secondsSinceStart: 0 }],
          pois: [],
          start_label: null,
          end_label: null,
          start_lat: 48.1,
          start_lng: 11.5,
          end_lat: null,
          end_lng: null,
          region: null,
          description: null,
          photos: [],
          is_public: true,
          share_track: false,
        },
      ],
      placeRows: [
        {
          external_id: 'poi-1',
          category: 'fuel',
          label: 'Tankstelle Bayreuth',
          lat: 49.95,
          lng: 11.57,
          visit_count: 3,
          last_visited_at: '2026-09-20T10:00:00Z',
        },
      ],
    };
    const service = await buildService();
    const res = await service.getPublicProfile(user, 'u-2');
    const ride = res.history.rides[0];
    expect(ride.distanceMeters).toBe(50000);
    expect(ride.track).toHaveLength(0);
    expect(ride.start).toEqual({ lat: 48.1, lng: 11.5 });
    expect(res.history.places).toHaveLength(1);
    expect(res.history.places[0].visitCount).toBe(3);
  });

  it('getPublicProfile: Profilzeile fehlt -> isPrivate', async () => {
    clientConfig = { profileRow: null };
    const service = await buildService();
    const res = await service.getPublicProfile(user, 'u-404');
    expect(res.profile.isPrivate).toBe(true);
    expect(res.history.rideCount).toBe(0);
  });

  it('HttpException bei DB-Fehler ist definiert (kein 500-Rohwurf)', async () => {
    clientConfig = {
      profileRow: null,
      profileError: { code: 'PGRST205', message: 'schema cache' },
    };
    const service = await buildService();
    await expect(service.getMyHistory(user)).rejects.toBeInstanceOf(HttpException);
  });
});
