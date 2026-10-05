import * as dotenv from 'dotenv';
// override:true ist PFLICHT (nicht der 'dotenv/config'-Kurzimport):
// auf Dev-Maschinen kann z. B. PORT=0 in der Shell liegen - NestJS
// merged process.env ÜBER die .env-Datei, ohne override gewinnt der
// Shell-Wert und app.listen(0) bindet einen Zufallsport.
dotenv.config({ override: true });
import { ValidationPipe } from '@nestjs/common';
import { NestFactory } from '@nestjs/core';
import { WsAdapter } from '@nestjs/platform-ws';
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

  // WICHTIG (Chat-Realtime-Fix): Ohne diese Zeile laesst NestJS den
  // Default-Socket.IO-Adapter laufen (platform-socket.io ist installiert).
  // Der Chat-Gateway + Flutter-Client sprechen aber das rohe WS-Protokoll
  // ({"event": ..., "data": ...} Frames) - der Socket.IO-Adapter beantwortet
  // die Upgrade-Requests nie, der Render-Proxy antwortet 502 und der Chat
  // faellt ueberall auf (langsames) REST-Polling zurueck. Der WsAdapter
  // bindet das Gateway (/v1/chat/ws) an denselben HTTP-Server.
  app.useWebSocketAdapter(new WsAdapter(app));

  const port = process.env.PORT ?? 3000;
  await app.listen(port);
}

bootstrap();
