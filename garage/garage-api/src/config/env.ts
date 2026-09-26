import dotenv from 'dotenv';
import { z } from 'zod';

dotenv.config({ override: true }); // .env gewinnt gegen System-Werte (z. B. globales PORT=0 auf manchen Windows-Systemen)

/**
 * Alle Zugangsdaten ueber Environment Variables (Anforderung 18).
 * Zod validiert beim Start - die App startet NICHT mit halben Configs.
 */
const schema = z.object({
  DATABASE_URL: z.string().min(1, 'DATABASE_URL fehlt'),
  PORT: z.coerce.number().int().positive().default(4100),
  NODE_ENV: z.enum(['development', 'test', 'production']).default('development'),
  JWT_SECRET: z.string().min(32, 'JWT_SECRET muss min. 32 Zeichen sein (siehe .env.example)'),
  JWT_EXPIRES_IN_SECONDS: z.coerce.number().int().positive().default(3600),
  ADMIN_EMAIL: z.string().email().optional(),
  ADMIN_PASSWORD: z.string().min(8).optional(),
  ADMIN_DISPLAY_NAME: z.string().optional(),
  CORS_ORIGINS: z.string().default('*'),
});

const parsed = schema.safeParse(process.env);
if (!parsed.success) {
  console.error('Ungültige Environment-Konfiguration:');
  for (const issue of parsed.error.issues) {
    console.error(`  - ${issue.path.join('.')}: ${issue.message}`);
  }
  process.exit(1);
}

export const env = parsed.data;
export const isProd = env.NODE_ENV === 'production';
