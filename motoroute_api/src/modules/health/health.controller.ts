import { Controller, Get } from '@nestjs/common';

/**
 * Health-Endpunkt (anonym erreichbar).
 *
 * Dient dem App-Verbindungstest (Einstellungen > Server & Verbindung):
 * Wenn dieser Aufruf klappt, sind Host, Port und Routing der BFF-Instanz
 * erreichbar - unabhaengig von Supabase/GraphHopper, deren Erreichbarkeit
 * erst echte Feature-Aufrufe zeigen koennen.
 */
@Controller('v1/health')
export class HealthController {
  @Get()
  check(): { status: string; service: string; time: string } {
    return {
      status: 'ok',
      service: 'motoroute-api',
      time: new Date().toISOString(),
    };
  }
}
