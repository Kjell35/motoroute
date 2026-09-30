import { Body, Controller, Get, Post, Req, UseGuards } from '@nestjs/common';
import { Throttle } from '@nestjs/throttler';
import { Type } from 'class-transformer';
import {
  IsIn,
  IsInt,
  IsLatitude,
  IsLongitude,
  IsNumber,
  IsOptional,
  IsString,
  IsUrl,
  Matches,
  Max,
  MaxLength,
  Min,
  MinLength,
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

/** Admin-Formular: neuen Badge anlegen (POST /v1/badges). */
export class CreateBadgeDto {
  @IsString()
  @MinLength(2)
  @MaxLength(80)
  title!: string;

  @IsOptional()
  @IsString()
  @MaxLength(300)
  description?: string;

  @IsIn(['pass', 'meeting', 'sight'])
  category!: 'pass' | 'meeting' | 'sight';

  @Type(() => Number)
  @IsNumber()
  @IsLatitude()
  lat!: number;

  @Type(() => Number)
  @IsNumber()
  @IsLongitude()
  lon!: number;

  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(20)
  @Max(500)
  radiusMeters?: number;

  /** Optionales Bild; nur https (die App fällt sonst aufs Emoji zurück). */
  @IsOptional()
  @IsUrl({ protocols: ['https'], require_protocol: true })
  @Matches(/^https:\/\//)
  @MaxLength(500)
  iconUrl?: string;
}

/**
 * Badges ("Pass-Knacker"): GPS-Check-ins an Pässen/Bikertreffs schalten
 * Trophäen frei. Endpunkte:
 *
 *   POST /v1/badges/checkin  - aktuelle Position melden (auth-pflichtig,
 *                              bewusst auf 10/min gedrosselt: GPS-Calls
 *                              sind teuer und ein Missbrauchsvektor).
 *   GET  /v1/badges/me       - Trophäenschrank (Katalog + Freischaltungen).
 *   POST /v1/badges          - Admin: neuen Badge anlegen (role=admin).
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

  @Post()
  @UseGuards(AuthProvider)
  @Throttle({ default: { limit: 30, ttl: 60_000 } })
  async create(@Req() req: AuthenticatedRequest, @Body() dto: CreateBadgeDto) {
    return this.badges.createBadge(req.user!, dto);
  }
}
