import {
  BadRequestException,
  Controller,
  Get,
  NotFoundException,
  Param,
  Query,
  UseGuards,
} from '@nestjs/common';
import { Throttle } from '@nestjs/throttler';
import { ClientThrottlerGuard } from '../../common/client-throttler.guard';
import { PairingService } from './pairing.service';
import { PairingGeocodeService } from './pairing-geocode.service';

/**
 * GET /api/v1/pairing/{TOKEN}/geocode?q=Eibsee
 *
 * Nur für gültige Pairing-Codes: sonst könnte jeder das Backend als
 * kostenlosen Geocoder gegen Nominatim benutzen. Zusätzlich pro Client
 * gedrosselt, damit die Suche nicht als Verstärker wirkt.
 */
@Controller(['api/v1/pairing', 'v1/pairing'])
export class PairingGeocodeController {
  constructor(
    private readonly pairing: PairingService,
    private readonly geocode: PairingGeocodeService,
  ) {}

  @Get(':token/geocode')
  @UseGuards(ClientThrottlerGuard)
  @Throttle({ default: { limit: 10, ttl: 60_000 } })
  async search(@Param('token') token: string, @Query('q') q?: string) {
    const points = await this.pairing.getPoints(token);
    if (points === null) {
      throw new NotFoundException('Pairing-Code unbekannt oder abgelaufen');
    }
    const query = (q ?? '').trim();
    if (query.length < 3) {
      throw new BadRequestException(
        'Bitte mindestens 3 Zeichen eingeben (z. B. Eibsee).',
      );
    }
    if (query.length > 120) {
      throw new BadRequestException('Suchbegriff ist zu lang.');
    }
    return { results: await this.geocode.search(query) };
  }
}
