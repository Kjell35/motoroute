import { Body, Controller, Delete, Get, HttpCode, HttpStatus, Inject, Param, Post, Put, Query, Req, UseGuards, UseInterceptors, UploadedFiles } from '@nestjs/common';
import { AnyFilesInterceptor } from '@nestjs/platform-express';
import type { Express } from 'express';
import { Transform, Type } from 'class-transformer';
import { AuthProvider, AuthenticatedRequest } from '../../guards';
import { MarketplaceService } from './marketplace.service';
import { ChatService } from '../chat/chat.service';
import {
  IsBoolean,
  IsInt,
  IsLatitude,
  IsLongitude,
  IsOptional,
  IsString,
  Length,
  Max,
  MaxLength,
  Min,
} from 'class-validator';

/**
 * Marktplatz-REST-Endpunkte (/v1/marketplace). Alle schreibenden
 * Operationen erfordern Auth; die KI-Pruefung passiert serverseitig
 * vor jeder oeffentlichen Sichtbarkeit.
 */

class CreateListingDto {
  @IsString()
  @Length(3, 120)
  title!: string;

  @IsOptional()
  @IsString()
  @MaxLength(4000)
  description?: string;

  /** Multipart liefert ALLES als String - explizite Conversion für Zahlen. */
  @Transform(({ value }) => Number(value))
  @IsInt()
  @Min(0)
  @Max(1_000_000_00)
  priceCents!: number;

  @IsString()
  condition!: string;

  @IsString()
  category!: string;

  @IsString()
  subcategory!: string;

  @IsOptional()
  @IsString()
  @Length(1, 60)
  brand?: string;

  @IsOptional()
  @IsString()
  @Length(1, 60)
  model?: string;

  @IsOptional()
  @Transform(({ value }) => (value === undefined || value === null || value === '' ? undefined : Math.trunc(Number(value))))
  @IsInt()
  @Min(1900)
  @Max(2100)
  year?: number;

  @IsString()
  @Length(1, 120)
  locationLabel!: string;

  @IsOptional()
  @Transform(({ value }) => (value === undefined || value === '' ? undefined : Number(value)))
  @IsLatitude()
  lat?: number;

  @IsOptional()
  @Transform(({ value }) => (value === undefined || value === '' ? undefined : Number(value)))
  @IsLongitude()
  lng?: number;

  /** Multipart: 'true'/'false' kommen als String an -> vor der Validierung
   *  auf echtes Boolean normalisieren (IsBoolean lehnt Strings ab). */
  @Transform(({ value }) => value === true || value === 'true' || value === '1')
  @IsBoolean()
  shipping!: boolean;
}

class StatusDto {
  @IsString()
  status!: 'active' | 'paused' | 'sold';
}

/** year kommt als String an: nach Number konvertieren. */

class ReportDto {
  @IsString()
  reason!: string;

  @IsOptional()
  @IsString()
  @MaxLength(1000)
  details?: string;
}

class ContactSellerDto {
  @IsOptional()
  @IsString()
  @MaxLength(500)
  message?: string;
}

class ReviewDto {
  @Transform(({ value }) => Number(value))
  @IsInt()
  @Min(1)
  @Max(5)
  rating!: number;

  @IsOptional()
  @IsString()
  @MaxLength(500)
  comment?: string;
}

class AdminPatchDto {
  @IsOptional()
  @IsString()
  status?: 'active' | 'blocked' | 'paused' | 'sold';

  @IsOptional()
  @IsString()
  reviewStatus?: 'approved' | 'rejected' | 'manual_review';

  @IsOptional()
  @IsString()
  @MaxLength(500)
  reason?: string;
}

class BanDto {
  @IsBoolean()
  banned!: boolean;
}

/** Minimales Foto-Shape von Multer (ohne @types/multer-Abhaengigkeit). */
interface UploadedPhoto {
  buffer: Buffer;
  mimetype: string;
  size: number;
}

@UseGuards(AuthProvider)
@Controller('v1/marketplace')
export class MarketplaceController {
  constructor(
    private readonly marketplace: MarketplaceService,
    @Inject(ChatService) private readonly chatService: ChatService,
  ) {}

  /** Kategorien + Unterkategorien (Stamm-Daten fuer das Erstell-Formular). */
  @Get('categories')
  categories() {
    return this.marketplace.categories();
  }

  /** Autovervollständigung: Marken/Modelle aus aktiven Angebot. */
  @Get('suggest')
  suggest(@Query('q') q: string) {
    return this.marketplace.suggest(q ?? '');
  }

  /** Oeffentliche Liste mit Filtern + Suche. */
  @Get('listings')
  list(@Query() query: Record<string, string>) {
    const num = (v: string | undefined): number | undefined =>
      v !== undefined && v !== '' ? Number(v) : undefined;
    return this.marketplace.listPublic({
      q: query['q'],
      category: query['category'],
      subcategory: query['subcategory'],
      brand: query['brand'],
      condition: query['condition'],
      shipping: query['shipping'] === 'true' ? true : undefined,
      minPriceCents: num(query['minPrice']),
      maxPriceCents: num(query['maxPrice']),
      lat: num(query['lat']),
      lng: num(query['lng']),
      radiusKm: num(query['radiusKm']),
      sort: (query['sort'] as 'newest' | 'price_asc' | 'price_desc' | undefined) ?? 'newest',
      limit: num(query['limit']),
      offset: num(query['offset']),
    });
  }

  /** Oeffentliches Detail eines freigegebenen Angebots. */
  @Get('listings/:id')
  get(@Param('id') id: string) {
    return this.marketplace.getPublicListing(id);
  }

  /** Verkaeufer-Info (oeffentliche Kennung, keine privaten Daten). */
  @Get('listings/:id/seller')
  seller(@Param('id') id: string) {
    return this.marketplace.sellerInfoOf(id);
  }

  /** Neues Angebot: multipart mit optionalen Foto-Dateien ("images"). */
  @Post('listings')
  @UseInterceptors(AnyFilesInterceptor({ limits: { files: 8, fileSize: 8 * 1024 * 1024 } }))
  create(@Req() req: AuthenticatedRequest, @Body() dto: CreateListingDto, @UploadedFiles() files: UploadedPhoto[]) {
    const images = (files ?? []).map((f) => ({ buffer: f.buffer, mimeType: f.mimetype }));
    return this.marketplace.createListing(req.user!, dto, images);
  }

  /** Abgelehntes Angebot bearbeiten + erneut einreichen (mit neuen Fotos). */
  @Put('listings/:id')
  @UseInterceptors(AnyFilesInterceptor({ limits: { files: 8, fileSize: 8 * 1024 * 1024 } }))
  resubmit(@Req() req: AuthenticatedRequest, @Param('id') id: string, @Body() dto: CreateListingDto, @UploadedFiles() files: UploadedPhoto[]) {
    const images = (files ?? []).map((f) => ({ buffer: f.buffer, mimeType: f.mimetype }));
    return this.marketplace.resubmitListing(req.user!, id, dto, images);
  }

  // Eigene Angebote
  @Get('me/listings')
  mine(@Req() req: AuthenticatedRequest) {
    return this.marketplace.myListings(req.user!);
  }

  @Put('me/listings/:id/status')
  setStatus(@Req() req: AuthenticatedRequest, @Param('id') id: string, @Body() dto: StatusDto) {
    return this.marketplace.updateStatus(req.user!, id, dto.status);
  }

  @Delete('me/listings/:id')
  delete(@Req() req: AuthenticatedRequest, @Param('id') id: string) {
    return this.marketplace.deleteListing(req.user!, id);
  }

  // Favoriten
  @Get('me/favorites')
  favorites(@Req() req: AuthenticatedRequest) {
    return this.marketplace.listFavorites(req.user!);
  }

  @Post('me/favorites/:listingId')
  addFavorite(@Req() req: AuthenticatedRequest, @Param('listingId') id: string) {
    return this.marketplace.addFavorite(req.user!, id);
  }

  @Delete('me/favorites/:listingId')
  removeFavorite(@Req() req: AuthenticatedRequest, @Param('listingId') id: string) {
    return this.marketplace.removeFavorite(req.user!, id);
  }

  // Meldungen
  @Post('listings/:id/report')
  @HttpCode(HttpStatus.CREATED)
  report(@Req() req: AuthenticatedRequest, @Param('id') id: string, @Body() dto: ReportDto) {
    return this.marketplace.reportListing(req.user!, id, dto.reason, dto.details);
  }

  /** Verkaeufer kontaktieren - erstellt den privaten Chat via ChatService. */
  @Post('listings/:id/contact')
  contact(@Req() req: AuthenticatedRequest, @Param('id') id: string, @Body() dto: ContactSellerDto) {
    return this.marketplace.contactSeller(req.user!, id, dto.message, this.chatService);
  }

  // Bewertungen (Migration 0007)
  @Get('listings/:id/reviews')
  reviews(@Param('id') id: string) {
    return this.marketplace.listReviews(id);
  }

  @Post('listings/:id/reviews')
  @HttpCode(HttpStatus.CREATED)
  createReview(
    @Req() req: AuthenticatedRequest,
    @Param('id') id: string,
    @Body() dto: ReviewDto,
  ) {
    return this.marketplace.createReview(req.user!, id, dto.rating, dto.comment);
  }

  // In-App-Benachrichtigungen
  @Get('notifications')
  notifications(@Req() req: AuthenticatedRequest) {
    return this.marketplace.listNotifications(req.user!);
  }

  @Post('notifications/read-all')
  @HttpCode(HttpStatus.NO_CONTENT)
  notificationsReadAll(@Req() req: AuthenticatedRequest) {
    return this.marketplace.markNotificationsRead(req.user!);
  }

  // Admin
  @Get('admin/pending')
  adminPending(@Req() req: AuthenticatedRequest) {
    return this.marketplace.adminListPending(req.user!);
  }

  @Get('admin/reports')
  adminReports(@Req() req: AuthenticatedRequest) {
    return this.marketplace.adminListReports(req.user!);
  }

  @Put('admin/listings/:id')
  adminPatch(@Req() req: AuthenticatedRequest, @Param('id') id: string, @Body() dto: AdminPatchDto) {
    return this.marketplace.adminSetStatus(req.user!, id, dto);
  }

  @Delete('admin/listings/:id')
  adminDelete(@Req() req: AuthenticatedRequest, @Param('id') id: string) {
    return this.marketplace.adminDeleteListing(req.user!, id);
  }

  @Put('admin/users/:id/ban')
  adminBan(@Req() req: AuthenticatedRequest, @Param('id') id: string, @Body() dto: BanDto) {
    return this.marketplace.adminSetUserBanned(req.user!, id, dto.banned);
  }

  @Put('admin/reports/:id/resolve')
  adminResolve(@Req() req: AuthenticatedRequest, @Param('id') id: string) {
    return this.marketplace.adminResolveReport(req.user!, Number(id));
  }
}
