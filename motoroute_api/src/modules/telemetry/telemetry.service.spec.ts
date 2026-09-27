import { ForbiddenException, ServiceUnavailableException } from '@nestjs/common';
import { CreateErrorReportDto } from './telemetry.controller';
import { TelemetryService } from './telemetry.service';

/** Minimaler Supabase-Stub, der nur das braucht, was der Service nutzt. */
function makeClient(overrides: {
  insertError?: { message: string } | null;
  selectError?: { message: string } | null;
  rows?: Record<string, unknown>[];
  role?: string;
}) {
  return {
    from: (_table: string) => ({
      insert: (_values: unknown) => ({
        error: overrides.insertError ?? null,
      }),
      select: (_cols: string) => ({
        order: (_col: string, _opts: unknown) => ({
          limit: (_n: number) =>
            Promise.resolve({ data: overrides.rows ?? [], error: overrides.selectError ?? null }),
        }),
        eq: (_col: string, _val: string) => ({
          maybeSingle: () =>
            Promise.resolve({ data: overrides.role ? { role: overrides.role } : null, error: null }),
        }),
      }),
    }),
  } as never;
}

const adminUser = { id: 'admin-1', email: 'a@b.c', role: 'admin' } as never;
const normalUser = { id: 'u-1', email: 'u@b.c', role: 'user' } as never;

const dto: CreateErrorReportDto = {
  category: 'chat.load',
  cause: 'HTTP 401 - Sitzung abgelaufen',
  platform: 'android',
  appVersion: '0.4.6',
};

describe('TelemetryService', () => {
  it('verwirft Berichte ohne DB (graceful), statt zu werfen', async () => {
    const svc = new TelemetryService(null);
    await expect(svc.reportError(undefined, 'salt', dto)).resolves.toBeUndefined();
  });

  it('insertet mit Tages-Hash fuer angemeldete Nutzer', async () => {
    let captured: unknown;
    const client = {
      from: (t: string) => ({
        insert: (v: Record<string, unknown>) => {
          captured = { table: t, ...v };
          return { error: null };
        },
      }),
    } as never;
    const svc = new TelemetryService(client);
    await svc.reportError('user-42', 'salt', dto);
    const row = captured as Record<string, unknown>;
    expect(row.table).toBe('app_error_reports');
    expect(row.user_hash).toMatch(/^[0-9a-f]{64}$/);
    expect(row.category).toBe('chat.load');
    expect(row.http_status).toBeNull();
  });

  it('nimmt http_status aus dem DTO, kuerzt lange Ursachen', async () => {
    let captured: Record<string, unknown> | undefined;
    const client = {
      from: () => ({
        insert: (v: Record<string, unknown>) => {
          captured = v;
          return { error: null };
        },
      }),
    } as never;
    const svc = new TelemetryService(client);
    await svc.reportError('user-42', 'salt', {
      ...dto,
      cause: 'x'.repeat(500),
      httpStatus: 403,
    });
    expect(captured?.http_status).toBe(403);
    expect((captured?.cause as string).length).toBe(300);
  });

  it('adminList: Nicht-Admins bekommen 403', async () => {
    const svc = new TelemetryService(makeClient({ role: 'user' }));
    await expect(svc.adminList(normalUser)).rejects.toBeInstanceOf(ForbiddenException);
  });

  it('adminList: aggregiert Kategorien und betroffene Nutzer', async () => {
    const svc = new TelemetryService(
      makeClient({
        role: 'admin',
        rows: [
          { id: '1', user_hash: 'h1', category: 'chat.load' },
          { id: '2', user_hash: 'h1', category: 'chat.load' },
          { id: '3', user_hash: 'h2', category: 'crash' },
        ],
      }),
    );
    const res = await svc.adminList(adminUser);
    expect(res.total).toBe(3);
    const chat = res.summary.find((s) => s.category === 'chat.load');
    expect(chat?.count).toBe(2);
    expect(chat?.affectedUsers).toBe(1);
  });

  it('adminList: ohne DB 503', async () => {
    const svc = new TelemetryService(null);
    await expect(svc.adminList(adminUser)).rejects.toBeInstanceOf(ServiceUnavailableException);
  });
});
