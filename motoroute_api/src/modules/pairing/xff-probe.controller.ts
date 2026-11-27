import { Controller, Get, Req } from '@nestjs/common';
import type { Request } from 'express';

/**
 * VORÜBERGEHEND (Diagnose, wird nach der Messung wieder entfernt):
 * zeigt, wie der Render-Proxy X-Forwarded-For aufbaut - welcher Eintrag von
 * wem stammt. Liefert nur die Header des aufrufenden Requests.
 */
@Controller('__probe')
export class XffProbeController {
  @Get('xff')
  probe(@Req() req: Request) {
    const raw = req.headers['x-forwarded-for'];
    const forwarded = (Array.isArray(raw) ? raw.join(' | ') : (raw ?? ''))
      .split(',')
      .map((entry) => entry.trim())
      .filter(Boolean);

    return {
      forwarded,
      count: forwarded.length,
      reqIp: req.ip,
      reqIps: req.ips,
      socket: req.socket?.remoteAddress,
      forwardedForHeaderCount: Array.isArray(raw) ? raw.length : raw ? 1 : 0,
      proto: req.headers['x-forwarded-proto'],
      host: req.headers['x-forwarded-host'] ?? req.headers.host,
      headers: req.headers,
    };
  }
}
