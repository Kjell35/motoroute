import {
  Body,
  Controller,
  Get,
  HttpCode,
  Param,
  Post,
  Query,
  Req,
  UseGuards,
} from '@nestjs/common';
import { AuthProvider, AuthenticatedRequest } from '../../guards';
import { HazardsService } from './hazards.service';
import { CreateHazardDto, NearbyHazardsQueryDto } from './hazards.dto';

/**
 * Community-Gefahrenradar unter /v1/hazards.
 *
 * Strikt authentifiziert (AuthProvider): Meldungen von unterwegs sind
 * ein angemeldet-Feature - das schützt das Radar vor Spam-Anonymität,
 * und der globale Throttler (120 req/min) deckelt ohnehin. RLS + RPCs
 * in schema_hazards.sql bleiben die durchsetzende Autorisierungsschicht.
 */
@Controller('v1/hazards')
@UseGuards(AuthProvider)
export class HazardsController {
  constructor(private readonly hazards: HazardsService) {}

  /** Neue Gefahrenmeldung abspeichern (PostGIS POINT + Konsolidierung). */
  @Post()
  create(@Req() req: AuthenticatedRequest, @Body() dto: CreateHazardDto): Promise<unknown> {
    return this.hazards.createReport(req.user!, dto);
  }

  /** Aktive Gefahren im Umkreis (Standard 50 km, 24-h-Ablauf). */
  @Get('nearby')
  nearby(@Req() req: AuthenticatedRequest, @Query() query: NearbyHazardsQueryDto): Promise<unknown[]> {
    return this.hazards.nearby(req.user!, {
      lat: query.lat,
      lon: query.lon,
      radiusKm: query.radiusKm,
    });
  }

  /** Upvote = "Gefahr existiert noch" (Validierung + Deduplizierung im RPC). */
  @Post(':id/upvote')
  @HttpCode(200)
  upvote(@Req() req: AuthenticatedRequest, @Param('id') id: string): Promise<unknown> {
    void req;
    return this.hazards.upvote(req.user!, id);
  }
}
