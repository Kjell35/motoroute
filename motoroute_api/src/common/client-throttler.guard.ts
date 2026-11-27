import { Injectable } from '@nestjs/common';
import { ThrottlerGuard } from '@nestjs/throttler';

/**
 * Drosselung pro echtem Client statt pro Proxy-Adresse.
 *
 * `ThrottlerGuard` zählt standardmäßig auf `req.ip`. Hinter dem Render-Proxy
 * ist das mit `trust proxy 1` nicht stabil: live gemessen landeten die 5/min
 * von POST /pairing/start auf wechselnden Schlüsseln - ein Burst ging teils
 * durch, teils kam 429 mit zurückgesetztem `x-ratelimit-reset`. Der erste
 * Eintrag in `X-Forwarded-For` ist der Client, den der Proxy eingetragen hat;
 * alles danach sind Hops dahinter (und dürfen den Zähler nicht splitten).
 *
 * Fallback auf `req.ip`, wenn der Header fehlt (direkte Verbindung, Tests).
 */
@Injectable()
export class ClientThrottlerGuard extends ThrottlerGuard {
  protected async getTracker(req: Record<string, any>): Promise<string> {
    const header = req.headers?.['x-forwarded-for'];
    const raw = Array.isArray(header) ? header[0] : header;
    const client = typeof raw === 'string' ? raw.split(',')[0].trim() : '';

    return client || req.ip || 'unbekannt';
  }
}
