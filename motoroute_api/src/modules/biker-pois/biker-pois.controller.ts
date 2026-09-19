import { Controller, Get, Query, Req, ServiceUnavailableException, UseGuards } from '@nestjs/common';
import { AuthProvider, AuthenticatedRequest } from '../../guards';
import { BikerPoisService } from './biker-pois.service';
import { IsLatitude, IsLongitude, IsNumber, IsOptional, IsString, Min } from 'class-validator';
import { Type } from 'class-transformer';

export class BikerPoiSyncQueryDto {
  /** ISO-Timestamp des letzten Syncs (erster Aufruf: 1970-01-01T00:00:00Z). */
  @IsString()
  since: string;

  @IsOptional()
  @Type(() => Number)
  @IsLatitude()
  lat?: number;

  @IsOptional()
  @Type(() => Number)
  @IsLongitude()
  lon?: number;

  /** Radius in km um lat/lon. */
  @IsOptional()
  @Type(() => Number)
  @IsNumber()
  @Min(1)
  radiusKm?: number;

  /** Kommagetrennte App-Kategorien (Teilmenge der unterstützten Kategorien). */
  @IsOptional()
  @IsString()
  categories?: string;
}

/**
 * BFF-Endpunkt für den Biker-POI-Delta-Sync. Strikt authentifiziert -
 * der Scan-Dienst kuratiert mit dem TomTom-Key des Betreibers, der
 * Abfluss läuft nur über das eigene, authentifizierte BFF.
 */
@Controller('v1/biker-pois')
@UseGuards(AuthProvider)
export class BikerPoisController {
  constructor(private readonly bikerPois: BikerPoisService) {}

  @Get('sync')
  sync(@Req() req: AuthenticatedRequest, @Query() query: BikerPoiSyncQueryDto): Promise<unknown> {
    void req;
    if (!this.bikerPois.configured) {
      // Bewusst 503 statt leerer Antwort: die App unterscheidet
      // "Dienst nicht konfiguriert" von "keine Änderungen".
      throw new ServiceUnavailableException({
        error: 'BIKER_POI_UNAVAILABLE',
        message: 'Biker-POI-Dienst nicht konfiguriert',
      });
    }
    return this.bikerPois.sync(query);
  }

  @Get('status')
  status(): unknown {
    return this.bikerPois.status();
  }
}
