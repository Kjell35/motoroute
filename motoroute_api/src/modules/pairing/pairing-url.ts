import type { Request } from 'express';

/**
 * Öffentliche Basis-URL für QR-/Plan-Links.
 *
 * Warum nicht einfach req.protocol: Express steht hinter dem Render-Proxy und
 * vertraut ihm ohne `trust proxy` nicht, `req.protocol` wäre also "http" - die
 * App würde den QR-Code scannen und an einer Cleartext-URL scheitern. Deshalb
 * die X-Forwarded-Header auswerten; `PAIRING_PUBLIC_BASE_URL` hat Vorrang,
 * falls die Links später über eine eigene Domain laufen sollen.
 */
export function publicOrigin(req: Request, configured?: string): string {
  const explicit = (configured ?? '').trim().replace(/\/+$/, '');
  if (explicit) return explicit;

  const header = (name: string): string => {
    const value = req.headers[name];
    const raw = Array.isArray(value) ? value[0] : value;
    return (raw ?? '').split(',')[0].trim();
  };

  const proto = header('x-forwarded-proto') || req.protocol || 'https';
  const host = header('x-forwarded-host') || header('host');
  return host ? `${proto}://${host}` : '';
}
