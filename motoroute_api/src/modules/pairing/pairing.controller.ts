import {
  Body,
  Controller,
  Get,
  HttpCode,
  NotFoundException,
  Param,
  Post,
  Put,
  Req,
  UseGuards,
} from '@nestjs/common';
import { Throttle } from '@nestjs/throttler';
import { ClientThrottlerGuard } from '../../common/client-throttler.guard';
import { ConfigService } from '@nestjs/config';
import type { Request } from 'express';
import { PairingService, PairingStart } from './pairing.service';
import { publicOrigin } from './pairing-url';

/**
 * Vertrag, den die App (apps/mobile/lib/features/pairing) schon nutzt:
 *   POST /api/v1/pairing/start       -> { token, plan_url, plan_urls, expires_in_seconds }
 *   GET  /api/v1/pairing/{TOKEN}     -> { points: [{ label, detail, lat, lon }] }, 404 bei abgelaufen
 * Bewusst ohne AuthGuard: die App ruft beide Endpunkte ohne Bearer-Token auf,
 * und das Token selbst ist das Geheimnis.
 *
 * Zusätzlich unter /v1/pairing erreichbar: der Audit hat genau diesen Pfad
 * geprüft und dort 404 gesehen (die übrigen Module hängen unter /api/v1).
 * Beide Pfade zeigen auf dieselbe Implementierung, damit weder App noch
 * Prüfskript einen Sonderfall braucht.
 */
@Controller(['api/v1/pairing', 'v1/pairing'])
export class PairingController {
  constructor(
    private readonly pairing: PairingService,
    private readonly config: ConfigService,
  ) {}

  /**
   * Öffentlich und schreibt bei jedem Aufruf eine Zeile nach pairing_plans -
   * deshalb gedrosselt (5 Starts pro Minute und Client). Ohne Guard wäre der
   * Decorator wirkungslos: der Throttler ist in dieser App nirgends global
   * gebunden, hier hängt er bewusst nur an dieser Route.
   */
  @Post('start')
  @HttpCode(200)
  @UseGuards(ClientThrottlerGuard)
  @Throttle({ default: { limit: 5, ttl: 60_000 } })
  start(@Req() req: Request): Promise<PairingStart> {
    return this.pairing.start(
      publicOrigin(req, this.config.get<string>('PAIRING_PUBLIC_BASE_URL')),
    );
  }

  @Get(':token')
  async get(@Param('token') token: string) {
    const points = await this.pairing.getPoints(token);
    if (points === null) {
      throw new NotFoundException('Pairing-Code unbekannt oder abgelaufen');
    }
    return { points };
  }

  /** Aufruf der Web-Seite /plan/{TOKEN}; die App liest nur per GET. */
  @Put(':token/points')
  @HttpCode(200)
  async save(@Param('token') token: string, @Body() body: { points?: unknown }) {
    const points = await this.pairing.savePoints(token, body?.points);
    if (points === null) {
      throw new NotFoundException('Pairing-Code unbekannt oder abgelaufen');
    }
    return { ok: true, count: points.length };
  }
}
