import { Router } from 'express';
import { z } from 'zod';
import { requireAuth } from '../auth/auth.middleware';
import { maintenanceService } from './maintenance.service';
import { parseBody } from '../auth/auth.routes';
import { vehicleIdOf } from '../../common/params';
import { MAINTENANCE_TYPES, maintenanceTypesFor } from '../../common/maintenance-types';

export const maintenanceRouter = Router({ mergeParams: true });
maintenanceRouter.use(requireAuth);

const createSchema = z.object({
  type: z.string().min(2).max(40),
  performedAt: z.string().datetime().or(z.string().date()),
  odometerKm: z.number().int().min(0).max(5_000_000),
  nextDueDate: z.string().datetime().or(z.string().date()).optional(),
  nextDueOdometerKm: z.number().int().min(0).optional(),
  costCents: z.number().int().min(0).optional(),
  shopName: z.string().max(120).optional(),
  notes: z.string().max(2000).optional(),
});

const updateSchema = createSchema.partial();

// Wartungstypen-Katalog fuer das UI (nach Fahrzeugkategorie filterbar).
maintenanceRouter.get('/types', (req, res) => {
  const category = req.query['category'] === 'car' ? 'car' : req.query['category'] === 'motorcycle' ? 'motorcycle' : undefined;
  res.json({ types: category ? maintenanceTypesFor(category) : MAINTENANCE_TYPES });
});

maintenanceRouter.get('/', async (req, res, next) => {
  try {
    const type = typeof req.query['type'] === 'string' ? req.query['type'] : undefined;
    res.json(await maintenanceService.list(req.user!.id, vehicleIdOf(req), type));
  } catch (e) {
    next(e);
  }
});

maintenanceRouter.post('/', async (req, res, next) => {
  try {
    const dto = parseBody(createSchema, req.body);
    res.status(201).json(await maintenanceService.create(req.user!.id, vehicleIdOf(req), dto));
  } catch (e) {
    next(e);
  }
});

// Historie (chronologisch) - eigene Route vor :id (Anforderung 7).
maintenanceRouter.get('/history', async (req, res, next) => {
  try {
    res.json(await maintenanceService.history(req.user!.id, vehicleIdOf(req)));
  } catch (e) {
    next(e);
  }
});

// Kosten-Aggregation (Anforderung 8).
maintenanceRouter.get('/costs', async (req, res, next) => {
  try {
    res.json(await maintenanceService.costs(req.user!.id, vehicleIdOf(req)));
  } catch (e) {
    next(e);
  }
});

maintenanceRouter.put('/:id', async (req, res, next) => {
  try {
    const dto = parseBody(updateSchema, req.body);
    res.json(await maintenanceService.update(req.user!.id, req.params.id, dto));
  } catch (e) {
    next(e);
  }
});

maintenanceRouter.delete('/:id', async (req, res, next) => {
  try {
    await maintenanceService.delete(req.user!.id, req.params.id);
    res.status(204).send();
  } catch (e) {
    next(e);
  }
});
