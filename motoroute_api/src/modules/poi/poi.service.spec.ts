import { Test } from '@nestjs/testing';
import { ConfigService } from '@nestjs/config';
import axios from 'axios';
import { PoiService } from './poi.service';
import { PoiSource } from './entities/poi.entity';
import { QueryPoisDto, PoiCategory } from './dto/query-pois.dto';

jest.mock('axios');
const mockedAxios = axios as jest.Mocked<typeof axios>;

const MUNICH_BBOX = [11.4, 48.1, 11.6, 48.2];

function dto(categories: PoiCategory[], bbox: number[] = MUNICH_BBOX): QueryPoisDto {
  return { bbox, categories } as QueryPoisDto;
}

async function buildService(env: Record<string, string | undefined>, supabase: unknown = null) {
  const moduleRef = await Test.createTestingModule({
    providers: [
      PoiService,
      { provide: ConfigService, useValue: { get: (key: string) => env[key] } },
      { provide: 'SUPABASE_CLIENT', useValue: supabase },
    ],
  }).compile();
  const service = moduleRef.get(PoiService);
  // Cache zwischen Tests isolieren.
  (service as unknown as { curatedCache: Map<string, unknown> }).curatedCache.clear();
  (service as unknown as { tableMissing: boolean }).tableMissing = false;
  return service;
}

describe('PoiService - TomTom-Kuratierung on-demand', () => {
  beforeEach(() => {
    mockedAxios.get.mockReset();
    mockedAxios.post.mockReset();
  });

  it('fragt TomTom für Kategorien ohne Overpass-Query (RESTAURANT) und mappt den Biker-Score', async () => {
    const service = await buildService({ TRAFFIC_API_KEY: 'tt-key', OVERPASS_URL: '' });
    mockedAxios.get.mockResolvedValueOnce({
      data: {
        results: [
          { id: 't1', poi: { name: 'Bikerstüberl' }, position: { lat: 48.15, lon: 11.5 }, address: { freeformAddress: 'München' } },
          { id: 't2', poi: { name: 'Gasthaus Alpenglühn' }, position: { lat: 48.14, lon: 11.52 } },
          { id: 't3', poi: { name: 'Kein Name vermutlich' }, position: {} }, // fällt raus
        ],
      },
    });

    const pois = await service.findInBoundingBox(dto([PoiCategory.RESTAURANT]));

    expect(pois).toHaveLength(2);
    expect(pois[0].source).toBe(PoiSource.CURATED);
    expect(pois[0].id).toBe('curated-restaurant-t1');
    // "Bikerstüberl" matcht das Biker-Keyword -> 40 + 15
    expect(pois[0].metadata?.bikerScore).toBe(55);
    expect(pois[1].metadata?.bikerScore).toBe(40);
    // TomTom-URL enthält Key + categorySet
    const [url, cfg] = mockedAxios.get.mock.calls[0];
    expect(String(url)).toContain('categorySearch/restaurant.json');
    expect((cfg as { params: Record<string, unknown> }).params.key).toBe('tt-key');
    expect((cfg as { params: Record<string, unknown> }).params.categorySet).toBe('7315014');
  });

  it('dedupliziert OSM gegen Kuratierung (75-m-Regel, OSM gewinnt)', async () => {
    const service = await buildService({ TRAFFIC_API_KEY: 'tt', OVERPASS_URL: '' });
    // Zwei Kuratierungs-Treffer am praktisch identischen Punkt:
    mockedAxios.get.mockResolvedValueOnce({
      data: {
        results: [
          { id: 'dup', poi: { name: 'Gasthof Kurve' }, position: { lat: 48.1, lon: 11.4 } },
          { id: 'other', poi: { name: 'Gasthof Kurve' }, position: { lat: 48.1005, lon: 11.4004 } }, // ~60 m
          { id: 'far', poi: { name: 'Gasthof Kurve' }, position: { lat: 48.11, lon: 11.41 } }, // > 1 km
        ],
      },
    });

    const pois = await service.findInBoundingBox(dto([PoiCategory.RESTAURANT]));

    // dup + other verschmelzen, far bleibt: 2 Treffer
    expect(pois).toHaveLength(2);
    expect(pois.map((p) => p.id).sort()).toEqual(['curated-restaurant-dup', 'curated-restaurant-far']);
  });

  it('degradiert ohne TomTom-Key zu leerer Kuratierung und fragt nichts', async () => {
    const service = await buildService({ OVERPASS_URL: '' });
    const pois = await service.findInBoundingBox(dto([PoiCategory.PUB, PoiCategory.FUEL]));
    expect(pois).toEqual([]);
    expect(mockedAxios.get).not.toHaveBeenCalled();
  });

  it('cached TomTom-Antworten pro Kategorie+Rasterzelle (kein zweiter Request)', async () => {
    const service = await buildService({ TRAFFIC_API_KEY: 'tt', OVERPASS_URL: '' });
    mockedAxios.get.mockResolvedValue({
      data: { results: [{ id: 'x', poi: { name: 'Kneipe' }, position: { lat: 48.1, lon: 11.4 } }] },
    });

    await service.findInBoundingBox(dto([PoiCategory.PUB]));
    await service.findInBoundingBox(dto([PoiCategory.PUB]));
    expect(mockedAxios.get).toHaveBeenCalledTimes(1);
  });

  it('negativ-cacht TomTom-Fehler (5 min), wirft nicht', async () => {
    const service = await buildService({ TRAFFIC_API_KEY: 'tt', OVERPASS_URL: '' });
    mockedAxios.get.mockRejectedValue(new Error('timeout'));

    await expect(service.findInBoundingBox(dto([PoiCategory.PUB]))).resolves.toEqual([]);
    await expect(service.findInBoundingBox(dto([PoiCategory.PUB]))).resolves.toEqual([]);
    expect(mockedAxios.get).toHaveBeenCalledTimes(1);
  });

  it('degradiert bei fehlender poi-Tabelle (PGRST205) statt 500 zu werfen', async () => {
    const supabase = {
      from: () => ({
        select: () => ({
          in: () => ({
            gte: () => ({
              lte: () => ({
                gte: () => ({
                  lte: () =>
                    Promise.resolve({
                      data: null,
                      error: { code: 'PGRST205', message: 'Could not find the table public.poi' },
                    }),
                }),
              }),
            }),
          }),
        }),
      }),
    };
    const service = await buildService({ OVERPASS_URL: '' }, supabase);

    await expect(service.findInBoundingBox(dto([PoiCategory.FUEL]))).resolves.toEqual([]);
  });

  it('spiegelt kuratierte Funde in die poi-Tabelle (upsert)', async () => {
    const upsert = jest.fn().mockResolvedValue({ error: null });
    let fromCalls = 0;
    const supabase = {
      from: jest.fn(() => {
        fromCalls += 1;
        if (fromCalls === 1) {
          // Erster Aufruf: queryDatabase (select-Kette)
          return {
            select: () => ({
              in: () => ({
                gte: () => ({
                  lte: () => ({
                    gte: () => ({
                      lte: () => Promise.resolve({ data: [], error: null }),
                    }),
                  }),
                }),
              }),
            }),
          };
        }
        return { upsert };
      }),
    };
    const service = await buildService({ TRAFFIC_API_KEY: 'tt', OVERPASS_URL: '' }, supabase);
    mockedAxios.get.mockResolvedValueOnce({
      data: { results: [{ id: 'x', poi: { name: 'Kneipe' }, position: { lat: 48.1, lon: 11.4 } }] },
    });

    await service.findInBoundingBox(dto([PoiCategory.PUB]));
    // Async-Spiegelung: kurze Warteschleife für den Mikrotask.
    await new Promise((r) => setTimeout(r, 0));
    expect(upsert).toHaveBeenCalledWith(
      expect.arrayContaining([expect.objectContaining({ id: 'curated-pub-x', category: 'PUB' })]),
      { onConflict: 'id' },
    );
  });
});
