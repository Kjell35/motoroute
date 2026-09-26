import type { PrismaClient } from '@prisma/client';
import bcrypt from 'bcryptjs';
import { env } from '../src/config/env';

/**
 * Idempotenter Start-Seed (kein Ersatz für `npm run seed` mit vollem
 * Katalog, aber sorgt dafür, dass eine frische Instanz nutzbar ist):
 * - Bootstrap-Admin aus env.ADMIN_EMAIL/PASSWORD, falls kein Admin existiert
 * - leerer Katalog: minimaler Hinweis (volles Seeding via `npm run seed`)
 */
export async function seedIfEmpty(prisma: PrismaClient): Promise<void> {
  const adminCount = await prisma.user.count({ where: { role: 'admin' } });
  if (adminCount === 0 && env.ADMIN_EMAIL && env.ADMIN_PASSWORD) {
    const passwordHash = await bcrypt.hash(env.ADMIN_PASSWORD, 12);
    await prisma.user.upsert({
      where: { email: env.ADMIN_EMAIL.toLowerCase() },
      update: { role: 'admin' },
      create: {
        email: env.ADMIN_EMAIL.toLowerCase(),
        passwordHash,
        displayName: env.ADMIN_DISPLAY_NAME ?? 'Garage Admin',
        role: 'admin',
      },
    });
    console.log(`Bootstrap-Admin angelegt: ${env.ADMIN_EMAIL}`);
  }

  const manufacturerCount = await prisma.manufacturer.count();
  if (manufacturerCount === 0) {
    console.warn('Katalog ist leer - `npm run seed` ausführen, um Starter-Fahrzeugdaten einzuspielen.');
  }
}
