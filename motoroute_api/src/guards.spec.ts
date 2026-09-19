import { ExecutionContext, UnauthorizedException } from '@nestjs/common';
import { AuthProvider, OptionalAuthProvider, SupabaseAuthService } from './guards';

function mockConfig(): { get: (key: string) => string } {
  return {
    get: (key: string) =>
      key === 'SUPABASE_URL'
        ? 'https://real-project.supabase.co'
        : 'service-role-key-with-sufficient-length-1234567890',
  };
}

function requestWith(header?: string): { headers: Record<string, string> } {
  const headers: Record<string, string> = {};
  if (header) headers.authorization = header;
  return { headers };
}

function contextWith(request: unknown): ExecutionContext {
  return {
    switchToHttp: () => ({ getRequest: () => request }),
  } as unknown as ExecutionContext;
}

describe('SupabaseAuthService.validateToken', () => {
  it('returns null when Supabase rejects the token', async () => {
    const service = new SupabaseAuthService(mockConfig() as never);
    jest.spyOn(service['adminClient']!.auth, 'getUser').mockResolvedValue({
      data: { user: null },
      error: { message: 'invalid token' } as never,
    } as never);

    expect(await service.validateToken('bad-token')).toBeNull();
  });

  it('returns id and email for a valid token', async () => {
    const service = new SupabaseAuthService(mockConfig() as never);
    jest.spyOn(service['adminClient']!.auth, 'getUser').mockResolvedValue({
      data: { user: { id: 'u-1', email: 'rider@example.com' } },
      error: null,
    } as never);

    const user = await service.validateToken('good-token');
    expect(user).toEqual({ id: 'u-1', email: 'rider@example.com' });
  });

  it('degrades to a null client without Supabase config instead of throwing', async () => {
    const service = new SupabaseAuthService({ get: () => undefined } as never);
    // Ohne Konfiguration gilt jeder Token als nicht validiert (anonym).
    expect(await service.validateToken('anything')).toBeNull();
  });
});

describe('OptionalAuthProvider', () => {
  it('accepts a request without any Authorization header (anonymous)', async () => {
    const auth = { validateToken: jest.fn() } as unknown as SupabaseAuthService;
    const guard = new OptionalAuthProvider(auth);
    const request = requestWith();

    await expect(guard.canActivate(contextWith(request))).resolves.toBe(true);
    expect(auth.validateToken).not.toHaveBeenCalled();
  });

  it('attaches req.user for a valid token', async () => {
    const auth = {
      validateToken: jest.fn().mockResolvedValue({ id: 'u-1' }),
    } as unknown as SupabaseAuthService;
    const guard = new OptionalAuthProvider(auth);
    const request = requestWith('Bearer good-token');

    await expect(guard.canActivate(contextWith(request))).resolves.toBe(true);
    // Auch der Optional-Guard reicht das Token durch (RLS-scoped Aufrufe).
    expect((request as { user?: unknown }).user).toEqual({ id: 'u-1', token: 'good-token' });
  });

  it('treats an invalid token as anonymous instead of rejecting', async () => {
    const auth = {
      validateToken: jest.fn().mockResolvedValue(null),
    } as unknown as SupabaseAuthService;
    const guard = new OptionalAuthProvider(auth);
    const request = requestWith('Bearer expired-token');

    await expect(guard.canActivate(contextWith(request))).resolves.toBe(true);
    expect((request as { user?: unknown }).user).toBeUndefined();
  });
});

describe('AuthProvider', () => {
  it('rejects a request without token with 401 semantics', async () => {
    const guard = new AuthProvider({} as SupabaseAuthService);
    await expect(guard.canActivate(contextWith(requestWith()))).rejects.toThrow(
      UnauthorizedException,
    );
  });

  it('rejects an invalid token', async () => {
    const auth = {
      validateToken: jest.fn().mockResolvedValue(null),
    } as unknown as SupabaseAuthService;
    const guard = new AuthProvider(auth);

    await expect(
      guard.canActivate(contextWith(requestWith('Bearer invalid'))),
    ).rejects.toThrow(UnauthorizedException);
  });

  it('attaches req.user and passes for a valid token', async () => {
    const auth = {
      validateToken: jest.fn().mockResolvedValue({ id: 'u-7', email: 'x@y.de' }),
    } as unknown as SupabaseAuthService;
    const guard = new AuthProvider(auth);
    const request = requestWith('Bearer valid');

    await expect(guard.canActivate(contextWith(request))).resolves.toBe(true);
    // req.user trägt jetzt auch das Roh-Token (Chat-Service ruft Supabase
    // mit den Rechten DES NUTZERS auf, damit RLS die Durchsetzung bleibt).
    expect((request as { user?: unknown }).user).toEqual({
      id: 'u-7',
      email: 'x@y.de',
      token: 'valid',
    });
  });
});
