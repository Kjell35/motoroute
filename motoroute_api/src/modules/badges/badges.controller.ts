import { Body, Controller, Get, Post, Req, UseGuards } from '@nestjs/common';
import { Throttle } from '@nestjs/throttler';
import { Type } from 'class-transformer';
import {
  IsLatitude,
  IsLongitude,
  IsNumber,
} from 'class-validator';
import {
  AuthenticatedRequest,
  AuthProvider,
} from '../../guards';
import { BadgesService } from './badges.service';

export class CheckinDto {
  @Type(() => Number)
  @IsNumber()
  @IsLatitude()
  lat!: number;

  @Type(() => Number)
  @IsLongitude()
  lon!: number;
}

/**
 * Badges ("Pass-Knacker"): GPS-Check-ins an Pässen/Bikertreffs schalten
 * Trophäen frei. Endpunkte:
 *
 *   POST /v1/badges/checkin  - aktuelle Position melden (auth-pflichtig,
 *                              bewusst auf 10/min gedrosselt: GPS-Calls
 *                              sind teuer und ein Missbrauchsvektor).
 *   GET  /v1/badges/me       - Trophäenschrank (Katalog + Freischaltungen).
 */
@Controller('v1/badges')
export class BadgesController {
  constructor(private readonly badges: BadgesService) {}

  @Post('checkin')
  @UseGuards(AuthProvider)
  @Throttle({ default: { limit: 10, ttl: 60_000 } })
  async checkin(@Req() req: AuthenticatedRequest, @Body() dto: CheckinDto) {
    return this.badges.checkin(req.user!, dto.lat, dto.lon);
  }

  @Get('me')
  @UseGuards(AuthProvider)
  async me(@Req() req: AuthenticatedRequest) {
    return this.badges.myBadges(req.user!);
  }
}
