import {
  ConflictException,
  Injectable,
  Logger,
  UnauthorizedException,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { createClient, SupabaseClient } from '@supabase/supabase-js';
import { AuthSession, LoginDto, RegisterDto } from './auth.dto';
import { PUBLIC_CONVERSATION_ID } from '../chat/chat.service';

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

  /**
   * Admin-Client (Service-Key) - zwei Pflichtaufgaben:
   * 1. AUTH_AUTO_CONFIRM=true: Registrierung serverseitig bestätigen
   *    (Testphase ohne E-Mail-Zustell-Risiko; der Nutzer bekommt seine
   *    Session SOFORT, ohne auf eine Mail warten zu müssen).
   * 2. displayName sauber in die GoTrue-User-Metadaten schreiben
   *    (der frühere Weg via anonymem updateUser konnte ohne Session
   *    gar nicht funktionieren - stiller Fail).
   */
  private readonly adminClient: SupabaseClient | null;
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

    const autoConfirm = /^(1|true|yes)$/i.test(
      this.config.get<string>('AUTH_AUTO_CONFIRM') ?? '',
    );
    this.adminClient =
      this.configured && serviceKey && serviceKey.startsWith('sb_secret_')
        ? createClient(url!, serviceKey, {
            auth: { autoRefreshToken: false, persistSession: false },
          })
        : null;
    if (autoConfirm && this.adminClient == null) {
      this.logger.warn(
        'AUTH_AUTO_CONFIRM=true, aber kein sb_secret_-Service-Key gesetzt - Auto-Confirm bleibt aus',
      );
    }
  }

  /**
   * Provisioning nach erfolgreicher Registrierung: Profilzeile
   * (users-Tabelle, Grundlage für Chat-Suche/Anzeigenamen) + Beitritt
   * zum öffentlichen Chat. Beides idempotent (ON CONFLICT ignore), so
   * dass ein Re-Run nie doppelte Zeilen erzeugt. RLS erlaubt beide
   * Operationen bewusst (users_self_insert, conv_member_insert für
   * type='public'); die conversations-Zeile des öffentlichen Chats
   * legt der Admin-Client an, falls sie noch fehlt (erst-Setup).
   */
  private async provisionUser(userId: string, email: string | undefined, displayName?: string): Promise<void> {
    const db = this.adminClient;
    if (!db) return;
    try {
      // 1) Profilzeile (Webhook-freier Pfad: direkt hier, nicht erst
      //    beim ersten Profilabruf).
      await db.from('users').upsert(
        {
          id: userId,
          email: email ?? null,
          ...(displayName ? { display_name: displayName } : {}),
        },
        { onConflict: 'id', ignoreDuplicates: true },
      );

      // 2) Öffentliche Chat-Konversation sicherstellen (idempotent).
      await db.from('conversations').upsert(
        { id: PUBLIC_CONVERSATION_ID, type: 'public' },
        { onConflict: 'id', ignoreDuplicates: true },
      );

      // 3) Auto-Join: Mitglied des öffentlichen Chats werden.
      await db.from('conversation_members').upsert(
        { conversation_id: PUBLIC_CONVERSATION_ID, user_id: userId, role: 'member' },
        { onConflict: 'conversation_id,user_id', ignoreDuplicates: true },
      );
    } catch (e) {
      // Provisioning darf die Registrierung nie scheitern lassen -
      // der ChatService heilt fehlende Profile selbst (getProfile).
      this.logger.warn(`Provisioning unvollständig (ignoriert): ${String(e)}`);
    }
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
    // Self-Healing: Nutzer aus der Zeit vor dem Auto-Provisioning bekommen
    // Profilzeile + öffentlichen Chat beim ersten Login nachgerüstet.
    await this.provisionUser(data.user.id, data.user.email);
    return this.toSession(data.session, data.user);
  }

  async register(dto: RegisterDto): Promise<AuthSession> {
    const client = this.requireClient();

    // Admin-Pfad (Testphase / private Nutzung): Konto direkt anlegen und
    // bestätigen. Kein E-Mail-Versand => keine Zustell-Risiken und keine
    // GoTrue-Rate-Limits (over_email_send_rate_limit). Aktiv, sobald ein
    // sb_secret_-Service-Key konfiguriert ist.
    if (this.adminClient) {
      const { error: adminError } = await this.adminClient.auth.admin.createUser({
        email: dto.email,
        password: dto.password,
        email_confirm: true,
        ...(dto.displayName ? { user_metadata: { display_name: dto.displayName } } : {}),
      });
      if (!adminError) {
        const { data: signIn, error: signInError } = await client.auth.signInWithPassword({
          email: dto.email,
          password: dto.password,
        });
        if (!signInError && signIn.session && signIn.user) {
          await this.provisionUser(signIn.user.id, dto.email, dto.displayName);
          return this.toSession(signIn.session, signIn.user);
        }
        throw new UnauthorizedException(
          'Konto erstellt - bitte melde dich mit E-Mail und Passwort an',
        );
      }
      if (/already|exists|registered|duplicate/i.test(adminError.message)) {
        throw new ConflictException('Diese E-Mail ist bereits registriert');
      }
      this.logger.warn(
        `Admin-Registrierung fehlgeschlagen (${adminError.message}) - Fallback auf Standard-Signup`,
      );
    }

    const { data, error } = await client.auth.signUp({
      email: dto.email,
      password: dto.password,
      // displayName als User-Metadaten: landet via Webhook in der
      // users-Tabelle (raw_user_meta_data->>display_name).
      ...(dto.displayName ? { options: { data: { display_name: dto.displayName } } } : {}),
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
      // Projekt mit E-Mail-Bestätigungspflicht (ohne Admin-Pfad): klarer
      // Hinweis statt undefined.
      throw new UnauthorizedException(
        'Bitte bestätige zuerst die E-Mail (Link im Postfach) und melde dich dann an',
      );
    }

    await this.provisionUser(data.user.id, dto.email, dto.displayName);
    return this.toSession(data.session, data.user);
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
