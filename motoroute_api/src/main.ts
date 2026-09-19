import * as dotenv from 'dotenv';
// override:true ist PFLICHT (nicht der 'dotenv/config'-Kurzimport):
// auf Dev-Maschinen kann z. B. PORT=0 in der Shell liegen - NestJS
// merged process.env ÜBER die .env-Datei, ohne override gewinnt der
// Shell-Wert und app.listen(0) bindet einen Zufallsport.
dotenv.config({ override: true });
import { ValidationPipe } from '@nestjs/common';
import { NestFactory } from '@nestjs/core';
import { AppModule } from './app.module';

async function bootstrap() {
  const app = await NestFactory.create(AppModule);

  // whitelist strips unknown properties instead of erroring on them -
  // forbidNonWhitelisted flips that to a hard 400, which we want here:
  // a client sending an unexpected field (e.g. a leftover debug flag)
  // should fail loudly during development, not be silently dropped.
  app.useGlobalPipes(
    new ValidationPipe({
      whitelist: true,
      forbidNonWhitelisted: true,
      transform: true,
    }),
  );

  const port = process.env.PORT ?? 3000;
  await app.listen(port);
}

bootstrap();
