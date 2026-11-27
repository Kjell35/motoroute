import { Injectable } from '@nestjs/common';
import { ThrottlerGuard } from '@nestjs/throttler';

/**
 * Drosselung pro echtem Client.
 *
 * Gemessener Aufbau hinter Cloudflare + Render (Probe, 27.11.):
 *
 *   ohne eigenen Header:  X-Forwarded-For: 77.8.137.177, 104.22.83.54, 10.29.164.4
 *   mit gefälschtem XFF:  X-Forwarded-For: 9.9.9.9, 77.8.137.177, 172.71.147.98, 10.24.36.215
 *   cf-connecting-ip:     77.8.137.177   (auch mit gefälschtem XFF unverändert)
 *   req.ip:               10.29.164.4    (interner Hop, wechselt pro Anfrage)
 *
 * Der Client kann also vorne beliebig viele Einträge anhängen; Cloudflare
 * schreibt seinen Eintrag dahinter, Render hängt intern 10.x an. Deshalb ist
 * der linke Eintrag NICHT vertrauenswürdig (damit war das Limit umgehbar),
 * und `req.ip` ist der interne Hop (damit war die Zählung instabil).
 *
 * Schlüssel:
 *  1. `cf-connecting-ip` (bzw. `true-client-ip`), aber nur wenn der Request
 *     wirklich durch Cloudflare kam (`cf-ray`/`cdn-loop` vorhanden) - sonst
 *     könnte man den Header direkt am Origin fälschen.
 *  2. sonst die X-Forwarded-For-Kette von rechts: interne Hops (10.x, ::1, …)
 *     abschneiden, bei Cloudflare zusätzlich den Edge-Eintrag davor. Was dann
 *     rechts steht, ist der Client.
 *  3. sonst `req.ip`.
 */
@Injectable()
export class ClientThrottlerGuard extends ThrottlerGuard {
  protected async getTracker(req: Record<string, any>): Promise<string> {
    return clientKey(req);
  }
}

export function clientKey(req: Record<string, any>): string {
  const headers = req?.headers ?? {};
  const viaCloudflare = Boolean(headerValue(headers['cf-ray']) || headerValue(headers['cdn-loop']));

  if (viaCloudflare) {
    const cloudflareClient =
      headerValue(headers['cf-connecting-ip']) || headerValue(headers['true-client-ip']);
    if (cloudflareClient) return cloudflareClient;
  }

  const chain = parseForwardedFor(headers['x-forwarded-for']);

  // Render hängt seinen internen Hop an - der gehört nicht zum Client.
  while (chain.length > 1 && isInternalAddress(chain[chain.length - 1])) chain.pop();
  // Direkt davor steht der Cloudflare-Edge; der wechselt und ist kein Client.
  if (viaCloudflare && chain.length > 1 && !isInternalAddress(chain[chain.length - 1])) chain.pop();

  return chain[chain.length - 1] || req?.ip || 'unbekannt';
}

function headerValue(value: string | string[] | undefined): string {
  const raw = Array.isArray(value) ? value[0] : value;
  return (raw ?? '').split(',')[0].trim();
}

function parseForwardedFor(value: string | string[] | undefined): string[] {
  const raw = Array.isArray(value) ? value.join(',') : (value ?? '');
  return raw
    .split(',')
    .map((entry) => entry.trim())
    .filter(Boolean);
}

/** Adressen, die nur innerhalb des Hosting-Stacks vorkommen. */
function isInternalAddress(ip: string): boolean {
  return (
    /^10\./.test(ip) ||
    /^127\./.test(ip) ||
    /^192\.168\./.test(ip) ||
    /^169\.254\./.test(ip) ||
    /^172\.(1[6-9]|2\d|3[01])\./.test(ip) ||
    ip === '::1' ||
    /^fe80:/i.test(ip) ||
    /^f[cd][0-9a-f]{2}:/i.test(ip)
  );
}
