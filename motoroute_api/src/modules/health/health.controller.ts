import { Controller, Get, Inject, Logger, Res } from '@nestjs/common';
import { SupabaseClient } from '@supabase/supabase-js';
import type { Response } from 'express';
import { SUPABASE_CLIENT } from '../../supabase/supabase.module';

/**
 * Health-Endpunkte (anonym erreichbar).
 *
 * GET /v1/health       - reine Prozess-Antwort; zeigt nur, dass der Dienst
 *                        läuft (App-Verbindungstest). Berührt Supabase NICHT.
 * GET /v1/health/deps  - prüft die Abhängigkeiten wirklich: eine Query gegen
 *                        Postgres und ein Request an GoTrue (Auth). Genau
 *                        diese beiden Anfragen halten das Supabase-Free-Projekt
 *                        aktiv; ohne sie pausiert es nach ~1 Woche Inaktivität
 *                        und der Login fällt aus (so im November 2026 passiert,
 *                        obwohl die alten Keep-Alive-Workflows liefen).
 *
 * Antwort: 200 bei ok, 503 sobald eine Abhängigkeit nicht antwortet. Details
 * bleiben im Server-Log - die öffentliche Antwort nennt nur den Zustand.
 */
@Controller('v1/health')
export class HealthController {
  private readonly logger = new Logger(HealthController.name);

  constructor(@Inject(SUPABASE_CLIENT) private readonly db: SupabaseClient | null) {}

  @Get()
  check(): { status: string; service: string; time: string } {
    return {
      status: 'ok',
      service: 'motoroute-api',
      time: new Date().toISOString(),
    };
  }

  @Get('deps')
  async deps(
    @Res({ passthrough: true }) res: Response,
  ): Promise<Record<string, string>> {
    if (!this.db) {
      res.status(503);
      return {
        status: 'degraded',
        db: 'not_configured',
        auth: 'not_configured',
        time: new Date().toISOString(),
      };
    }

    const [db, auth] = await Promise.all([this.checkDb(this.db), this.checkAuth(this.db)]);
    const ok = db === 'ok' && auth === 'ok';
    res.status(ok ? 200 : 503);
    return {
      status: ok ? 'ok' : 'degraded',
      db,
      auth,
      time: new Date().toISOString(),
    };
  }

  /** Ein Kopf-Request mit Count: erreicht Postgres, lädt aber keine Zeilen. */
  private async checkDb(db: SupabaseClient): Promise<string> {
    try {
      const { error } = await db
        .from('users')
        .select('id', { count: 'exact', head: true })
        .limit(1);
      if (error) {
        this.logger.error(`health/deps db failed: ${error.code} ${error.message}`);
        return 'error';
      }
      return 'ok';
    } catch (e) {
      this.logger.error(`health/deps db threw: ${(e as Error).message}`);
      return 'error';
    }
  }

  /** Echter GoTrue-Request (Admin-API, Service-Role) - hält den Auth-Dienst aktiv. */
  private async checkAuth(db: SupabaseClient): Promise<string> {
    try {
      const { error } = await db.auth.admin.listUsers({ page: 1, perPage: 1 });
      if (error) {
        this.logger.error(`health/deps auth failed: ${error.status} ${error.message}`);
        return 'error';
      }
      return 'ok';
    } catch (e) {
      this.logger.error(`health/deps auth threw: ${(e as Error).message}`);
      return 'error';
    }
  }
}
