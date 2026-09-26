import { Router } from 'express';
import { z } from 'zod';
import { prisma } from '../../common/prisma';
import { requireAuth } from '../auth/auth.middleware';
import { parseBody } from '../auth/auth.routes';
import { vehicleIdOf } from '../../common/params';
import { VehicleError } from '../vehicles/vehicles.service';

export const documentsRouter = Router({ mergeParams: true });
documentsRouter.use(requireAuth);

const createSchema = z.object({
  type: z.enum(['invoice', 'inspection', 'tuv', 'service_record', 'other']),
  title: z.string().min(1).max(160),
  fileUrl: z.string().min(1).max(1000),
  fileSizeBytes: z.number().int().min(0).optional(),
  mimeType: z.string().max(100).optional(),
  notes: z.string().max(1000).optional(),
});

/**
 * Dokumente sind IMMER privat (Anforderung 9/15): alle Routen pruefen
 * Ownership; es gibt keinen oeffentlichen Dokument-Endpunkt. Die eigent-
 * lichen Dateien liegen hinter fileUrl (privater Storage-Bucket) - der
 * Endpunkt verwaltet nur die Metadaten.
 */
async function requireOwned(userId: string, vehicleId: string) {
  const vehicle = await prisma.vehicle.findUnique({ where: { id: vehicleId } });
  if (!vehicle || vehicle.ownerId !== userId) {
    throw new VehicleError(404, 'VEHICLE_NOT_FOUND', 'Fahrzeug nicht gefunden');
  }
  return vehicle;
}

documentsRouter.get('/', async (req, res, next) => {
  try {
    await requireOwned(req.user!.id, vehicleIdOf(req));
    const documents = await prisma.document.findMany({
      where: { vehicleId: vehicleIdOf(req) },
      orderBy: { createdAt: 'desc' },
    });
    res.json({ documents });
  } catch (e) {
    next(e);
  }
});

documentsRouter.post('/', async (req, res, next) => {
  try {
    const dto = parseBody(createSchema, req.body);
    const document = await prisma.document.create({
      data: {
        vehicleId: vehicleIdOf(req),
        ownerId: req.user!.id,
        type: dto.type,
        title: dto.title,
        fileUrl: dto.fileUrl,
        fileSizeBytes: dto.fileSizeBytes ?? null,
        mimeType: dto.mimeType ?? null,
        notes: dto.notes ?? null,
      },
    });
    res.status(201).json(document);
  } catch (e) {
    next(e);
  }
});

documentsRouter.delete('/:id', async (req, res, next) => {
  try {
    const doc = await prisma.document.findUnique({ where: { id: req.params.id } });
    if (!doc || doc.ownerId !== req.user!.id) {
      throw new VehicleError(404, 'DOCUMENT_NOT_FOUND', 'Dokument nicht gefunden');
    }
    await prisma.document.delete({ where: { id: doc.id } });
    res.status(204).send();
  } catch (e) {
    next(e);
  }
});
