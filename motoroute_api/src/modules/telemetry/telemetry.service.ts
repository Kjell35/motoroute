import {
  ForbiddenException,
  HttpException,
  HttpStatus,
  Injectable,
  ServiceUnavailableException,
} from '@nestjs/common';
import { createHash } from 'crypto';
import { Inject } from '@nestjs/common';
import { SupabaseClient } from '@supabase/supabase-js';
import { AuthenticatedUser } from '../../guards';
import { SUPABASE_CLIENT } from '../../supabase/supabase.module';
import { CreateErrorReportDto } from './telemetry.controller';

/**
 * Telemetry-Service: anonymes Fehler-Reporting.
 *
 * Speichert fehlgeschlagene Aktionen OHNE personenbezogene Daten.
 * user_hash = SHA-256(user_id + TELEMETRY_SALT) - erlaubt "wie viele
 * EINZELNE Nutzer betroffen sind", ohne dass die Hashes auf Accounts
 * rückschließen (das Salz liegt nur auf dem Server). Ohne Anmeldung
 * bleibt der Bericht ganz ohne Hash-Bindung ('anon').
 */
@Injectable()
export class TelemetryService {
  private readonly adminClient: SupabaseClient | null;

  constructor(@Inject(SUPABASE_CLIENT) adminClient: SupabaseClient | null) {
    this.adminClient = adminClient;
  }

  async reportError(
    userId: string | undefined,
    salt: string,
    dto: CreateErrorReportDto,
  ): Promise<void> {
    // Graceful Degradierung: Ohne DB einfach verwerfen - Reporting darf
    // NIE die App-Funktion beeinträchtigen (Fire-and-forget-Kontrakt).
    if (!this.adminClient) return;

    const userHash = userId
      ? createHash('sha256').update(`${userId}:${salt}`).digest('hex')
      : 'anon';

    const { error } = await this.adminClient.from('app_error_reports').insert({
      user_hash: userHash,
      category: dto.category,
      cause: dto.cause.slice(0, 300),
      http_status: dto.httpStatus ?? null,
      platform: dto.platform,
      app_version: dto.appVersion,
    });
    if (error) {
      // Tabelle fehlt (Migration nicht angewendet) -> still ignorieren,
      // damit die App nie wegen Reporting scheitert.
      return;
    }
  }

  /** Admin: letzte Berichte + kurze Aggregation (Kategorien, betroffene Hashes). */
  async adminList(user: AuthenticatedUser, limit = 100) {
    if (!this.adminClient) {
      throw new ServiceUnavailableException({
        error: 'DB_NOT_CONFIGURED',
        message: 'Telemetry nicht konfiguriert',
      });
    }
    await this.requireAdmin(user);

    const { data, error } = await this.adminClient
      .from('app_error_reports')
      .select('id, user_hash, category, cause, http_status, platform, app_version, created_at')
      .order('created_at', { ascending: false })
      .limit(Math.min(limit, 200));
    if (error) {
      // Migration 0008 noch nicht im Dashboard angewendet -> PostgREST
      // meldet fehlende Tabelle. Das ist ein definierter Zustand, kein
      // Fehler: leere Auswertung liefern, damit die Admin-Ansicht in
      // der App nicht in einen 500 laeuft.
      const code = (error as { code?: string }).code ?? '';
      if (
        code === 'PGRST205' ||
        code === '42P01' ||
        /could not find the table/i.test(error.message)
      ) {
        return { reports: [], summary: [], total: 0 };
      }
      throw new HttpException(
        { error: 'TELEMETRY_READ_FAILED', message: error.message },
        HttpStatus.INTERNAL_SERVER_ERROR,
      );
    }

    const rows = (data ?? []) as Record<string, unknown>[];
    const byCategory: Record<string, number> = {};
    const usersPerCategory: Record<string, Set<string>> = {};
    for (const r of rows) {
      const cat = String(r.category ?? 'other');
      byCategory[cat] = (byCategory[cat] ?? 0) + 1;
      (usersPerCategory[cat] ??= new Set()).add(String(r.user_hash));
    }
    const summary = Object.entries(byCategory)
      .map(([category, count]) => ({
        category,
        count,
        affectedUsers: usersPerCategory[category]?.size ?? 0,
      }))
      .sort((a, b) => b.count - a.count);

    return { reports: rows, summary, total: rows.length };
  }

  private async requireAdmin(user: AuthenticatedUser): Promise<void> {
    if (!this.adminClient) return;
    const { data, error } = await this.adminClient
      .from('users')
      .select('role')
      .eq('id', user.id)
      .maybeSingle();
    if (error) {
      throw new HttpException(
        { error: 'ROLE_LOOKUP_FAILED', message: 'Rolle konnte nicht geprüft werden' },
        HttpStatus.INTERNAL_SERVER_ERROR,
      );
    }
    if ((data as { role?: string } | null)?.role !== 'admin') {
      throw new ForbiddenException({ error: 'FORBIDDEN', message: 'Kein Zugriff' });
    }
  }
}
