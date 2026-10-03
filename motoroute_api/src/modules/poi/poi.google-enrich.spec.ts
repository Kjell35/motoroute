/**
 * Tests für die Google-Places-Anreicherung des POI-Detail-Endpunkts
 * (Audit-Fix 03.10.2026): Live-OSM-POIs ohne DB-Zeile bekommen über
 * einen Nearby-Match Bild/Beschreibung/Website; alles degradiert ehrlich.
 */
import { Test } from '@nestjs/testing';
import { ConfigService } from '@nestjs/config';
import axios from 'axios';
import { PoiService } from './poi.service';

jest.mock('axios');
const mockedAxios = axios as jest.Mocked<typeof axios>;

async function buildService(env: Record<string, string | undefined>, supabase: unknown = null) {
  const moduleRef = await Test.createTestingModule({
    providers: [
      PoiService,
      { provide: ConfigService, useValue: { get: (key: string) => env[key] } },
      { provide: 'SUPABASE_CLIENT', useValue: supabase },
    ],
  }).compile();
  const service = moduleRef.get(PoiService);
  (service as unknown as { curatedCache: Map<string, unknown> }).curatedCache.clear();
  (service as unknown as { googleEnrichCache: Map<string, unknown> }).googleEnrichCache.clear();
  return service;
}

function googleNearbyResponse(overrides: Record<string, unknown> = {}) {
  return {
    data: {
      places: [
        {
          id: 'GP-1',
          displayName: { text: 'Gasthof Alpenblick' },
          formattedAddress: 'Alpenstraße 1, 82467 Garmisch',
          websiteUri: 'https://alpenblick.example',
          googleMapsUri: 'https://maps.google.com/?cid=123',
          editorialSummary: { text: 'Klassischer bayerischer Wirtshaus-Garten.' },
          photos: [
            {
              name: 'places/GP-1/photos/ATJ83zhSSAtk/media',
              authorAttributions: [{ displayName: 'Max Muster' }],
            },
          ],
          ...overrides,
        },
      ],
    },
  };
}

describe('PoiService - Google-Enrichment (Detail)', () => {
  beforeEach(() => {
    mockedAxios.get.mockReset();
    mockedAxios.post.mockReset();
  });

  it('angereichert: OSM-POI ohne DB-Zeile bekommt Google-Website/-Foto/-Summary', async () => {
    const service = await buildService({ GOOGLE_PLACES_API_KEY: 'g-key' });
    mockedAxios.post.mockResolvedValueOnce(googleNearbyResponse());

    const detail = await service.findDetail('osm-node-42', 47.55, 11.03, 'RESTAURANT');

    expect(detail).not.toBeNull();
    expect(detail!.website).toBe('https://alpenblick.example');
    expect(detail!.imageUrl).toBe(
      '/v1/pois/photo?name=' + encodeURIComponent('places/GP-1/photos/ATJ83zhSSAtk/media'),
    );
    expect(detail!.description).toContain('bayerischer');
    expect(detail!.googleMapsUri).toContain('maps.google.com');
    expect(detail!.photoAttribution).toBe('Max Muster');
    expect(detail!.publishedBy).toBe('Google Places');
    // Nearby-Call gegen places.googleapis.com mit FieldMask (3 Argumente:
    // url, body, config).
    const [url, , cfg] = mockedAxios.post.mock.calls[0];
    expect(String(url)).toContain('places.googleapis.com');
    expect((cfg as { headers: Record<string, string> }).headers['X-Goog-Api-Key']).toBe('g-key');
    expect((cfg as { headers: Record<string, string> }).headers['X-Goog-FieldMask']).toContain(
      'places.websiteUri',
    );
  });

  it('eigene Daten gewinnen: vorhandene Website/DB-Zeile wird nicht überschrieben', async () => {
    const supabase = {
      from: () => ({
        select: () => ({
          eq: () => ({
            maybeSingle: () =>
              Promise.resolve({
                data: {
                  id: 'curated-pub-1',
                  category: 'PUB',
                  name: 'Bikerstüberl',
                  lat: 48.1,
                  lng: 11.4,
                  source: 'CURATED',
                  created_at: '2026-09-01T10:00:00Z',
                  metadata: { website: 'bikerstueberl.example' },
                },
                error: null,
              }),
          }),
        }),
      }),
    };
    const service = await buildService({ GOOGLE_PLACES_API_KEY: 'g-key' }, supabase);
    mockedAxios.post.mockResolvedValueOnce(googleNearbyResponse());

    const detail = await service.findDetail('curated-pub-1');

    expect(detail!.website).toBe('https://bikerstueberl.example');
    expect(detail!.publishedBy).toBe('Biker-POI-Kuratierung (TomTom)');
    expect(detail!.publishedAt).toBe('2026-09-01T10:00:00Z');
  });

  it('ohne Key: kein Google-Call, ehrliches DB/OSM-Detail', async () => {
    const service = await buildService({});
    const detail = await service.findDetail('osm-node-42', 47.55, 11.03, 'RESTAURANT');
    expect(mockedAxios.post).not.toHaveBeenCalled();
    expect(detail).toBeNull();
  });

  it('KOSTENLOSE KETTE: Wikimedia Commons liefert das Bild ohne jeden Key', async () => {
    const service = await buildService({});
    // Commons-GeoSearch (formatversion 2 -> pages als Array):
    mockedAxios.get.mockResolvedValueOnce({
      data: {
        query: {
          pages: [
            {
              title: 'File:Koelner Dom.jpg',
              imageinfo: [
                {
                  thumburl: 'https://upload.wikimedia.org/wikipedia/commons/thumb/koeln.jpg/640px-koeln.jpg',
                  extmetadata: {
                    Artist: { value: '<a href="//commons.wikimedia.org">Max Fotograf</a>' },
                  },
                },
              ],
            },
          ],
        },
      },
    });

    const detail = await service.findDetail('osm-node-42', 50.9413, 6.9583, 'RESTAURANT');
    expect(detail).not.toBeNull();
    expect(detail!.imageUrl).toContain('upload.wikimedia.org');
    expect(detail!.photoAttribution).toBe('Max Fotograf / Wikimedia Commons');
    // Keyless bestätigt: kein Google-Call, Commons-URL mit Parametern:
    expect(mockedAxios.post).not.toHaveBeenCalled();
    const [url, cfg] = mockedAxios.get.mock.calls[0];
    expect(String(url)).toContain('commons.wikimedia.org');
    expect((cfg as { headers: Record<string, string> }).headers['User-Agent']).toContain(
      'MotoRoute',
    );
  });

  it('DB-Zeile mit eigenem Bild: kein Wikimedia-Call (Kosten sparen)', async () => {
    const supabase = {
      from: () => ({
        select: () => ({
          eq: () => ({
            maybeSingle: () =>
              Promise.resolve({
                data: {
                  id: 'curated-pub-3',
                  category: 'PUB',
                  name: 'Mit Bild',
                  lat: 48.1,
                  lng: 11.4,
                  source: 'CURATED',
                  created_at: '2026-09-01T10:00:00Z',
                  metadata: { image_url: 'https://example.com/foto.jpg' },
                },
                error: null,
              }),
          }),
        }),
      }),
    };
    const service = await buildService({}, supabase);
    await service.findDetail('curated-pub-3');
    expect(mockedAxios.get).not.toHaveBeenCalled();
  });

  it('Wikimedia ohne Treffer + keine DB-Zeile -> ehrlich null', async () => {
    const service = await buildService({});
    mockedAxios.get.mockResolvedValueOnce({ data: { query: { pages: [] } } });
    const detail = await service.findDetail('osm-node-42', 47.55, 11.03, 'RESTAURANT');
    expect(detail).toBeNull();
  });

  it('SPEED_CAMERA: kein Google-Call (keine Entsprechung)', async () => {
    const service = await buildService({ GOOGLE_PLACES_API_KEY: 'g-key' });
    await service.findDetail('osm-node-99', 47.55, 11.03, 'SPEED_CAMERA');
    expect(mockedAxios.post).not.toHaveBeenCalled();
  });

  it('Google-Fehler degradiert: kein Throw; ohne DB-Zeile -> 404-Pfad, App zeigt Basis-Sheet', async () => {
    const service = await buildService({ GOOGLE_PLACES_API_KEY: 'g-key' });
    mockedAxios.post.mockRejectedValueOnce(new Error('timeout'));
    // Kein DB-Zeile + Google-Fehlschlag = nichts Neues für die App -> null.
    await expect(
      service.findDetail('osm-node-42', 47.55, 11.03, 'RESTAURANT'),
    ).resolves.toBeNull();
  });

  it('Google-Fehler mit DB-Zeile: Detail bleibt, nichts angereichert, kein Throw', async () => {
    const supabase = {
      from: () => ({
        select: () => ({
          eq: () => ({
            maybeSingle: () =>
              Promise.resolve({
                data: {
                  id: 'curated-pub-2',
                  category: 'PUB',
                  name: 'Zum Kurvenkiller',
                  lat: 48.1,
                  lng: 11.4,
                  source: 'CURATED',
                  created_at: '2026-09-01T10:00:00Z',
                  metadata: {},
                },
                error: null,
              }),
          }),
        }),
      }),
    };
    const service = await buildService({ GOOGLE_PLACES_API_KEY: 'g-key' }, supabase);
    mockedAxios.post.mockRejectedValueOnce(new Error('timeout'));

    const detail = await service.findDetail('curated-pub-2');
    expect(detail).not.toBeNull();
    expect(detail!.website).toBeNull();
    expect(detail!.googleMapsUri).toBeNull();
    expect(detail!.publishedBy).toBe('Biker-POI-Kuratierung (TomTom)');
  });

  it('cached die Anreicherung pro poi-id (kein zweiter Google-Call)', async () => {
    const service = await buildService({ GOOGLE_PLACES_API_KEY: 'g-key' });
    mockedAxios.post.mockResolvedValue(googleNearbyResponse());

    await service.findDetail('osm-node-42', 47.55, 11.03, 'RESTAURANT');
    await service.findDetail('osm-node-42', 47.55, 11.03, 'RESTAURANT');
    expect(mockedAxios.post).toHaveBeenCalledTimes(1);
  });

  describe('Foto-Proxy', () => {
    it('streamt Google-Foto-Binary ohne Key-Exposure', async () => {
      const service = await buildService({ GOOGLE_PLACES_API_KEY: 'g-key' });
      const jpeg = new Uint8Array([0xff, 0xd8, 0xff, 0xe0]).buffer;
      mockedAxios.get.mockResolvedValueOnce({
        data: jpeg,
        headers: { 'content-type': 'image/jpeg' },
      });

      const photo = await service.fetchGooglePhoto('places/GP-1/photos/ABC/media');
      expect(photo).not.toBeNull();
      expect(photo!.contentType).toBe('image/jpeg');
      const [url, cfg] = mockedAxios.get.mock.calls[0];
      expect(String(url)).toContain('places/GP-1/photos/ABC/media');
      expect((cfg as { params: Record<string, unknown> }).params.key).toBe('g-key');
      expect((cfg as { params: Record<string, unknown> }).params.skipHttpRedirect).toBe(true);
    });

    it('lehnt nicht-Format-konforme name-Parameter ab (kein SSRF-Träger)', async () => {
      const service = await buildService({ GOOGLE_PLACES_API_KEY: 'g-key' });
      expect(await service.fetchGooglePhoto('https://evil.example/steal')).toBeNull();
      expect(await service.fetchGooglePhoto('places/../../secrets')).toBeNull();
      expect(await service.fetchGooglePhoto('')).toBeNull();
      expect(mockedAxios.get).not.toHaveBeenCalled();
    });

    it('ohne Key: 404-Pfad (null)', async () => {
      const service = await buildService({});
      expect(await service.fetchGooglePhoto('places/GP-1/photos/ABC/media')).toBeNull();
      expect(mockedAxios.get).not.toHaveBeenCalled();
    });
  });
});
