import { Router } from 'express';
import { z } from 'zod';
import { prisma } from '../../common/prisma';
import { requireAuth } from '../auth/auth.middleware';
import { parseBody } from '../auth/auth.routes';
import { vehicleIdOf } from '../../common/params';
import { VehicleError } from '../vehicles/vehicles.service';

export const fuelRouter = Router({ mergeParams: true });
fuelRouter.use(requireAuth);

const createSchema = z.object({
  date: z.string().datetime().or(z.string().date()),
  odometerKm: z.number().int().min(0).max(5_000_000),
  liters: z.number().positive().max(500),
  priceCentsTotal: z.number().int().min(0),
  pricePerLiterCents: z.number().int().min(0).optional(),
  station: z.string().max(120).optional(),
  isFullTank: z.boolean().default(true),
  notes: z.string().max(500).optional(),
});

async function requireOwned(userId: string, vehicleId: string) {
  const vehicle = await prisma.vehicle.findUnique({ where: { id: vehicleId } });
  if (!vehicle || vehicle.ownerId !== userId) {
    throw new VehicleError(404, 'VEHICLE_NOT_FOUND', 'Fahrzeug nicht gefunden');
  }
  return vehicle;
}

fuelRouter.get('/', async (req, res, next) => {
  try {
    await requireOwned(req.user!.id, vehicleIdOf(req));
    const entries = await prisma.fuelEntry.findMany({
      where: { vehicleId: vehicleIdOf(req) },
      orderBy: { odometerKm: 'asc' },
    });
    res.json({ entries });
  } catch (e) {
    next(e);
  }
});

fuelRouter.post('/', async (req, res, next) => {
  try {
    const dto = parseBody(createSchema, req.body);
    const entry = await prisma.fuelEntry.create({
      data: {
        vehicleId: vehicleIdOf(req),
        ownerId: req.user!.id,
        date: new Date(dto.date),
        odometerKm: dto.odometerKm,
        liters: dto.liters,
        priceCentsTotal: dto.priceCentsTotal,
        pricePerLiterCents: dto.pricePerLiterCents ?? Math.round(dto.priceCentsTotal / dto.liters),
        station: dto.station ?? null,
        isFullTank: dto.isFullTank,
        notes: dto.notes ?? null,
      },
    });
    res.status(201).json(entry);
  } catch (e) {
    next(e);
  }
});

/**
 * Verbrauchs-/Kostenstatistik (Anforderung 11): Durchschnittsverbrauch
 * aus aufeinanderfolgenden VOLL-Tankungen, Gesamtkosten, Kosten/km.
 */
fuelRouter.get('/stats', async (req, res, next) => {
  try {
    await requireOwned(req.user!.id, vehicleIdOf(req));
    const entries = await prisma.fuelEntry.findMany({
      where: { vehicleId: vehicleIdOf(req) },
      orderBy: { odometerKm: 'asc' },
    });

    let litersSum = 0;
    let kmSum = 0;
    let segments = 0;
    for (let i = 1; i < entries.length; i++) {
      const prev = entries[i - 1]!;
      const cur = entries[i]!;
      if (prev.isFullTank && cur.isFullTank && cur.odometerKm > prev.odometerKm) {
        litersSum += cur.liters;
        kmSum += cur.odometerKm - prev.odometerKm;
        segments += 1;
      }
    }

    const totalCost = entries.reduce((s, e) => s + e.priceCentsTotal, 0);
    const totalLiters = entries.reduce((s, e) => s + e.liters, 0);
    const minOdo = entries[0]?.odometerKm ?? 0;
    const maxOdo = entries.at(-1)?.odometerKm ?? 0;

    res.json({
      vehicleId: vehicleIdOf(req),
      averageConsumptionPer100km: kmSum > 0 ? Math.round((litersSum / kmSum) * 1000) / 10 : null,
      segmentsCounted: segments,
      totalCostCents: totalCost,
      totalLiters: Math.round(totalLiters * 100) / 100,
      costPerKmCents: maxOdo > minOdo ? Math.round(totalCost / (maxOdo - minOdo)) : null,
      entriesCount: entries.length,
    });
  } catch (e) {
    next(e);
  }
});

fuelRouter.delete('/:id', async (req, res, next) => {
  try {
    const entry = await prisma.fuelEntry.findUnique({ where: { id: req.params.id } });
    if (!entry || entry.ownerId !== req.user!.id) {
      throw new VehicleError(404, 'ENTRY_NOT_FOUND', 'Tankeintrag nicht gefunden');
    }
    await prisma.fuelEntry.delete({ where: { id: entry.id } });
    res.status(204).send();
  } catch (e) {
    next(e);
  }
});
