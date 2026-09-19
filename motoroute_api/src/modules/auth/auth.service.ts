import {
  ConflictException,
  Injectable,
  Logger,
  UnauthorizedException,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { createClient, SupabaseClient } from '@supabase/supabase-js';
import { AuthSession, LoginDto, RegisterDto } from './auth.dto';

/**
 * Auth-Service: E-Mail/Passwort-Login gegen Supabase GoTrue.
 *
 * Design-Regeln (Projekt-Konventionen):
 * - Der Service ist die EINZIGE Stelle, die Bearer-Tokens ausstellt;
 *   alle anderen Module bleiben beim verifizierenden AuthProvider.
 * - Fehler werden auf klare HTTP-Codes gemappt (401 falsche Daten,
 *   409 bereits registriert) statt Supabase-Rohfehler durchzureichen.
 * - displayName wird nach der Registrierung im Profil-Store gesetzt
 *   (upsert des users-Moduls), damit Chat/Gruppen direkt einen Namen
 *   haben statt "Rider 0815".
 */
@Injectable()
export class AuthService {
  private readonly logger = new Logger(AuthService.name);
  private readonly client: SupabaseClient | null;
  private readonly configured: boolean;

  constructor(
    private readonly config: ConfigService,
  ) {
    const url = this.config.get<string>('SUPABASE_URL');
    const anonKey = this.config.get<string>('SUPABASE_ANON_KEY');
    const serviceKey = this.config.get<string>('SUPABASE_SERVICE_ROLE_KEY');

    // GoTrue-LogIn braucht den anon key (identify client). Ist er nicht
    // gesetzt, nutzen wir bewusst den Service-Role-Key NICHT (der wuerde
    // admin-Zugriffe erlaubt); stattdessen degradiert Auth mit 503.
    const key = anonKey ?? serviceKey;
    this.configured =
      Boolean(url) &&
      Boolean(key) &&
      !url!.includes('your-project.supabase.co');

    this.client = this.configured
      ? createClient(url!, key!, {
          auth: { autoRefreshToken: false, persistSession: false },
        })
      : null;
  }

  get isConfigured(): boolean {
    return this.configured;
  }

  private requireClient(): SupabaseClient {
    if (!this.client) {
      const err = new Error('SUPABASE_NOT_CONFIGURED') as Error & { status?: number };
      err.status = 503;
      throw err;
    }
    return this.client;
  }

  async login(dto: LoginDto): Promise<AuthSession> {
    const client = this.requireClient();
    const { data, error } = await client.auth.signInWithPassword({
      email: dto.email,
      password: dto.password,
    });
    if (error || !data.session || !data.user) {
      throw new UnauthorizedException('E-Mail oder Passwort falsch');
    }
    return this.toSession(data.session, data.user);
  }

  async register(dto: RegisterDto): Promise<AuthSession> {
    const client = this.requireClient();
    const { data, error } = await client.auth.signUp({
      email: dto.email,
      password: dto.password,
    });

    if (error) {
      const alreadyExists = /already|exists|registered/i.test(error.message);
      if (alreadyExists) {
        throw new ConflictException('Diese E-Mail ist bereits registriert');
      }
      this.logger.warn(`Registrierung fehlgeschlagen: ${error.message}`);
      throw new UnauthorizedException(error.message);
    }
    if (!data.session || !data.user) {
      // Projekt mit E-Mail-Bestätigungspflicht: ohne Session gibt es
      // nichts zu übergeben - klarer Hinweis statt undefined.
      throw new UnauthorizedException(
        'Bitte bestätige zuerst die E-Mail (Link im Postfach) und melde dich dann an',
      );
    }

    const session = this.toSession(data.session, data.user);
    if (dto.displayName) {
      try {
        await client.auth.updateUser({ data: { display_name: dto.displayName } });
      } catch (e) {
        // Namen nicht zur Registrierungspflicht machen.
        this.logger.warn(`displayName-Update fehlgeschlagen: ${String(e)}`);
      }
    }
    return session;
  }

  async refresh(refreshToken: string): Promise<AuthSession> {
    const client = this.requireClient();
    const { data, error } = await client.auth.refreshSession({ refresh_token: refreshToken });
    if (error || !data.session) {
      throw new UnauthorizedException('Sitzung abgelaufen - bitte neu anmelden');
    }
    return this.toSession(data.session, data.user ?? undefined);
  }

  async logout(): Promise<void> {
    const client = this.requireClient();
    try {
      // Ohne Token-Argument wird die serverseitige Session des
      // (persistenzlosen) Service-Clients invalidiert; der Client
      // verwirft seine Sitzung lokal - best-effort.
      await client.auth.signOut();
    } catch (e) {
      this.logger.warn(`Logout-Fehler (ignoriert): ${String(e)}`);
    }
  }

  async profile(accessToken: string): Promise<AuthSession['user']> {
    const client = this.requireClient();
    const { data, error } = await client.auth.getUser(accessToken);
    if (error || !data.user) {
      throw new UnauthorizedException('Sitzung ungültig');
    }
    const meta = (data.user.user_metadata ?? {}) as Record<string, unknown>;
    return {
      id: data.user.id,
      email: data.user.email ?? undefined,
      ...(typeof meta['display_name'] === 'string'
        ? { displayName: meta['display_name'] }
        : {}),
    };
  }

  private toSession(
    session: {
      access_token: string;
      refresh_token: string;
      expires_in: number;
    },
    user: { id: string; email?: string | null; user_metadata?: Record<string, unknown> } | null | undefined,
  ): AuthSession {
    const meta = (user?.user_metadata ?? {}) as Record<string, unknown>;
    return {
      accessToken: session.access_token,
      refreshToken: session.refresh_token,
      expiresInSeconds: session.expires_in ?? 3600,
      user: {
        id: user?.id ?? '',
        email: user?.email ?? undefined,
        ...(typeof meta['display_name'] === 'string'
          ? { displayName: meta['display_name'] }
          : {}),
      },
    };
  }
}
