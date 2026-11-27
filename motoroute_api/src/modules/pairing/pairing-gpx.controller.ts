import { Controller, Get, NotFoundException, Param, Res } from '@nestjs/common';
import type { Response } from 'express';
import { buildGpx } from './pairing-gpx';
import { normalizeToken, PairingService } from './pairing.service';

/**
 * GET /plan/{TOKEN}/gpx - die gespeicherten Punkte als GPX-Download.
 *
 * Gleiche Gültigkeit wie die Plan-Seite: nur existierende Codes liefern eine
 * Datei, abgelaufene bekommen 404. Kein Fremddienst, keine Signatur - das XML
 * entsteht aus den Punkten, die in der Datenbank stehen.
 */
@Controller('plan')
export class PairingGpxController {
  constructor(private readonly pairing: PairingService) {}

  @Get(':token/gpx')
  async download(@Param('token') token: string, @Res() res: Response): Promise<void> {
    const points = await this.pairing.getPoints(token);
    if (points === null) {
      throw new NotFoundException('Pairing-Code unbekannt oder abgelaufen');
    }

    const code = normalizeToken(token);
    res.setHeader('Content-Type', 'application/gpx+xml; charset=utf-8');
    res.setHeader('Content-Disposition', `attachment; filename="MotoRoute-${code}.gpx"`);
    res.send(buildGpx(code, points));
  }
}
