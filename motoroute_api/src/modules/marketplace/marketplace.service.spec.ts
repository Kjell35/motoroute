import { Test } from '@nestjs/testing';
import { ConfigService } from '@nestjs/config';
import { MarketplaceService } from './marketplace.service';
import { GeminiReviewService } from './gemini-review.service';
import { SearchService } from '../search/search.service';
import { SUPABASE_CLIENT } from '../../supabase/supabase.module';

/**
 * Tests fuer die intelligente Suche (Punkt 13): Mehrwoertige Queries
 * ("BMW Auspuff") muessen per wortweiser UND-Verknuepfung Treffer
 * finden, deren Felder die Begriffe an verschiedenen Stellen tragen.
 */

/** Client + getrennter Query-Builder (der Builder ist thenable, der Client nicht). */
function fakeSupabase(captured: { ors: string[] }) {
  const builder: Record<string, any> = {};
  const client = { from: jest.fn(() => builder) };
  builder.select = jest.fn(() => builder);
  builder.eq = jest.fn(() => builder);
  builder.ilike = jest.fn(() => builder);
  builder.gte = jest.fn(() => builder);
  builder.lte = jest.fn(() => builder);
  builder.range = jest.fn(() => builder);
  builder.order = jest.fn(() => builder);
  builder.or = jest.fn((s: string) => {
    captured.ors.push(s);
    return builder;
  });
  builder.then = (resolve: (v: unknown) => void) => resolve({ data: [], error: null, count: 0 });
  return client;
}

describe('MarketplaceService listPublic - intelligente Suche', () => {
  let service: MarketplaceService;
  let captured: { ors: string[] };

  beforeEach(async () => {
    captured = { ors: [] };
    const moduleRef = await Test.createTestingModule({
      providers: [
        MarketplaceService,
        GeminiReviewService,
        { provide: ConfigService, useValue: { get: () => 'x' } },
        { provide: SearchService, useValue: {} },
        { provide: SUPABASE_CLIENT, useValue: fakeSupabase(captured) },
      ],
    }).compile();
    service = moduleRef.get(MarketplaceService);
  });

  it('teilt mehrwoertige Queries in wortweise UND-Verknuepfung', async () => {
    await service.listPublic({ q: 'BMW Auspuff' });
    expect(captured.ors.length).toBe(2);
    expect(captured.ors[0]).toContain('title.ilike.%BMW%');
    expect(captured.ors[1]).toContain('title.ilike.%Auspuff%');
  });

  it('ignoriert Ein-Wort-Kuerzel und limitiert auf 5 Begriffe', async () => {
    await service.listPublic({ q: 'a BMW Auspuff Felge Bremse Reifen Motor' });
    // 'a' (< 2 Zeichen) fliegt raus -> 5 Begriffe bleiben
    expect(captured.ors.length).toBe(5);
  });

  it('kein q -> keine or-Klauseln', async () => {
    await service.listPublic({});
    expect(captured.ors.length).toBe(0);
  });
});

/**
 * Bild-URL-Vertrag: Der Server liefert image_urls mit ECHTEN Supabase-
 * publicUrls (positionssortiert) und NIE das rohe storage_path-Embed -
 * der frühere Client-seitige URL-Builder gegen die API-Domain produzierte
 * für jedes Foto einen 404er.
 */
describe('MarketplaceService image_urls-Vertrag', () => {
  function fakeSupabaseWithListing(listingRow: Record<string, unknown>) {
    const builder: Record<string, any> = {};
    const client: Record<string, any> = { from: jest.fn(() => builder) };
    builder.select = jest.fn(() => builder);
    builder.eq = jest.fn(() => builder);
    builder.ilike = jest.fn(() => builder);
    builder.gte = jest.fn(() => builder);
    builder.lte = jest.fn(() => builder);
    builder.range = jest.fn(() => builder);
    builder.order = jest.fn(() => builder);
    builder.or = jest.fn(() => builder);
    builder.maybeSingle = jest.fn(
      () =>
        new Promise((resolve) =>
          resolve({ data: listingRow, error: null } as { data: Record<string, unknown>; error: null }),
        ),
    );
    builder.then = (resolve: (v: unknown) => void) => resolve({ data: [listingRow], error: null, count: 1 });
    client.storage = {
      from: (bucket: string) => ({
        getPublicUrl: (path: string) => ({
          data: { publicUrl: `https://supabase.test/storage/v1/object/public/${bucket}/${path}` },
        }),
      }),
    };
    return client;
  }

  async function serviceWith(row: Record<string, unknown>): Promise<MarketplaceService> {
    const moduleRef = await Test.createTestingModule({
      providers: [
        MarketplaceService,
        GeminiReviewService,
        { provide: ConfigService, useValue: { get: () => 'x' } },
        { provide: SearchService, useValue: {} },
        { provide: SUPABASE_CLIENT, useValue: fakeSupabaseWithListing(row) },
      ],
    }).compile();
    return moduleRef.get(MarketplaceService);
  }

  it('listPublic: image_urls positionssortiert, rohes images-Embed entfernt', async () => {
    const service = await serviceWith({
      id: 'l1',
      seller_id: 's1',
      title: 'Auspuff',
      images: [
        { storage_path: 's/l/1.jpg', position: 1 },
        { storage_path: 's/l/0.jpg', position: 0 },
      ],
    });

    const res = await service.listPublic({});
    const row = res.listings[0];

    expect(row['images']).toBeUndefined();
    expect(row['image_urls']).toEqual([
      'https://supabase.test/storage/v1/object/public/marketplace-photos/s/l/0.jpg',
      'https://supabase.test/storage/v1/object/public/marketplace-photos/s/l/1.jpg',
    ]);
  });

  it('listPublic: Listing ohne Bilder -> leeres image_urls (kein crash)', async () => {
    const service = await serviceWith({ id: 'l2', seller_id: 's1', title: 'Ohne Fotos' });

    const res = await service.listPublic({});
    expect(res.listings[0]['image_urls']).toEqual([]);
  });

  it('getPublicListing: gleicher Vertrag für die Detail-Ansicht', async () => {
    const service = await serviceWith({
      id: 'l3',
      seller_id: 's1',
      title: 'Detail',
      status: 'active',
      review_status: 'approved',
      images: [{ storage_path: 's/l/0.webp', position: 0 }],
    });

    const row = await service.getPublicListing('l3');
    expect(row['images']).toBeUndefined();
    expect(row['image_urls']).toEqual([
      'https://supabase.test/storage/v1/object/public/marketplace-photos/s/l/0.webp',
    ]);
  });
});
