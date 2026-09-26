import { Router } from 'express';
import { z } from 'zod';
import { requireAuth } from '../auth/auth.middleware';
import { vehiclesService } from './vehicles.service';
import { parseBody } from '../auth/auth.routes';
import { maintenanceService } from '../maintenance/maintenance.service';

export const vehiclesRouter = Router();
vehiclesRouter.use(requireAuth);

const createSchema = z.object({
  category: z.enum(['motorcycle', 'car']),
  variantId: z.string().uuid().optional(),
  manufacturerName: z.string().min(1).max(80),
  modelName: z.string().min(1).max(120),
  variantName: z.string().max(120).optional(),
  year: z.number().int().min(1900).max(2100).optional(),
  firstRegistration: z.string().datetime().or(z.string().date()).optional(),
  nickname: z.string().max(80).optional(),
  color: z.string().max(60).optional(),
  licensePlate: z.string().max(20).optional(),
  odometerKm: z.number().int().min(0).max(5_000_000).optional(),
  purchaseDate: z.string().datetime().or(z.string().date()).optional(),
  purchasePriceCents: z.number().int().min(0).optional(),
  notes: z.string().max(4000).optional(),
  photoUrl: z.string().url().max(1000).optional(),
});

const updateSchema = createSchema.partial().omit({ category: true, variantId: true, manufacturerName: true, modelName: true, variantName: true, year: true });

// GET /api/vehicles/garage - die Gruppierungs-Übersicht (Motorräder/Autos)
vehiclesRouter.get('/garage', async (req, res, next) => {
  try {
    res.json(await vehiclesService.garage(req.user!.id));
  } catch (e) {
    next(e);
  }
});

vehiclesRouter.post('/', async (req, res, next) => {
  try {
    const dto = parseBody(createSchema, req.body);
    res.status(201).json(await vehiclesService.create(req.user!.id, dto));
  } catch (e) {
    next(e);
  }
});

vehiclesRouter.get('/', async (req, res, next) => {
  try {
    const garage = await vehiclesService.garage(req.user!.id);
    res.json({ vehicles: [...garage.motorcycles, ...garage.cars] });
  } catch (e) {
    next(e);
  }
});

vehiclesRouter.get('/:id', async (req, res, next) => {
  try {
    res.json(await vehiclesService.get(req.user!.id, req.params.id));
  } catch (e) {
    next(e);
  }
});

vehiclesRouter.put('/:id', async (req, res, next) => {
  try {
    const dto = parseBody(updateSchema, req.body);
    res.json(await vehiclesService.update(req.user!.id, req.params.id, dto));
  } catch (e) {
    next(e);
  }
});

vehiclesRouter.delete('/:id', async (req, res, next) => {
  try {
    await vehiclesService.delete(req.user!.id, req.params.id);
    res.status(204).send();
  } catch (e) {
    next(e);
  }
});

// GET /api/vehicles/:id/costs - dokumentierter Alias auf die Wartungs-
// Kosten (Anforderung 8/14), delegiert an den MaintenanceService.
vehiclesRouter.get('/:id/costs', async (req, res, next) => {
  try {
    res.json(await maintenanceService.costs(req.user!.id, req.params.id));
  } catch (e) {
    next(e);
  }
});

// GET /api/vehicles/:id/specifications (Anforderung 14)
vehiclesRouter.get('/:id/specifications', async (req, res, next) => {
  try {
    res.json(await vehiclesService.specifications(req.user!.id, req.params.id));
  } catch (e) {
    next(e);
  }
});

// GET /api/vehicles/:id/reminders (Anforderung 14)
vehiclesRouter.get('/:id/reminders', async (req, res, next) => {
  try {
    res.json(await vehiclesService.reminders(req.user!.id, req.params.id));
  } catch (e) {
    next(e);
  }
});
