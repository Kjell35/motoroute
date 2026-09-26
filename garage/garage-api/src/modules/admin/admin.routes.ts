import { Router } from 'express';
import { z } from 'zod';
import { prisma } from '../../common/prisma';
import { requireAuth, requireAdmin } from '../auth/auth.middleware';
import { parseBody } from '../auth/auth.routes';
import { isSpecKey, SPEC_KEYS } from '../../common/spec-keys';

export const adminRouter = Router();
adminRouter.use(requireAuth, requireAdmin);

/**
 * Admin-Bereich (Anforderung 16): zentrale Fahrzeugdatenbank pflegen.
 * Deaktivieren statt löschen - referenzierte Fahrzeuge behalten ihren
 * Katalog-Snapshot und die Suche blendet Inaktive aus.
 */

const manufacturerSchema = z.object({
  name: z.string().min(1).max(80),
  country: z.string().max(60).optional(),
  isActive: z.boolean().optional(),
});

const modelSchema = z.object({
  name: z.string().min(1).max(120),
  category: z.enum(['motorcycle', 'car']),
  isActive: z.boolean().optional(),
});

const variantSchema = z.object({
  name: z.string().min(1).max(120),
  years: z.string().max(30).optional(),
});

const specSchema = z.object({
  key: z.string().min(2).max(60),
  value: z.string().min(1).max(200),
  unit: z.string().max(30).optional(),
  yearFrom: z.number().int().min(1900).max(2100).optional(),
  yearTo: z.number().int().min(1900).max(2100).optional(),
});

// --- Hersteller ---
adminRouter.post('/manufacturers', async (req, res, next) => {
  try {
    const dto = parseBody(manufacturerSchema, req.body);
    const manufacturer = await prisma.manufacturer.create({ data: dto });
    res.status(201).json(manufacturer);
  } catch (e) {
    next(e);
  }
});

adminRouter.put('/manufacturers/:id', async (req, res, next) => {
  try {
    const dto = parseBody(manufacturerSchema.partial(), req.body);
    const manufacturer = await prisma.manufacturer.update({ where: { id: req.params.id }, data: dto });
    res.json(manufacturer);
  } catch (e) {
    next(e);
  }
});

adminRouter.delete('/manufacturers/:id', async (req, res, next) => {
  try {
    // Deaktivieren statt löschen (Anforderung 16 "Fahrzeuge deaktivieren").
    const manufacturer = await prisma.manufacturer.update({
      where: { id: req.params.id },
      data: { isActive: false },
    });
    res.json(manufacturer);
  } catch (e) {
    next(e);
  }
});

// --- Modelle ---
adminRouter.post('/manufacturers/:id/models', async (req, res, next) => {
  try {
    const dto = parseBody(modelSchema, req.body);
    const model = await prisma.model.create({
      data: { ...dto, manufacturerId: req.params.id },
    });
    res.status(201).json(model);
  } catch (e) {
    next(e);
  }
});

adminRouter.put('/models/:id', async (req, res, next) => {
  try {
    const dto = parseBody(modelSchema.partial(), req.body);
    const model = await prisma.model.update({ where: { id: req.params.id }, data: dto });
    res.json(model);
  } catch (e) {
    next(e);
  }
});

// --- Varianten ---
adminRouter.post('/models/:id/variants', async (req, res, next) => {
  try {
    const dto = parseBody(variantSchema, req.body);
    const variant = await prisma.variant.create({
      data: { ...dto, modelId: req.params.id },
    });
    res.status(201).json(variant);
  } catch (e) {
    next(e);
  }
});

adminRouter.put('/variants/:id', async (req, res, next) => {
  try {
    const dto = parseBody(variantSchema.partial(), req.body);
    const variant = await prisma.variant.update({ where: { id: req.params.id }, data: dto });
    res.json(variant);
  } catch (e) {
    next(e);
  }
});

// --- Technische Daten ---
adminRouter.post('/variants/:id/specs', async (req, res, next) => {
  try {
    const dto = parseBody(specSchema, req.body);
    if (!isSpecKey(dto.key)) {
      res.status(400).json({
        error: 'UNKNOWN_SPEC_KEY',
        message: `Unbekannter Spec-Schlüssel. Erlaubt: siehe GET /api/admin/spec-keys`,
      });
      return;
    }
    const spec = await prisma.vehicleSpec.create({ data: { ...dto, variantId: req.params.id } });
    res.status(201).json(spec);
  } catch (e) {
    next(e);
  }
});

adminRouter.put('/specs/:id', async (req, res, next) => {
  try {
    const dto = parseBody(specSchema.partial(), req.body);
    const spec = await prisma.vehicleSpec.update({ where: { id: req.params.id }, data: dto });
    res.json(spec);
  } catch (e) {
    next(e);
  }
});

adminRouter.delete('/specs/:id', async (req, res, next) => {
  try {
    await prisma.vehicleSpec.delete({ where: { id: req.params.id } });
    res.status(204).send();
  } catch (e) {
    next(e);
  }
});

// Erlaubte Spec-Schluessel fuer das Admin-UI.
adminRouter.get('/spec-keys', (_req, res) => {
  res.json({ keys: SPEC_KEYS });
});
