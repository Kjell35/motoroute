import express from 'express';
import helmet from 'helmet';
import cors from 'cors';
import rateLimit from 'express-rate-limit';
import swaggerUi from 'swagger-ui-express';

import { env, isProd } from './config/env';
import { prisma } from './common/prisma';
import { authRouter } from './modules/auth/auth.routes';
import { catalogRouter } from './modules/catalog/catalog.routes';
import { vehiclesRouter } from './modules/vehicles/vehicles.routes';
import { maintenanceRouter } from './modules/maintenance/maintenance.routes';
import { tiresRouter } from './modules/tires/tires.routes';
import { fuelRouter } from './modules/fuel/fuel.routes';
import { documentsRouter } from './modules/documents/documents.routes';
import { adminRouter } from './modules/admin/admin.routes';
import { openapiSpec } from './docs/openapi';
import { seedIfEmpty } from '../prisma/seed-runner';

const app = express();

app.use(helmet());
app.use(
  cors({
    origin: env.CORS_ORIGINS === '*' ? true : env.CORS_ORIGINS.split(',').map((s) => s.trim()),
  }),
);
app.use(express.json({ limit: '1mb' }));
app.use(rateLimit({ windowMs: 60_000, max: 300, standardHeaders: true }));

// Health (ohne Auth - fuer Uptime-Monitoring).
app.get('/api/health', (_req, res) => {
  res.json({ status: 'ok', service: 'garage-api', time: new Date().toISOString() });
});

// Swagger/OpenAPI (Anforderung 14).
app.use('/api/docs', swaggerUi.serve, swaggerUi.setup(openapiSpec));
app.get('/api/openapi.json', (_req, res) => {
  res.json(openapiSpec);
});

// Module
app.use('/api/auth', authRouter);
app.use('/api/catalog', catalogRouter);
app.use('/api/vehicles', vehiclesRouter);
app.use('/api/vehicles/:vehicleId/maintenance', maintenanceRouter);
app.use('/api/vehicles/:vehicleId/tires', tiresRouter);
app.use('/api/vehicles/:vehicleId/fuel', fuelRouter);
app.use('/api/vehicles/:vehicleId/documents', documentsRouter);
app.use('/api/admin', adminRouter);

// 404
app.use((_req, res) => {
  res.status(404).json({ error: 'NOT_FOUND', message: 'Endpunkt existiert nicht (siehe /api/docs)' });
});

// Einheitlicher Fehler-Handler.
interface HttpError extends Error {
  status?: number;
  code?: string;
}

app.use((err: HttpError, _req: express.Request, res: express.Response, _next: express.NextFunction) => {
  const status = err.status ?? 500;
  if (status >= 500) {
    console.error(err);
  }
  res.status(status).json({
    error: err.code ?? 'INTERNAL_ERROR',
    message: isProd && status >= 500 ? 'Interner Fehler' : err.message,
  });
});

async function main(): Promise<void> {
  // Katalog-Starterdaten einspielen (echte Fahrzeugdaten, kein Dummy).
  await seedIfEmpty(prisma);

  app.listen(env.PORT, () => {
    console.log(`garage-api läuft auf Port ${env.PORT} (${env.NODE_ENV})`);
    console.log(`  Swagger: http://localhost:${env.PORT}/api/docs`);
  });
}

void main().catch((e) => {
  console.error('Start fehlgeschlagen:', e);
  process.exit(1);
});
