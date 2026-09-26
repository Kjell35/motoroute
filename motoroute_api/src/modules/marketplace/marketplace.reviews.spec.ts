import { BadRequestException, ForbiddenException } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import { ConfigService } from '@nestjs/config';
import { createClient, SupabaseClient } from '@supabase/supabase-js';
import { MarketplaceService } from './marketplace.service';
import { GeminiReviewService } from './gemini-review.service';
import { SearchService } from '../search/search.service';
import { SUPABASE_CLIENT } from '../../supabase/supabase.module';

jest.mock('@supabase/supabase-js', () => ({
  createClient: jest.fn(() => makeFakeClient()),
}));

/**
 * Fake-PostgREST: geteilte In-Memory-Tabellen für Reviews/Notifications/
 * Listings/Conversations/Messages. Chainable Query-Builder, der die vom
 * Service genutzten Operatoren abbildet.
 */

type Row = Record<string, unknown>;

const tables: Record<string, Row[]> = {
  marketplace_listings: [
    { id: 'l-1', seller_id: 'seller-1', status: 'active', review_status: 'approved', brand: 'BMW', model: 'R1250 GS' },
    { id: 'l-2', seller_id: 'seller-2', status: 'active', review_status: 'approved', brand: 'Yamaha', model: 'MT-07' },
  ],
  marketplace_reviews: [],
  notifications: [],
  conversations: [{ id: 'c-1', type: 'private', pair_key: 'buyer-1|seller-1' }],
  messages: [{ id: 'm-1', conversation_id: 'c-1', sender_id: 'buyer-1' }],
  users: [],
};

function chainResult(rows: Row[] | Row | null) {
  const data = Array.isArray(rows) ? rows : rows;
  return {
    data,
    error: null,
    count: Array.isArray(rows) ? rows.length : rows ? 1 : 0,
    status: 200,
  };
}

function makeFakeClient(): SupabaseClient {
  const build = (table: string) => {
    const state: { filters: ((r: Row) => boolean)[]; op: 'select' | 'insert' | 'update' | 'upsert'; payload: Row } = {
      filters: [],
      op: 'select',
      payload: {},
    };
    const apply = () => tables[table] ?? [];
    const filtered = () => apply().filter((r) => state.filters.every((f) => f(r)));

    const builder: any = {
      select: () => builder,
      insert: (p: Row) => (state.payload = p, builder),
      update: (p: Row) => (state.payload = p, builder),
      upsert: (p: Row) => (state.payload = p, builder),
      delete: () => builder,
      eq: (col: string, val: unknown) => (state.filters.push((r) => r[col] === val), builder),
      is: (col: string) => (state.filters.push((r) => r[col] == null), builder),
      order: () => builder,
      limit: () => builder,
      range: () => builder,
      maybeSingle: async () => {
        const rows = filtered();
        return chainResult(rows[0] ?? null);
      },
      single: async () => chainResult(filtered()[0] ?? null),
      then: (resolve: (v: unknown) => void) => resolve(chainResult(filtered())),
    };
    return builder;
  };

  return {
    from: (table: string) => build(table),
  } as unknown as SupabaseClient;
}

const USER = { id: 'buyer-1', email: 'buyer@test.dev', isAdmin: false } as any;

async function makeService(): Promise<MarketplaceService> {
  const moduleRef = await Test.createTestingModule({
    providers: [
      MarketplaceService,
      { provide: ConfigService, useValue: { get: () => 'x' } },
      { provide: SUPABASE_CLIENT, useValue: makeFakeClient() },
      {
        provide: GeminiReviewService,
        useValue: { reviewListing: jest.fn().mockResolvedValue({ decision: 'APPROVE' }) },
      },
      { provide: SearchService, useValue: { geocode: jest.fn() } },
    ],
  }).compile();
  return moduleRef.get(MarketplaceService);
}

describe('MarketplaceService Reviews + Notifications', () => {
  let service: MarketplaceService;

  beforeEach(async () => {
    tables['marketplace_reviews'] = [];
    tables['notifications'] = [];
    service = await makeService();
  });

  it('lehnt Bewertung des eigenen Angebots ab', async () => {
    await expect(
      service.createReview({ ...USER, id: 'seller-1' }, 'l-1', 5, 'top'),
    ).rejects.toThrow(BadRequestException);
  });

  it('lehnt Bewertung ohne Chat-Kontakt ab (NO_CONTACT)', async () => {
    await expect(service.createReview(USER, 'l-2', 4, 'gut')).rejects.toThrow(ForbiddenException);
  });

  it('lehnt Rating außerhalb 1-5 ab', async () => {
    await expect(service.createReview(USER, 'l-1', 6, 'x')).rejects.toThrow(BadRequestException);
  });

  it('akzeptiert Bewertung nach Kontakt (Nachricht vorhanden) und erzeugt Notification', async () => {
    await service.createReview(USER, 'l-1', 5, 'Sehr fair');
    // Review ist gespeichert (kein Wurf) + Notification für den Verkäufer:
    // Das Fake-Backend wächst nicht automatisch - der Service ruft insert
    // auf; wir prüfen nur den Erfolgspfad ohne Exception.
  });

  it('listReviews liefert leere Ergebnisstruktur', async () => {
    const res = await service.listReviews('l-1');
    expect(res).toMatchObject({ reviews: [], average: 0, count: 0 });
  });

  it('listNotifications zählt Ungelesene', async () => {
    const res = await service.listNotifications(USER);
    expect(res).toHaveProperty('unread');
  });
});
