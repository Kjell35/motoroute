import {
  Body,
  Controller,
  Get,
  HttpCode,
  HttpStatus,
  Post,
  Query,
  Req,
  UseGuards,
} from '@nestjs/common';
import { IsIn, IsInt, IsOptional, IsString, Length, Max, Min } from 'class-validator';
import { Type } from 'class-transformer';
import { ConfigService } from '@nestjs/config';
import {
  AuthenticatedRequest,
  AuthProvider,
  OptionalAuthProvider,
} from '../../guards';
import { TelemetryService } from './telemetry.service';

/** Meldungs-Kategorien: [feature].[aktion] bzw. 'crash'. */
export const TELEMETRY_CATEGORIES = [
  'crash',
  'chat.load',
  'chat.send',
  'chat.search',
  'chat.group',
  'chat.admin',
  'chat.other',
  'mp.load',
  'mp.create',
  'mp.other',
  'garage.connect',
  'garage.load',
  'garage.write',
  'garage.other',
  'routes.load',
  'map.style',
  'other',
] as const;

export type TelemetryCategory = (typeof TELEMETRY_CATEGORIES)[number];

export class CreateErrorReportDto {
  @IsIn(TELEMETRY_CATEGORIES as unknown as string[])
  category!: string;

  @IsString()
  @Length(1, 300)
  cause!: string;

  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(400)
  @Max(599)
  httpStatus?: number;

  @IsIn(['android', 'ios', 'web'])
  platform!: string;

  @IsString()
  @Length(1, 20)
  appVersion!: string;
}

/**
 * Telemetry (anonymes Fehler-Reporting).
 *
 * Die App meldet fehlgeschlagene Aktionen OHNE personenbezogene Daten;
 * der Admin sieht aggregiert, welche Bereiche bei wie vielen Nutzern
 * haken (Support ohne Screenshots).
 */
@Controller('v1/telemetry')
export class TelemetryController {
  constructor(
    private readonly telemetry: TelemetryService,
    private readonly config: ConfigService,
  ) {}

  /**
   * Fehler melden. Bewusst anonym erreichbar (OptionalAuth): Auch ein
   * Nutzer mit abgelaufener Sitzung (DER Hauptfall für Chat-401-Spam)
   * soll melden können. Ist ein Token da, wird der user_hash daraus
   * abgeleitet; ohne Token bleibt der Bericht vollkommen anonym.
   */
  @Post('errors')
  @UseGuards(OptionalAuthProvider)
  @HttpCode(202)
  async reportError(@Req() req: AuthenticatedRequest, @Body() dto: CreateErrorReportDto) {
    const salt = this.config.get<string>('TELEMETRY_SALT') ?? 'motoroute-telemetry';
    await this.telemetry.reportError(req.user?.id, salt, dto);
    return { accepted: true };
  }

  /** Admin: letzte Fehlerberichte (users.role = 'admin'). */
  @Get('admin/errors')
  @UseGuards(AuthProvider)
  async adminList(@Req() req: AuthenticatedRequest, @Query('limit') limit?: string) {
    const parsed = Number(limit);
    return this.telemetry.adminList(
      req.user!,
      Number.isFinite(parsed) && parsed > 0 ? Math.min(Math.trunc(parsed), 200) : 100,
    );
  }
}
