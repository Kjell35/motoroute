import express, { Router } from 'express';
import { z } from 'zod';
import { prisma } from '../../common/prisma';
import { requireAuth } from '../auth/auth.middleware';
import { parseBody } from '../auth/auth.routes';
import { vehicleIdOf } from '../../common/params';
import { VehicleError } from '../vehicles/vehicles.service';

export const documentsRouter = Router({ mergeParams: true });
documentsRouter.use(requireAuth);

/** Obergrenze pro Datei: groß genug für Fahrzeugschein-Fotos und PDFs, klein
 *  genug, dass die Free-Tier-Datenbank nicht vollläuft (Speicherung als bytea). */
const MAX_FILE_BYTES = 8 * 1024 * 1024;

const DOCUMENT_TYPES = ['invoice', 'inspection', 'tuv', 'service_record', 'other'] as const;

const createSchema = z.object({
  type: z.enum(DOCUMENT_TYPES),
  title: z.string().min(1).max(160),
  /** Altbestand: externe Links bleiben möglich, sind aber nicht mehr der Weg. */
  fileUrl: z.string().min(1).max(1000).optional(),
  fileName: z.string().min(1).max(200).optional(),
  fileSizeBytes: z.number().int().min(0).optional(),
  mimeType: z.string().max(100).optional(),
  notes: z.string().max(1000).optional(),
});

/** Metadaten-Felder ohne die Datei-Bytes - Listen dürfen nie megabytes laden. */
const DOCUMENT_SELECT = {
  id: true,
  vehicleId: true,
  ownerId: true,
  type: true,
  title: true,
  fileUrl: true,
  fileName: true,
  fileSizeBytes: true,
  mimeType: true,
  notes: true,
  hasFile: true,
  createdAt: true,
  updatedAt: true,
} as const;

/**
 * Dokumente sind IMMER privat (Anforderung 9/15): alle Routen pruefen
 * Ownership; es gibt keinen oeffentlichen Dokument-Endpunkt. Die Datei
 * selbst liegt in `Document.fileData` und wird ausschliesslich ueber
 * GET .../documents/:id/file ausgeliefert, nach Pruefung von Nutzer UND
 * Fahrzeug.
 */
async function requireOwned(userId: string, vehicleId: string) {
  const vehicle = await prisma.vehicle.findUnique({ where: { id: vehicleId } });
  if (!vehicle || vehicle.ownerId !== userId) {
    throw new VehicleError(404, 'VEHICLE_NOT_FOUND', 'Fahrzeug nicht gefunden');
  }
  return vehicle;
}

async function requireOwnedDocument(userId: string, vehicleId: string, documentId: string) {
  const document = await prisma.document.findUnique({ where: { id: documentId } });
  if (!document || document.ownerId !== userId || document.vehicleId !== vehicleId) {
    throw new VehicleError(404, 'DOCUMENT_NOT_FOUND', 'Dokument nicht gefunden');
  }
  return document;
}

/** Dateiname ohne Pfadanteile/Steuerzeichen - er landet im Content-Disposition-Header. */
function safeFileName(raw: string | undefined): string {
  const cleaned = (raw ?? '')
    .replace(/[\\/\r\n]/g, ' ')
    .replace(/[\u0000-\u001f]/g, '')
    .trim()
    .slice(0, 200);
  return cleaned || 'dokument';
}

documentsRouter.get('/', async (req, res, next) => {
  try {
    await requireOwned(req.user!.id, vehicleIdOf(req));
    const documents = await prisma.document.findMany({
      where: { vehicleId: vehicleIdOf(req) },
      orderBy: { createdAt: 'desc' },
      select: DOCUMENT_SELECT,
    });
    res.json({ documents });
  } catch (e) {
    next(e);
  }
});

documentsRouter.post('/', async (req, res, next) => {
  try {
    await requireOwned(req.user!.id, vehicleIdOf(req));
    const dto = parseBody(createSchema, req.body);
    const document = await prisma.document.create({
      data: {
        vehicleId: vehicleIdOf(req),
        ownerId: req.user!.id,
        type: dto.type,
        title: dto.title,
        fileUrl: dto.fileUrl ?? '',
        fileName: dto.fileName ? safeFileName(dto.fileName) : null,
        fileSizeBytes: dto.fileSizeBytes ?? null,
        mimeType: dto.mimeType ?? null,
        notes: dto.notes ?? null,
      },
      select: DOCUMENT_SELECT,
    });
    res.status(201).json(document);
  } catch (e) {
    next(e);
  }
});

/**
 * Datei-Upload als roher Body (kein Multipart-Parser nötig):
 *   PUT /api/vehicles/:v/documents/:id/file?fileName=fahrzeugschein.jpg
 *   Content-Type: image/jpeg
 *   Body: Bytes
 */
documentsRouter.put(
  '/:id/file',
  express.raw({ type: () => true, limit: MAX_FILE_BYTES }),
  async (req, res, next) => {
    try {
      const document = await requireOwnedDocument(req.user!.id, vehicleIdOf(req), req.params.id);
      const body = Buffer.isBuffer(req.body) ? req.body : Buffer.alloc(0);
      if (body.length === 0) {
        throw new VehicleError(400, 'FILE_EMPTY', 'Keine Datei empfangen');
      }
      const contentType = typeof req.headers['content-type'] === 'string'
        ? req.headers['content-type'].split(';')[0].trim()
        : null;
      const updated = await prisma.document.update({
        where: { id: document.id },
        data: {
          fileData: body,
          hasFile: true,
          fileSizeBytes: body.length,
          mimeType: contentType && contentType !== 'application/octet-stream'
            ? contentType
            : document.mimeType,
          fileName: req.query['fileName'] ? safeFileName(String(req.query['fileName'])) : document.fileName,
        },
        select: { id: true, fileName: true, fileSizeBytes: true, mimeType: true, hasFile: true },
      });
      res.json(updated);
    } catch (e) {
      next(e);
    }
  },
);

/** Datei ausliefern - nur an den Besitzer, nie öffentlich, nie cachebar. */
documentsRouter.get('/:id/file', async (req, res, next) => {
  try {
    const document = await requireOwnedDocument(req.user!.id, vehicleIdOf(req), req.params.id);
    if (!document.fileData || !document.hasFile) {
      throw new VehicleError(404, 'FILE_MISSING', 'Für dieses Dokument ist keine Datei gespeichert');
    }
    const name = safeFileName(document.fileName ?? `${document.title}.bin`);
    res.setHeader('Content-Type', document.mimeType ?? 'application/octet-stream');
    res.setHeader(
      'Content-Disposition',
      `attachment; filename="${name.replace(/[^\x20-\x7e]/g, '_')}"; filename*=UTF-8''${encodeURIComponent(name)}`,
    );
    res.setHeader('Cache-Control', 'private, no-store');
    res.send(Buffer.from(document.fileData));
  } catch (e) {
    next(e);
  }
});

documentsRouter.delete('/:id', async (req, res, next) => {
  try {
    await requireOwnedDocument(req.user!.id, vehicleIdOf(req), req.params.id);
    await prisma.document.delete({ where: { id: req.params.id } });
    res.status(204).send();
  } catch (e) {
    next(e);
  }
});
