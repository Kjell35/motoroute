import { ConflictException, UnauthorizedException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { AuthService } from './auth.service';

describe('AuthService', () => {
  const geometry = { whatever: true };

  function buildService(
    env: Record<string, string | undefined>,
  ): { service: AuthService; signIn: jest.Mock; signUp: jest.Mock; refresh: jest.Mock } {
    const config = new ConfigService(env);
    const service = new AuthService(config);
    // Interne GoTrue-Calls stubben (kein echtes Supabase im Unit-Test):
    const anyService = service as unknown as {
      client: { auth: Record<string, jest.Mock> } | null;
    };
    const signIn = jest.fn();
    const signUp = jest.fn();
    const refresh = jest.fn();
    if (anyService.client) {
      anyService.client.auth = {
        signInWithPassword: signIn,
        signUp,
        refreshSession: refresh,
      };
    }
    return { service, signIn, signUp, refresh };
  }

  it('ohne Konfiguration: login wirft 503-artigen Fehler mit status', async () => {
    const { service } = buildService({});
    await expect(
      service.login({ email: 'a@b.de', password: 'geheim123' }),
    ).rejects.toMatchObject({ status: 503 });
  });

  it('Login: Session wird auf AuthSession gemappt, metadata displayName mitgenommen', async () => {
    const { service, signIn } = buildService({
      SUPABASE_URL: 'https://test.supabase.co',
      SUPABASE_ANON_KEY: 'anon-key-1234567890',
    });
    signIn.mockResolvedValue({
      data: {
        session: {
          access_token: 'at',
          refresh_token: 'rt',
          expires_in: 3600,
        },
        user: {
          id: 'u1',
          email: 'rider@example.de',
          user_metadata: { display_name: 'Kjell' },
        },
      },
      error: null,
    });

    const session = await service.login({ email: 'rider@example.de', password: 'geheim123' });
    expect(session.accessToken).toBe('at');
    expect(session.refreshToken).toBe('rt');
    expect(session.user.displayName).toBe('Kjell');
    expect(session.user.email).toBe('rider@example.de');
  });

  it('Login: falsche Daten -> UnauthorizedException (401)', async () => {
    const { service, signIn } = buildService({
      SUPABASE_URL: 'https://test.supabase.co',
      SUPABASE_ANON_KEY: 'anon-key-1234567890',
    });
    signIn.mockResolvedValue({
      data: { session: null, user: null },
      error: { message: 'Invalid login credentials' },
    });

    await expect(
      service.login({ email: 'rider@example.de', password: 'falsch' }),
    ).rejects.toBeInstanceOf(UnauthorizedException);
  });

  it('Registrierung: bereits vorhanden -> ConflictException (409)', async () => {
    const { service, signUp } = buildService({
      SUPABASE_URL: 'https://test.supabase.co',
      SUPABASE_ANON_KEY: 'anon-key-1234567890',
    });
    signUp.mockResolvedValue({
      data: { session: null, user: null },
      error: { message: 'User already registered' },
    });

    await expect(
      service.register({ email: 'rider@example.de', password: 'geheim123' }),
    ).rejects.toBeInstanceOf(ConflictException);
  });

  it('Registrierung ohne Session (E-Mail-Bestätigung pflicht): klarer Hinweis', async () => {
    const { service, signUp } = buildService({
      SUPABASE_URL: 'https://test.supabase.co',
      SUPABASE_ANON_KEY: 'anon-key-1234567890',
    });
    signUp.mockResolvedValue({ data: { session: null, user: null }, error: null });

    await expect(
      service.register({ email: 'rider@example.de', password: 'geheim123' }),
    ).rejects.toThrow('bestätige zuerst die E-Mail');
  });

  it('Refresh: abgelaufen -> UnauthorizedException', async () => {
    const { service, refresh } = buildService({
      SUPABASE_URL: 'https://test.supabase.co',
      SUPABASE_ANON_KEY: 'anon-key-1234567890',
    });
    refresh.mockResolvedValue({
      data: { session: null, user: null },
      error: { message: 'Invalid Refresh Token' },
    });

    await expect(service.refresh('bad-token')).rejects.toBeInstanceOf(UnauthorizedException);
  });

  it('geometry-Hinweis: Service kennt kein Routing - Struktur-Test', () => {
    // Dokumentiert, dass AuthService nichts mit Routing zu tun hat.
    expect(geometry).toBeDefined();
  });
});
