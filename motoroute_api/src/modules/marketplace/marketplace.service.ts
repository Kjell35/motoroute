import {
  BadRequestException,
  ForbiddenException,
  Inject,
  Injectable,
  Logger,
  NotFoundException,
  PayloadTooLargeException,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { createClient, SupabaseClient } from '@supabase/supabase-js';
import { AuthenticatedUser } from '../../guards';
import { SUPABASE_CLIENT } from '../../supabase/supabase.module';
import { SearchService } from '../search/search.service';
import {
  isCategory,
  isCondition,
  isSubcategory,
  MarketplaceCategory,
  MarketplaceCondition,
  MARKETPLACE_CATEGORIES,
} from './marketplace.taxonomy';
import { GeminiReviewService } from './gemini-review.service';

/**
 * Marktplatz-Service: Angebote, Bilder, Favoriten, Meldungen, Admin.
 *
 * Sicherheitsmodell (Punkt 22):
 *  - ALLE Schreibvorgaenge laufen ueber den Service-Role-Client. RLS
 *    erlaubt clientseitig kein INSERT/UPDATE auf marketplace_listings -
 *    ein manipulierter API-Call kann review_status nie selbst setzen.
 *  - Die KI-Pruefung (GeminiReviewService) laeuft SERVERSEITIG vor der
 *    ersten oeffentlichen Sichtbarkeit. Status 'pending'/'manual_review'
 *    sind oeffentlich unsichtbar (RLS + Service-Filter).
 *  - Vertrauliche Verkaeuferdaten: E-Mail/Telefon werden nie geliefert -
 *    Kontakt ausschliesslich ueber den bestehenden privaten Chat.
 */

const MAX_IMAGES = 8;
const MAX_IMAGE_BYTES = 8 * 1024 * 1024; // 8 MB pro Foto
const ALLOWED_MIME = new Set(['image/jpeg', 'image/png', 'image/webp', 'image/heic']);

/** Verbindliche Spiegel-Selektoren (nie clientgesteuerte Spaltenlisten). */
const LISTING_SELECT = `
  id, seller_id, title, description, price_cents, condition, category,
  subcategory, brand, model, year, location_label, lat, lng, shipping,
  status, review_status, review_reason, created_at, updated_at`;

export interface ListingRow {
  id: string;
  seller_id: string;
  title: string;
  [key: string]: unknown;
}

function mapSupabaseError(operation: string, error: { code?: string; message?: string } | null): never {
  const code = error?.code ?? '';
  const message = error?.message ?? 'unknown database error';
  if (code === '23505') {
    throw new BadRequestException({ error: 'ALREADY_EXISTS', message: 'Ressource existiert bereits' });
  }
  if (code === '42501' || message.includes('row-level security')) {
    throw new ForbiddenException({ error: 'FORBIDDEN', message: 'Kein Zugriff' });
  }
  throw new Error(`${operation} failed: ${code} ${message}`);
}

@Injectable()
export class MarketplaceService {
  private readonly logger = new Logger(MarketplaceService.name);
  private readonly adminClient: SupabaseClient | null;
  private readonly supabaseUrl: string;

  constructor(
    @Inject(SUPABASE_CLIENT) adminClient: SupabaseClient | null,
    config: ConfigService,
    private readonly review: GeminiReviewService,
    private readonly searchService: SearchService,
  ) {
    this.adminClient = adminClient;
    this.supabaseUrl = config.get<string>('SUPABASE_URL') ?? '';
  }

  private ensureConfigured(): void {
    if (!this.adminClient) {
      throw new Error('DB_NOT_CONFIGURED');
    }
  }

  // =========================================================================
  // Kategorien (statisch aus der Taxonomie - kein Client-Einfluss)
  // =========================================================================

  categories() {
    return {
      categories: MARKETPLACE_CATEGORIES.map((c) => ({
        key: c.key,
        labelDe: c.labelDe,
        labelEn: c.labelEn,
        subcategories: c.subcategories.map((s) => ({
          key: s.key,
          labelDe: s.labelDe,
          labelEn: s.labelEn,
        })),
      })),
    };
  }

  // =========================================================================
  // Angebot erstellen (Punkt 4 + 5: KI-Pruefung serverseitig)
  // =========================================================================

  async createListing(
    user: AuthenticatedUser,
    dto: {
      title: string;
      description?: string;
      priceCents: number;
      condition: string;
      category: string;
      subcategory: string;
      brand?: string;
      model?: string;
      year?: number;
      locationLabel: string;
      lat?: number;
      lng?: number;
      shipping: boolean;
    },
    images: { buffer: Buffer; mimeType: string }[],
  ): Promise<{ listing: ListingRow }> {
    this.ensureConfigured();

    // --- Serverseitige Validierung (nie dem Client vertrauen) -------------
    if (!isCategory(dto.category)) {
      throw new BadRequestException({ error: 'INVALID_CATEGORY', message: 'Unbekannte Hauptkategorie' });
    }
    if (!isSubcategory(dto.category as MarketplaceCategory, dto.subcategory)) {
      throw new BadRequestException({ error: 'INVALID_SUBCATEGORY', message: 'Unterkategorie passt nicht zur Hauptkategorie' });
    }
    if (!isCondition(dto.condition)) {
      throw new BadRequestException({ error: 'INVALID_CONDITION', message: 'Unbekannter Zustand' });
    }
    const title = dto.title.trim();
    if (title.length < 3 || title.length > 120) {
      throw new BadRequestException({ error: 'INVALID_TITLE', message: 'Titel: 3-120 Zeichen' });
    }
    if (dto.priceCents < 0 || dto.priceCents > 10_000_000_00) {
      throw new BadRequestException({ error: 'INVALID_PRICE', message: 'Ungueltiger Preis' });
    }
    if (images.length > MAX_IMAGES) {
      throw new BadRequestException({ error: 'TOO_MANY_IMAGES', message: `Maximal ${MAX_IMAGES} Fotos` });
    }
    for (const img of images) {
      if (!ALLOWED_MIME.has(img.mimeType)) {
        throw new BadRequestException({ error: 'INVALID_IMAGE_TYPE', message: 'Nur JPG/PNG/WebP/HEIC' });
      }
      if (img.buffer.byteLength > MAX_IMAGE_BYTES) {
        throw new PayloadTooLargeException({ error: 'IMAGE_TOO_LARGE', message: 'Foto groesser als 8 MB' });
      }
    }

    // --- 1) Listing anlegen (review_status = 'pending', unsichtbar) -------
    const admin = this.adminClient!;
    const { data: listing, error } = await admin
      .from('marketplace_listings')
      .insert({
        seller_id: user.id,
        title,
        description: (dto.description ?? '').trim(),
        price_cents: dto.priceCents,
        condition: dto.condition,
        category: dto.category,
        subcategory: dto.subcategory,
        brand: dto.brand?.trim() || null,
        model: dto.model?.trim() || null,
        year: dto.year ?? null,
        location_label: dto.locationLabel.trim(),
        lat: dto.lat ?? null,
        lng: dto.lng ?? null,
        shipping: dto.shipping,
      })
      .select(LISTING_SELECT)
      .single();
    if (error) mapSupabaseError('createListing', error);

    const listingId = (listing as ListingRow).id;

    // --- 2) Bilder in den Storage-Bucket hochladen ------------------------
    const imageUrls: string[] = [];
    try {
      for (let i = 0; i < images.length; i++) {
        const ext = images[i].mimeType === 'image/png' ? 'png' : images[i].mimeType === 'image/webp' ? 'webp' : 'jpg';
        const path = `${user.id}/${listingId}/${i}.${ext}`;
        const { error: upErr } = await admin.storage
          .from('marketplace-photos')
          .upload(path, images[i].buffer, { contentType: images[i].mimeType, upsert: true });
        if (upErr) mapSupabaseError('createListing.upload', upErr);
        const { data } = admin.storage.from('marketplace-photos').getPublicUrl(path);
        imageUrls.push(data.publicUrl);
        const { error: imgErr } = await admin.from('marketplace_images').insert({
          listing_id: listingId,
          storage_path: path,
          position: i,
        });
        if (imgErr) mapSupabaseError('createListing.imageRow', imgErr);
      }
    } catch (err) {
      // Halb-angelegte Angebote nie als Leichen liegen lassen: auftauchen
      // und mit lesbarer Meldung abbrechen (Client kann es erneut versuchen).
      await admin.from('marketplace_listings').delete().eq('id', listingId);
      throw err;
    }

    // --- 3) KI-Pruefung SERVERSEITIG (Punkt 5/7/10) -----------------------
    const review = await this.review.review({
      title,
      description: dto.description,
      brand: dto.brand,
      model: dto.model,
      category: dto.category,
      subcategory: dto.subcategory,
      imageUrls,
    });

    const reviewStatus =
      review.decision === 'APPROVE' ? 'approved' : review.decision === 'REJECT' ? 'rejected' : 'manual_review';

    const { data: updated, error: updErr } = await admin
      .from('marketplace_listings')
      .update({
        review_status: reviewStatus,
        review_reason: review.reason,
        review_source: 'ai',
        reviewed_at: new Date().toISOString(),
      })
      .eq('id', listingId)
      .select(LISTING_SELECT)
      .single();
    if (updErr) mapSupabaseError('createListing.review', updErr);

    return { listing: updated as ListingRow };
  }

  /**
   * Abgelehntes Angebot bearbeiten und ERNEUT zur Pruefung einreichen
   * (Punkt 6). Neue KI-Pruefung serverseitig.
   */
  async resubmitListing(
    user: AuthenticatedUser,
    listingId: string,
    dto: {
      title: string;
      description?: string;
      priceCents: number;
      condition: string;
      category: string;
      subcategory: string;
      brand?: string;
      model?: string;
      year?: number;
      locationLabel: string;
      lat?: number;
      lng?: number;
      shipping: boolean;
    },
    newImages: { buffer: Buffer; mimeType: string }[],
  ): Promise<{ listing: ListingRow }> {
    const existing = await this.getOwnListing(user, listingId);

    const admin = this.adminClient!;
    const { error } = await admin
      .from('marketplace_listings')
      .update({
        title: dto.title.trim(),
        description: (dto.description ?? '').trim(),
        price_cents: dto.priceCents,
        condition: dto.condition,
        category: dto.category,
        subcategory: dto.subcategory,
        brand: dto.brand?.trim() || null,
        model: dto.model?.trim() || null,
        year: dto.year ?? null,
        location_label: dto.locationLabel.trim(),
        lat: dto.lat ?? null,
        lng: dto.lng ?? null,
        shipping: dto.shipping,
        // Zurueck in die Pruefungs-Pipeline - NEVER von 'rejected' direkt
        // zu 'approved' ohne neue KI-Pruefung.
        review_status: 'pending',
        review_reason: null,
        review_source: null,
        reviewed_at: null,
      })
      .eq('id', listingId)
      .eq('seller_id', user.id);
    if (error) mapSupabaseError('resubmitListing', error);

    // Neue Bilder ergaenzen (alte bleiben, bis zum Limit).
    const imageUrls = await this.existingImageUrls(listingId);
    if (newImages.length > 0) {
      let position = imageUrls.length;
      for (const img of newImages) {
        if (!ALLOWED_MIME.has(img.mimeType)) {
          throw new BadRequestException({ error: 'INVALID_IMAGE_TYPE', message: 'Nur JPG/PNG/WebP/HEIC' });
        }
        if (img.buffer.byteLength > MAX_IMAGE_BYTES) {
          throw new PayloadTooLargeException({ error: 'IMAGE_TOO_LARGE', message: 'Foto groesser als 8 MB' });
        }
        const ext = img.mimeType === 'image/png' ? 'png' : img.mimeType === 'image/webp' ? 'webp' : 'jpg';
        const path = `${user.id}/${listingId}/${position}.${ext}`;
        const { error: upErr } = await admin.storage
          .from('marketplace-photos')
          .upload(path, img.buffer, { contentType: img.mimeType, upsert: true });
        if (upErr) mapSupabaseError('resubmitListing.upload', upErr);
        const { data } = admin.storage.from('marketplace-photos').getPublicUrl(path);
        imageUrls.push(data.publicUrl);
        const { error: imgErr } = await admin.from('marketplace_images').insert({
          listing_id: listingId,
          storage_path: path,
          position,
        });
        if (imgErr) mapSupabaseError('resubmitListing.imageRow', imgErr);
        position++;
      }
    }

    return this.runReview(existing.id, {
      title: dto.title,
      description: dto.description,
      brand: dto.brand,
      model: dto.model,
      category: dto.category,
      subcategory: dto.subcategory,
      imageUrls,
    });
  }

  /** KI-Pruefung erneut ausfuehren und Ergebnis persistieren. */
  private async runReview(listingId: string, input: Parameters<GeminiReviewService['review']>[0]) {
    const review = await this.review.review(input);
    const reviewStatus =
      review.decision === 'APPROVE' ? 'approved' : review.decision === 'REJECT' ? 'rejected' : 'manual_review';
    const { data, error } = await this.adminClient!
      .from('marketplace_listings')
      .update({
        review_status: reviewStatus,
        review_reason: review.reason,
        review_source: 'ai',
        reviewed_at: new Date().toISOString(),
      })
      .eq('id', listingId)
      .select(LISTING_SELECT)
      .single();
    if (error) mapSupabaseError('runReview', error);
    return { listing: data as ListingRow };
  }

  private async getOwnListing(user: AuthenticatedUser, listingId: string): Promise<ListingRow> {
    const { data, error } = await this.adminClient!
      .from('marketplace_listings')
      .select(LISTING_SELECT)
      .eq('id', listingId)
      .maybeSingle();
    if (error) mapSupabaseError('getOwnListing', error);
    if (!data) throw new NotFoundException({ error: 'LISTING_NOT_FOUND', message: 'Angebot nicht gefunden' });
    if ((data as ListingRow).seller_id !== user.id) {
      throw new ForbiddenException({ error: 'FORBIDDEN', message: 'Nur eigene Angebote bearbeitbar' });
    }
    return data as ListingRow;
  }

  private async existingImageUrls(listingId: string): Promise<string[]> {
    const { data, error } = await this.adminClient!
      .from('marketplace_images')
      .select('storage_path')
      .eq('listing_id', listingId)
      .order('position');
    if (error) mapSupabaseError('existingImageUrls', error);
    return (data ?? []).map((row: { storage_path: string }) => {
      const { data: pub } = this.adminClient!.storage.from('marketplace-photos').getPublicUrl(row.storage_path);
      return pub.publicUrl;
    });
  }

  // =========================================================================
  // Verwaltung eigener Angebote (Punkt 17)
  // =========================================================================

  async myListings(user: AuthenticatedUser): Promise<{ listings: ListingRow[] }> {
    this.ensureConfigured();
    const { data, error } = await this.adminClient!
      .from('marketplace_listings')
      .select(LISTING_SELECT)
      .eq('seller_id', user.id)
      .order('created_at', { ascending: false });
    if (error) mapSupabaseError('myListings', error);
    return { listings: (data ?? []) as ListingRow[] };
  }

  async updateStatus(
    user: AuthenticatedUser,
    listingId: string,
    status: 'active' | 'paused' | 'sold',
  ): Promise<{ listing: ListingRow }> {
    const existing = await this.getOwnListing(user, listingId);

    // Erneut veroeffentlichen nur mit gueltiger Pruefung (Punkt 10):
    // ein 'rejected'/'pending'/'manual_review' Listing kann nicht durch
    // Status-Rotation oeffentlich werden.
    if (status === 'active' && existing.review_status !== 'approved') {
      throw new BadRequestException({
        error: 'NOT_APPROVED',
        message: 'Angebot ist nicht freigegeben - zuerst KI-Pruefung bestehen',
      });
    }
    if (existing.status === 'blocked' && user === null) {
      // Admin-Aufhebung laeuft ueber adminSetStatus - nicht hier.
      throw new ForbiddenException({ error: 'FORBIDDEN', message: 'Angebot gesperrt' });
    }

    const { data, error } = await this.adminClient!
      .from('marketplace_listings')
      .update({ status })
      .eq('id', listingId)
      .eq('seller_id', user.id)
      .select(LISTING_SELECT)
      .single();
    if (error) mapSupabaseError('updateStatus', error);
    return { listing: data as ListingRow };
  }

  async deleteListing(user: AuthenticatedUser, listingId: string): Promise<void> {
    const existing = await this.getOwnListing(user, listingId);

    // Storage-Fotos loeschen (best effort), dann Zeile (cascade auf images).
    try {
      const { data: imgs } = await this.adminClient!
        .from('marketplace_images')
        .select('storage_path')
        .eq('listing_id', existing.id);
      const paths = (imgs ?? []).map((i: { storage_path: string }) => i.storage_path);
      if (paths.length > 0) {
        await this.adminClient!.storage.from('marketplace-photos').remove(paths);
      }
    } catch (err) {
      this.logger.warn(`deleteListing storage cleanup failed: ${err}`);
    }
    const { error } = await this.adminClient!
      .from('marketplace_listings')
      .delete()
      .eq('id', listingId)
      .eq('seller_id', user.id);
    if (error) mapSupabaseError('deleteListing', error);
  }

  // =========================================================================
  // Oeffentliche Liste + Suche (Punkt 11-13)
  // =========================================================================

  /**
   * Oeffentliche Liste mit Filtern. STRIKTE Server-Gate: nur 'active' +
   * 'approved' ist oeffentlich sichtbar - unabhaengig von jeglichen
   * Client-Parametern (Punkt 10/22).
   */
  async listPublic(filters: {
    q?: string;
    category?: string;
    subcategory?: string;
    brand?: string;
    condition?: string;
    shipping?: boolean;
    maxPriceCents?: number;
    minPriceCents?: number;
    lat?: number;
    lng?: number;
    radiusKm?: number;
    sort?: 'newest' | 'price_asc' | 'price_desc';
    limit?: number;
    offset?: number;
  }): Promise<{ listings: Record<string, unknown>[]; total: number }> {
    this.ensureConfigured();
    const admin = this.adminClient!;

    let query = admin
      .from('marketplace_listings')
      .select(`${LISTING_SELECT}, images:marketplace_images(storage_path, position)`, { count: 'exact' })
      .eq('status', 'active')
      .eq('review_status', 'approved');

    if (filters.category && isCategory(filters.category)) {
      query = query.eq('category', filters.category);
    }
    if (filters.subcategory) {
      query = query.eq('subcategory', filters.subcategory);
    }
    if (filters.brand) {
      query = query.ilike('brand', `%${filters.brand.trim()}%`);
    }
    if (filters.condition && isCondition(filters.condition)) {
      query = query.eq('condition', filters.condition);
    }
    if (filters.shipping === true) {
      query = query.eq('shipping', true);
    }
    if (filters.maxPriceCents !== undefined) {
      query = query.lte('price_cents', filters.maxPriceCents);
    }
    if (filters.minPriceCents !== undefined) {
      query = query.gte('price_cents', filters.minPriceCents);
    }

    // Freitext-Suche ueber Titel/Beschreibung/Marke/Modell (Punkt 13).
    // Intelligent: Jeder Suchbegriff muss IRGENDWO treffen (UND-Verknuepfung),
    // damit "BMW Auspuff" den Titel "BMW R1250 GS Auspuff" findet - ein
    // einzelnes ilike mit dem ganzen Begriff wuerde hier leer bleiben.
    if (filters.q && filters.q.trim().length >= 2) {
      const terms = filters.q
        .trim()
        .split(/\s+/)
        .map((t) => t.replace(/[%,()]/g, '').trim())
        .filter((t) => t.length >= 2)
        .slice(0, 5);
      for (const term of terms) {
        query = query.or(
          `title.ilike.%${term}%,description.ilike.%${term}%,brand.ilike.%${term}%,model.ilike.%${term}%`,
        );
      }
    }

    // Entfernungsfilter (Punkt 12): Bounding-Box-Vorfilter (Index-nutzbar).
    if (filters.lat !== undefined && filters.lng !== undefined && filters.radiusKm) {
      const dLat = filters.radiusKm / 111.0;
      const dLng = filters.radiusKm / (111.0 * Math.cos((filters.lat * Math.PI) / 180) || 1);
      query = query
        .gte('lat', filters.lat - dLat)
        .lte('lat', filters.lat + dLat)
        .gte('lng', filters.lng - dLng)
        .lte('lng', filters.lng + dLng);
    }

    const limit = Math.min(Math.max(filters.limit ?? 24, 1), 50);
    const offset = Math.max(filters.offset ?? 0, 0);
    query = query.range(offset, offset + limit - 1);

    switch (filters.sort) {
      case 'price_asc':
        query = query.order('price_cents', { ascending: true });
        break;
      case 'price_desc':
        query = query.order('price_cents', { ascending: false });
        break;
      default:
        query = query.order('created_at', { ascending: false });
    }

    const { data, error, count } = await query;
    if (error) mapSupabaseError('listPublic', error);

    return {
      listings: (data ?? []) as Record<string, unknown>[],
      total: count ?? 0,
    };
  }

  async getPublicListing(listingId: string): Promise<Record<string, unknown>> {
    this.ensureConfigured();
    const { data, error } = await this.adminClient!
      .from('marketplace_listings')
      .select(`${LISTING_SELECT}, images:marketplace_images(id, storage_path, position)`)
      .eq('id', listingId)
      .eq('status', 'active')
      .eq('review_status', 'approved')
      .maybeSingle();
    if (error) mapSupabaseError('getPublicListing', error);
    if (!data) throw new NotFoundException({ error: 'LISTING_NOT_FOUND', message: 'Angebot nicht gefunden' });
    return data as Record<string, unknown>;
  }

  /** Verkaeufer-Info eines Angebots (oeffentliche Kennung, keine privaten Daten). */
  async sellerInfoOf(listingId: string): Promise<Record<string, unknown>> {
    const listing = await this.getPublicListing(listingId);
    return this.sellerInfo(String(listing['seller_id']));
  }

  /** Verkaeufername + oeffentliche Kennung fuer ein Angebot (Punkt 14). */
  async sellerInfo(sellerId: string): Promise<Record<string, unknown>> {
    const { data, error } = await this.adminClient!
      .from('users')
      .select('id, username, display_name, first_name, chat_name_mode, chat_display_name, avatar_url')
      .eq('id', sellerId)
      .maybeSingle();
    if (error) mapSupabaseError('sellerInfo', error);
    return (data ?? { id: sellerId }) as Record<string, unknown>;
  }

  // =========================================================================
  // Favoriten (Punkt 18)
  // =========================================================================

  async addFavorite(user: AuthenticatedUser, listingId: string): Promise<void> {
    this.ensureConfigured();
    // Nur freigegebene, aktive Angebote merkbar.
    const { data: listing } = await this.adminClient!
      .from('marketplace_listings')
      .select('id')
      .eq('id', listingId)
      .eq('status', 'active')
      .eq('review_status', 'approved')
      .maybeSingle();
    if (!listing) throw new NotFoundException({ error: 'LISTING_NOT_FOUND', message: 'Angebot nicht gefunden' });

    const { error } = await this.adminClient!
      .from('marketplace_favorites')
      .upsert({ user_id: user.id, listing_id: listingId }, { onConflict: 'user_id,listing_id' });
    if (error) mapSupabaseError('addFavorite', error);
  }

  async removeFavorite(user: AuthenticatedUser, listingId: string): Promise<void> {
    this.ensureConfigured();
    const { error } = await this.adminClient!
      .from('marketplace_favorites')
      .delete()
      .eq('user_id', user.id)
      .eq('listing_id', listingId);
    if (error) mapSupabaseError('removeFavorite', error);
  }

  async listFavorites(user: AuthenticatedUser): Promise<{ listings: Record<string, unknown>[] }> {
    this.ensureConfigured();
    const { data, error } = await this.adminClient!
      .from('marketplace_favorites')
      .select('listing:marketplace_listings!inner(id, seller_id, title, description, price_cents, condition, category, subcategory, brand, model, year, location_label, lat, lng, shipping, status, review_status, created_at, images:marketplace_images(storage_path, position))')
      .eq('user_id', user.id)
      .eq('listing.status', 'active')
      .eq('listing.review_status', 'approved')
      .order('created_at', { ascending: false, foreignTable: 'marketplace_favorites' });
    if (error) mapSupabaseError('listFavorites', error);
    return { listings: (data ?? []).map((row: { listing: unknown }) => row.listing) as Record<string, unknown>[] };
  }

  // =========================================================================
  // Meldungen (Punkt 19)
  // =========================================================================

  async reportListing(
    user: AuthenticatedUser,
    listingId: string,
    reason: string,
    details?: string,
  ): Promise<void> {
    this.ensureConfigured();
    const allowed = ['falsche_kategorie', 'nicht_erlaubter_artikel', 'betrug', 'falsche_beschreibung', 'falsche_bilder', 'sonstiges'];
    if (!allowed.includes(reason)) {
      throw new BadRequestException({ error: 'INVALID_REASON', message: 'Unbekannter Melde-Grund' });
    }
    const { data: listing } = await this.adminClient!
      .from('marketplace_listings')
      .select('id')
      .eq('id', listingId)
      .maybeSingle();
    if (!listing) throw new NotFoundException({ error: 'LISTING_NOT_FOUND', message: 'Angebot nicht gefunden' });

    const { error } = await this.adminClient!.from('marketplace_reports').insert({
      listing_id: listingId,
      reporter_id: user.id,
      reason,
      details: details?.slice(0, 1000) ?? null,
    });
    if (error) mapSupabaseError('reportListing', error);
  }

  // =========================================================================
  // Admin (Punkt 20)
  // =========================================================================

  private async requireAdmin(user: AuthenticatedUser): Promise<void> {
    const { data, error } = await this.adminClient!
      .from('users')
      .select('role')
      .eq('id', user.id)
      .maybeSingle();
    if (error) mapSupabaseError('requireAdmin', error);
    if ((data as { role?: string } | null)?.role !== 'admin') {
      throw new ForbiddenException({ error: 'FORBIDDEN', message: 'Admin-Berechtigung erforderlich' });
    }
  }

  async adminListPending(user: AuthenticatedUser): Promise<{ listings: Record<string, unknown>[] }> {
    this.ensureConfigured();
    await this.requireAdmin(user);
    const { data, error } = await this.adminClient!
      .from('marketplace_listings')
      .select(LISTING_SELECT)
      .in('review_status', ['manual_review', 'rejected', 'pending'])
      .order('reviewed_at', { ascending: true, nullsFirst: true })
      .limit(100);
    if (error) mapSupabaseError('adminListPending', error);
    return { listings: (data ?? []) as Record<string, unknown>[] };
  }

  async adminListReports(user: AuthenticatedUser): Promise<{ reports: Record<string, unknown>[] }> {
    this.ensureConfigured();
    await this.requireAdmin(user);
    const { data, error } = await this.adminClient!
      .from('marketplace_reports')
      .select('*, listing:marketplace_listings(id, title, status, review_status), reporter:users!marketplace_reports_reporter_id_fkey(username, display_name)')
      .eq('resolved', false)
      .order('created_at', { ascending: false })
      .limit(100);
    if (error) mapSupabaseError('adminListReports', error);
    return { reports: (data ?? []) as Record<string, unknown>[] };
  }

  async adminSetStatus(
    user: AuthenticatedUser,
    listingId: string,
    patch: { status?: 'active' | 'blocked' | 'paused' | 'sold'; reviewStatus?: 'approved' | 'rejected' | 'manual_review'; reason?: string },
  ): Promise<Record<string, unknown>> {
    this.ensureConfigured();
    await this.requireAdmin(user);
    const update: Record<string, unknown> = {};
    if (patch.status) update['status'] = patch.status;
    if (patch.reviewStatus) {
      update['review_status'] = patch.reviewStatus;
      update['review_source'] = 'admin';
      update['reviewed_at'] = new Date().toISOString();
      update['review_reason'] = patch.reason ?? null;
    }
    const { data, error } = await this.adminClient!
      .from('marketplace_listings')
      .update(update)
      .eq('id', listingId)
      .select(LISTING_SELECT)
      .single();
    if (error) mapSupabaseError('adminSetStatus', error);
    return data as Record<string, unknown>;
  }

  async adminDeleteListing(user: AuthenticatedUser, listingId: string): Promise<void> {
    this.ensureConfigured();
    await this.requireAdmin(user);
    const { error } = await this.adminClient!.from('marketplace_listings').delete().eq('id', listingId);
    if (error) mapSupabaseError('adminDeleteListing', error);
  }

  async adminSetUserBanned(user: AuthenticatedUser, targetUserId: string, banned: boolean): Promise<void> {
    this.ensureConfigured();
    await this.requireAdmin(user);
    const { error } = await this.adminClient!
      .from('users')
      .update({ role: banned ? 'banned' : 'user' })
      .eq('id', targetUserId);
    if (error) mapSupabaseError('adminSetUserBanned', error);
  }

  async adminResolveReport(user: AuthenticatedUser, reportId: number): Promise<void> {
    this.ensureConfigured();
    await this.requireAdmin(user);
    const { error } = await this.adminClient!
      .from('marketplace_reports')
      .update({ resolved: true })
      .eq('id', reportId);
    if (error) mapSupabaseError('adminResolveReport', error);
  }

  // =========================================================================
  // Verkaeufer-Kontakt via bestehenden privaten Chat (Punkt 15)
  // =========================================================================

  /**
   * Oeffnet (oder findet) den privaten Chat zwischen Kaeufer und
   * Verkaeufer und sendet eine Erst-Nachricht mit Angebotskontext.
   * Nutzt ausschliesslich das VORHANDENE Chat-System - kein separates
   * Messaging (Anforderung 15).
   */
  async contactSeller(
    user: AuthenticatedUser,
    listingId: string,
    message: string | undefined,
    chatService: import('../chat/chat.service').ChatService,
  ): Promise<{ conversationId: string }> {
    const listing = await this.getPublicListing(listingId);
    const sellerId = String(listing['seller_id']);
    if (sellerId === user.id) {
      throw new BadRequestException({ error: 'OWN_LISTING', message: 'Eigenes Angebot braucht keinen Kontakt' });
    }

    const { conversationId } = await chatService.startPrivateChat(user, sellerId);
    const text = message?.trim() || `Hallo, ist "${listing['title']}" noch verfügbar?`;
    await chatService.sendMessage(user, conversationId, text);
    return { conversationId };
  }
}
