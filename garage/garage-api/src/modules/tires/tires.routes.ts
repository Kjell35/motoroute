import { Router } from 'express';
import { z } from 'zod';
import { prisma } from '../../common/prisma';
import { requireAuth } from '../auth/auth.middleware';
import { parseBody } from '../auth/auth.routes';
import { vehicleIdOf } from '../../common/params';
import { VehicleError } from '../vehicles/vehicles.service';

export const tiresRouter = Router({ mergeParams: true });
tiresRouter.use(requireAuth);

const createSchema = z.object({
  position: z.enum(['front', 'rear']),
  brand: z.string().min(1).max(60),
  modelName: z.string().min(1).max(80),
  size: z.string().min(3).max(40),
  mountedAt: z.string().datetime().or(z.string().date()),
  mountedAtKm: z.number().int().min(0).max(5_000_000),
  treadDepthMm: z.number().min(0).max(20).optional(),
  season: z.enum(['summer', 'winter', 'allseason']).optional(),
  notes: z.string().max(1000).optional(),
});

async function requireOwned(userId: string, vehicleId: string) {
  const vehicle = await prisma.vehicle.findUnique({ where: { id: vehicleId } });
  if (!vehicle || vehicle.ownerId !== userId) {
    throw new VehicleError(404, 'VEHICLE_NOT_FOUND', 'Fahrzeug nicht gefunden');
  }
  return vehicle;
}

tiresRouter.get('/', async (req, res, next) => {
  try {
    await requireOwned(req.user!.id, vehicleIdOf(req));
    const mounted = req.query['mounted'] === 'true' ? { removedAt: null } : req.query['mounted'] === 'false' ? { NOT: { removedAt: null } } : {};
    const tires = await prisma.tire.findMany({
      where: { vehicleId: vehicleIdOf(req), ...mounted },
      orderBy: { mountedAt: 'desc' },
    });
    res.json({ tires });
  } catch (e) {
    next(e);
  }
});

tiresRouter.post('/', async (req, res, next) => {
  try {
    const dto = parseBody(createSchema, req.body);
    const tire = await prisma.tire.create({
      data: {
        vehicleId: vehicleIdOf(req),
        ownerId: req.user!.id,
        position: dto.position,
        brand: dto.brand,
        modelName: dto.modelName,
        size: dto.size,
        mountedAt: new Date(dto.mountedAt),
        mountedAtKm: dto.mountedAtKm,
        treadDepthMm: dto.treadDepthMm ?? null,
        season: dto.season ?? null,
        notes: dto.notes ?? null,
      },
    });
    res.status(201).json(tire);
  } catch (e) {
    next(e);
  }
});

/** Reifen abmontieren (Historie bleibt erhalten). */
tiresRouter.post('/:id/remove', async (req, res, next) => {
  try {
    const tire = await prisma.tire.findUnique({ where: { id: req.params.id } });
    if (!tire || tire.ownerId !== req.user!.id) {
      throw new VehicleError(404, 'TIRE_NOT_FOUND', 'Reifen nicht gefunden');
    }
    const updated = await prisma.tire.update({
      where: { id: tire.id },
      data: { removedAt: new Date() },
    });
    res.json(updated);
  } catch (e) {
    next(e);
  }
});

tiresRouter.delete('/:id', async (req, res, next) => {
  try {
    const tire = await prisma.tire.findUnique({ where: { id: req.params.id } });
    if (!tire || tire.ownerId !== req.user!.id) {
      throw new VehicleError(404, 'TIRE_NOT_FOUND', 'Reifen nicht gefunden');
    }
    await prisma.tire.delete({ where: { id: tire.id } });
    res.status(204).send();
  } catch (e) {
    next(e);
  }
});
