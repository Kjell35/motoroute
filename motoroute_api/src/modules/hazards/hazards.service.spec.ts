import { GoneException, NotFoundException } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import { ConfigService } from '@nestjs/config';

/**
 * Der Service erzeugt in scoped() einen NEUEN Supabase-Client mit dem
 * User-JWT (RLS bleibt Durchsetzungsschicht). Für die Tests mocken wir
 * createClient auf Modulebene - damit kontrolliert jeder Test exakt das
 * rpc()-Verhalten, das der Service dann erhält (kein echter Netzcall).
 */
const rpcMock = jest.fn();

jest.mock('@supabase/supabase-js', () => ({
  createClient: jest.fn(() => ({ rpc: rpcMock })),
}));

import { HazardsService } from './hazards.service';

async function buildService(): Promise<HazardsService> {
  const moduleRef = await Test.createTestingModule({
    providers: [
      HazardsService,
      { provide: 'SUPABASE_CLIENT', useValue: {} },
      {
        provide: ConfigService,
        useValue: {
          get: (key: string) =>
            key === 'SUPABASE_URL' ? 'https://test.supabase.co' : 'anon-key-0123456789abcdefghij',
        },
      },
    ],
  }).compile();
  return moduleRef.get(HazardsService);
}

const user = { id: 'u-1', token: 'jwt-token' };

describe('HazardsService (Community-Gefahrenradar)', () => {
  beforeEach(() => {
    rpcMock.mockReset();
  });

  it('createReport ruft hazard_report_create mit korrekten Parametern', async () => {
    rpcMock.mockResolvedValueOnce({ data: { id: 'h-1', merged: false, upvotes: 1 }, error: null });
    const service = await buildService();

    const result = (await service.createReport(user, {
      reportType: 'oelspur',
      lat: 48.1,
      lng: 11.5,
      description: 'Kurvenausgang',
    })) as { id: string; merged: boolean };

    expect(rpcMock).toHaveBeenCalledWith('hazard_report_create', {
      p_type: 'oelspur',
      p_lat: 48.1,
      p_lng: 11.5,
      p_description: 'Kurvenausgang',
    });
    expect(result.merged).toBe(false);
  });

  it('nearby übergibt Radius in Metern (km -> m)', async () => {
    rpcMock.mockResolvedValueOnce({ data: [], error: null });
    const service = await buildService();

    await service.nearby(user, { lat: 48, lon: 11, radiusKm: 25 });
    expect(rpcMock).toHaveBeenCalledWith('hazard_report_nearby', {
      p_lat: 48,
      p_lng: 11,
      p_radius_m: 25000,
    });
  });

  it('nearby: Default-Radius 50 km, wenn keiner gesetzt ist', async () => {
    rpcMock.mockResolvedValueOnce({ data: [], error: null });
    const service = await buildService();

    await service.nearby(user, { lat: 48, lon: 11 });
    expect(rpcMock).toHaveBeenCalledWith('hazard_report_nearby', {
      p_lat: 48,
      p_lng: 11,
      p_radius_m: 50000,
    });
  });

  it('upvote mappt fehlende Meldung auf 404', async () => {
    rpcMock.mockResolvedValueOnce({ data: null, error: { code: 'P0002', message: 'NOT_FOUND' } });
    const service = await buildService();

    await expect(service.upvote(user, '00000000-0000-0000-0000-000000000001')).rejects.toThrow(
      NotFoundException,
    );
  });

  it('upvote mappt abgelaufene Meldung auf 410 Gone (Client entfernt Marker)', async () => {
    rpcMock.mockResolvedValueOnce({ data: null, error: { code: 'P0001', message: 'EXPIRED' } });
    const service = await buildService();

    await expect(service.upvote(user, '00000000-0000-0000-0000-000000000002')).rejects.toThrow(
      GoneException,
    );
  });

  it('mappt fehlenden Token auf 403 (kein RPC-Call)', async () => {
    const service = await buildService();

    await expect(
      service.createReport({ id: 'u-1' }, { reportType: 'sperrung', lat: 48, lng: 11 }),
    ).rejects.toThrow(/Token fehlt/);
    expect(rpcMock).not.toHaveBeenCalled();
  });
});
