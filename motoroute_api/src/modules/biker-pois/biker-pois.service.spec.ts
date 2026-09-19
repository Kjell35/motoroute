import { Test } from '@nestjs/testing';
import { ConfigService } from '@nestjs/config';
import axios from 'axios';
import { BikerPoisService } from './biker-pois.service';

jest.mock('axios');
const mockedAxios = axios as jest.Mocked<typeof axios>;

describe('BikerPoisService (BFF-Proxy)', () => {
  let service: BikerPoisService;

  beforeEach(async () => {
    const moduleRef = await Test.createTestingModule({
      providers: [
        BikerPoisService,
        { provide: 'SUPABASE_CLIENT', useValue: {} },
        {
          provide: ConfigService,
          useValue: { get: (key: string) => (key === 'BIKER_POI_SERVICE_URL' ? 'http://poi-service:3100' : '') },
        },
      ],
    }).compile();
    service = moduleRef.get(BikerPoisService);
    service['cache'].clear();
    mockedAxios.get.mockReset();
  });

  it('mappt Dienst-Kategorien auf App-Kategorien (gartenlokal -> BIKER_MEETUP)', async () => {
    mockedAxios.get.mockResolvedValueOnce({
      data: {
        serverTime: '2026-09-18T10:00:00.000Z',
        hasMore: false,
        upserted: [
          { id: 'p1', name: 'Biergarten am See', category: 'gartenlokal', lat: 48.1, lon: 11.5, bikerScore: 45, amenities: {}, updatedAt: '2026-09-18T09:00:00.000Z' },
          { id: 'p2', name: 'Kneipe zum Kurvenkönig', category: 'kneipe', lat: 48.2, lon: 11.6, bikerScore: 40, amenities: {}, updatedAt: '2026-09-18T09:00:00.000Z' },
          { id: 'p3', name: 'Pension Alpenglück', category: 'pension', lat: 48.3, lon: 11.7, bikerScore: 40, amenities: {}, updatedAt: '2026-09-18T09:00:00.000Z' },
        ],
        deletedIds: [],
      },
    });

    const result = await service.sync({ since: '2026-09-17T00:00:00.000Z' });
    expect(result.pois.map((p) => p.category)).toEqual(['BIKER_MEETUP', 'PUB', 'MOTO_HOTEL']);
    // Namensraum-Trennung zu OSM-POIs
    expect(result.pois[0].id).toBe('biker-p1');
  });

  it('gibt Cursor (serverTime) als neuen since-Stand zurück', async () => {
    mockedAxios.get.mockResolvedValueOnce({
      data: {
        serverTime: '2026-09-18T10:00:00.000Z',
        hasMore: false,
        upserted: [],
        deletedIds: ['old-1'],
      },
    });
    const result = await service.sync({ since: '2026-09-17T00:00:00.000Z' });
    expect(result.since).toBe('2026-09-18T10:00:00.000Z');
    expect(result.deletedIds).toEqual(['biker-old-1']);
  });

  it('filtert Ergebnisse ohne valide Koordinaten aus (Datenqualität)', async () => {
    mockedAxios.get.mockResolvedValueOnce({
      data: {
        serverTime: '2026-09-18T10:00:00.000Z',
        hasMore: false,
        upserted: [
          { id: 'ok', name: 'Ok', category: 'hotel', lat: 48, lon: 11, bikerScore: 40, amenities: {}, updatedAt: 'x' },
          { id: 'bad', name: 'Kaputt', category: 'hotel', lat: 'n/a', lon: null, bikerScore: 0, amenities: {}, updatedAt: 'x' },
        ],
        deletedIds: [],
      },
    });
    const result = await service.sync({ since: '2026-09-17T00:00:00.000Z' });
    expect(result.pois).toHaveLength(1);
    expect(result.pois[0].id).toBe('biker-ok');
  });

  it('cached identische Delta-Anfragen (60 s TTL)', async () => {
    const payload = { serverTime: '2026-09-18T10:00:00.000Z', hasMore: false, upserted: [], deletedIds: [] };
    mockedAxios.get.mockResolvedValue({ data: payload });

    await service.sync({ since: '2026-09-17T00:00:00.000Z' });
    await service.sync({ since: '2026-09-17T00:00:00.000Z' });

    expect(mockedAxios.get).toHaveBeenCalledTimes(1);
  });

  it('unterscheidet Cache-Schlüssel nach Parametern', async () => {
    const payload = { serverTime: 'x', hasMore: false, upserted: [], deletedIds: [] };
    mockedAxios.get.mockResolvedValue({ data: payload });

    await service.sync({ since: 's1' });
    await service.sync({ since: 's2' });
    await service.sync({ since: 's1', lat: 48, lon: 11, radiusKm: 50 });

    expect(mockedAxios.get).toHaveBeenCalledTimes(3);
  });
});
