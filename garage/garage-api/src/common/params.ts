import type { Request } from 'express';

/**
 * Verschachtelte Router (mergeParams) verlieren in Express-4-Typen die
 * Elterntypen - req.params ist {}. Dieser Helper liest den vehicleId-Param
 * typisiert (alle verschachtelten Routen hangen an /api/vehicles/:vehicleId).
 */
export function vehicleIdOf(req: Request): string {
  return String(req.params['vehicleId'] ?? '');
}
