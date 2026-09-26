import { Router } from 'express';
import { z } from 'zod';
import { requireAuth } from '../auth/auth.middleware';
import { catalogService } from './catalog.service';
import { parseBody } from '../auth/auth.routes';

export const catalogRouter = Router();

/**
 * Katalog-Routen (oeffentlich fuer angemeldete Nutzer - die Fahrzeug-
 * datenbank ist Lesegut fuer alle, Schreiben nur Admin, siehe admin.routes).
 */

// Suche: GET /api/catalog/search?q=BMW+GS&category=motorcycle&year=2024
catalogRouter.get('/search', requireAuth, async (req, res, next) => {
  try {
    const schema = z.object({
      q: z.string().max(120).default(''),
      category: z.enum(['motorcycle', 'car']).optional(),
      year: z.coerce.number().int().min(1900).max(2100).optional(),
      limit: z.coerce.number().int().min(1).max(50).default(25),
    });
    const { q, category, year, limit } = parseBody(schema, req.query);
    res.json(await catalogService.search(q ?? '', category, year, limit));
  } catch (e) {
    next(e);
  }
});

catalogRouter.get('/manufacturers', requireAuth, async (_req, res, next) => {
  try {
    res.json({ manufacturers: await catalogService.manufacturers() });
  } catch (e) {
    next(e);
  }
});

catalogRouter.get('/manufacturers/:id/models', requireAuth, async (req, res, next) => {
  try {
    res.json({ models: await catalogService.models(req.params.id) });
  } catch (e) {
    next(e);
  }
});

catalogRouter.get('/models/:id/variants', requireAuth, async (req, res, next) => {
  try {
    res.json({ variants: await catalogService.variants(req.params.id) });
  } catch (e) {
    next(e);
  }
});

// Technische Daten einer Variante: GET /api/catalog/variants/:id/specs?year=2024
catalogRouter.get('/variants/:id/specs', requireAuth, async (req, res, next) => {
  try {
    const schema = z.object({ year: z.coerce.number().int().min(1900).max(2100).optional() });
    const { year } = parseBody(schema, req.query);
    res.json(await catalogService.specsForVariant(req.params.id, year));
  } catch (e) {
    next(e);
  }
});
