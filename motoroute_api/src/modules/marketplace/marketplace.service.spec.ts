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
