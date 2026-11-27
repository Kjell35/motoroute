import { Controller, Get, Param, Req, Res } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import type { Request, Response } from 'express';
import QRCode from 'qrcode';
import { readPlanAsset, renderTemplate } from './plan-page/assets';
import { normalizeToken, PairingService } from './pairing.service';
import { publicOrigin } from './pairing-url';

/**
 * Die Plan-Seite am Rechner: /plan/{TOKEN}.
 *
 * HTML, CSS und Skript liegen als eigene Dateien unter `plan-page/`; hier
 * werden nur die Werte eingesetzt, die sich pro Plan unterscheiden (Code,
 * QR-Bild, Prefill). CSS und Skript sind für alle Pläne gleich, werden in
 * `main.ts` unter /plan/assets/ statisch ausgeliefert und dürfen deshalb im
 * Browser-Cache liegen.
 */
@Controller('plan')
export class PairingPlanPageController {
  constructor(
    private readonly pairing: PairingService,
    private readonly config: ConfigService,
  ) {}

  /**
   * QR-Code als PNG. Die Seite laedt ihn nach der Rettung eines abgelaufenen
   * Codes neu, statt das ganze Dokument zu wechseln.
   */
  @Get(':token/qr.png')
  async qr(
    @Param('token') token: string,
    @Req() req: Request,
    @Res() res: Response,
  ): Promise<void> {
    const planUrl = `${publicOrigin(req, this.config.get<string>('PAIRING_PUBLIC_BASE_URL'))}/plan/${normalizeToken(token)}`;
    const png = await QRCode.toBuffer(planUrl, { margin: 1, width: 260, type: 'png' });
    res.type('png').send(png);
  }

  @Get(':token')
  async page(
    @Param('token') token: string,
    @Req() req: Request,
    @Res() res: Response,
  ): Promise<void> {
    const points = await this.pairing.getPoints(token);
    const planUrl = `${publicOrigin(req, this.config.get<string>('PAIRING_PUBLIC_BASE_URL'))}/plan/${normalizeToken(token)}`;

    if (points === null) {
      res
        .status(404)
        .type('html')
        .send(
          renderTemplate(readPlanAsset('expired.html'), { PLAN_URL: escapeHtml(planUrl) }),
        );
      return;
    }

    const qr = await QRCode.toDataURL(planUrl, { margin: 1, width: 260 });

    // Echter Zeilenumbruch, kein '\\n': der Text landet 1:1 im <textarea>,
    // sonst klebt nach dem Laden alles in einer Zeile mit Backslash-n.
    const prefill = points.map((p) => `${p.lat}, ${p.lon}, ${p.label}`).join('\n');

    res.type('html').send(
      renderTemplate(readPlanAsset('page.html'), {
        TOKEN: escapeHtml(normalizeToken(token)),
        PLAN_URL: escapeHtml(planUrl),
        QR_DATA_URL: qr,
        PREFILL: escapeHtml(prefill),
        COUNT: String(points.length),
      }),
    );
  }
}

function escapeHtml(value: string): string {
  return value
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}
