import { HttpException, HttpStatus, Inject, Injectable } from '@nestjs/common';
import { SupabaseClient } from '@supabase/supabase-js';
import { SUPABASE_CLIENT } from '../../supabase/supabase.module';
import { AuthenticatedUser } from '../../guards';

/**
 * UserService - verwaltet die Benutzerprofile in Supabase.
 *
 * Trennung von Auth (Supabase Auth) und Profildaten (eigene Tabelle
 * `users`): Supabase-Auth speichert Email/Password/Provider, die
 * eigene Tabelle speichert Profil-Felder (displayName, avatarUrl).
 * Das ist die von Supabase empfohlene Struktur (auth.users vs.
 * public.users via Webhook-Upsert).
 */
@Injectable()
export class UserService {
  private readonly table = 'users';

  constructor(@Inject(SUPABASE_CLIENT) private readonly supabase: SupabaseClient | null) {}

  /**
   * Lädt das Profil des aktuell authentifizierten Nutzers.
   * Liefert Profil-Zeile, erzeugt bei Bedarf einen Fallback aus den
   * JWT-Claims, falls der Webhook-Upsert noch nicht gelaufen ist.
   */
  async getMe(user: AuthenticatedUser): Promise<unknown> {
    // Kein Supabase konfiguriert: definierte Antwort statt 500.
    if (this.supabase == null) {
      throw new HttpException(
        { error: 'DB_NOT_CONFIGURED', message: 'User storage is not configured' },
        HttpStatus.SERVICE_UNAVAILABLE,
      );
    }
    const { data, error } = await this.supabase
      .from(this.table)
      .select('id, email, display_name, avatar_url, plan, updated_at')
      .eq('id', user.id)
      .maybeSingle();

    if (error) {
      // Schema noch nicht eingespielt (PGRST205=Tabelle fehlt,
      // PGRST204=Spalte fehlt, schema cache nach Migration): definiertes
      // Default-Profil statt 500 - der Login selbst bleibt damit voll
      // funktionsfaehig, auch VOR dem SQL-Editor-Paste.
      const code = (error as { code?: string }).code;
      const schemaMissing =
        code === 'PGRST205' ||
        code === 'PGRST204' ||
        /relation .* does not exist|column .* does not exist|schema cache/i.test(error.message);
      if (!schemaMissing) {
        throw new HttpException(
          { error: 'DB_ERROR', message: error.message },
          HttpStatus.INTERNAL_SERVER_ERROR,
        );
      }
    }

    // Profil noch nicht angelegt: leeres Default-Profil melden, statt
    // 500 zu werfen - der Nutzer ist ja gültig authentifiziert, es
    // fehlt nur die Zeile.
    const profile =
      data ?? {
        id: user.id,
        email: user.email ?? null,
        display_name: null,
        avatar_url: null,
        plan: 'free' as const,
        updated_at: null,
      };
    return { ...profile, entitlements: this.entitlementsFor(profile.plan) };
  }

  /**
   * Premium-Vorbereitung (Feature-Gate nur im Backend): Aktuell
   * Testphase - ALLES kostenlos freigeschaltet, egal welcher Plan.
   * Später wird hier allein der Premium-Zweig beschnitten; das Frontend
   * liest nur dieses Objekt und hat keine eigene Paywall-Logik.
   */
  private entitlementsFor(plan: string | null | undefined) {
    const premium = plan === 'premium';
    return {
      plan: premium ? ('premium' as const) : ('free' as const),
      // Solange kein Zahlungsdienst aktiv ist, sind alle Features offen.
      liveGroupRides: true,
      weatherRadar: true,
      offlineMaps: true,
      unlimitedGroups: true,
    };
  }

  /**
   * Aktualisiert das Profil des aktuell authentifizierten Nutzers.
   * User-ID kommt IMMER aus dem validierten JWT, nie aus dem Body -
   * sonst könnte ein Nutzer fremde Profile überschreiben.
   */
  async updateMe(user: AuthenticatedUser, dto: { displayName?: string; avatarUrl?: string }): Promise<unknown> {
    if (this.supabase == null) {
      throw new HttpException(
        { error: 'DB_NOT_CONFIGURED', message: 'User storage is not configured' },
        HttpStatus.SERVICE_UNAVAILABLE,
      );
    }
    const { data, error } = await this.supabase
      .from(this.table)
      .update({
        ...(dto.displayName !== undefined ? { display_name: dto.displayName } : {}),
        ...(dto.avatarUrl !== undefined ? { avatar_url: dto.avatarUrl } : {}),
        updated_at: new Date().toISOString(),
      })
      .eq('id', user.id)
      .select()
      .single();

    if (error) {
      // PGRST116 = no row updated: Profil existiert noch nicht.
      if ((error as { code?: string }).code === 'PGRST116') {
        const created = await this.upsert({
          id: user.id,
          email: user.email,
          displayName: dto.displayName,
          avatarUrl: dto.avatarUrl,
        });
        return created;
      }
      throw new HttpException(
        { error: 'DB_ERROR', message: error.message },
        HttpStatus.INTERNAL_SERVER_ERROR,
      );
    }

    return data;
  }

  /**
   * Ändert das Passwort des angemeldeten Nutzers.
   * Das aktuelle Passwort wird per echtem GoTrue-Login verifiziert -
   * ein gestohlenes Access-Token allein reicht also nicht. Die
   * eigentliche Änderung läuft über die Admin-API (Service-Key bleibt
   * im Backend, nie im Frontend).
   */
  async updatePassword(
    user: AuthenticatedUser,
    dto: { currentPassword: string; newPassword: string },
  ): Promise<{ changed: boolean }> {
    if (this.supabase == null) {
      throw new HttpException(
        { error: 'DB_NOT_CONFIGURED', message: 'User storage is not configured' },
        HttpStatus.SERVICE_UNAVAILABLE,
      );
    }
    if (!user.email) {
      throw new HttpException(
        { error: 'NO_EMAIL', message: 'Konto hat keine E-Mail-Adresse' },
        HttpStatus.BAD_REQUEST,
      );
    }
    const { error: signInError } = await this.supabase.auth.signInWithPassword({
      email: user.email,
      password: dto.currentPassword,
    });
    if (signInError) {
      throw new HttpException(
        { error: 'WRONG_PASSWORD', message: 'Aktuelles Passwort ist falsch' },
        HttpStatus.UNAUTHORIZED,
      );
    }
    const { error } = await this.supabase.auth.admin.updateUserById(user.id, {
      password: dto.newPassword,
    });
    if (error) {
      throw new HttpException(
        { error: 'UPDATE_FAILED', message: error.message },
        HttpStatus.INTERNAL_SERVER_ERROR,
      );
    }
    return { changed: true };
  }

  /**
   * Löscht das Konto endgültig (auth.users). Alle Profil-/Chat-/Gruppen-
   * Zeilen fallen per ON DELETE CASCADE mit weg - das ist im Schema so
   * verdrahtet und datenschutzfreundlich.
   */
  async deleteMe(user: AuthenticatedUser): Promise<{ deleted: boolean }> {
    if (this.supabase == null) {
      throw new HttpException(
        { error: 'DB_NOT_CONFIGURED', message: 'User storage is not configured' },
        HttpStatus.SERVICE_UNAVAILABLE,
      );
    }
    const { error } = await this.supabase.auth.admin.deleteUser(user.id);
    if (error) {
      throw new HttpException(
        { error: 'DELETE_FAILED', message: error.message },
        HttpStatus.INTERNAL_SERVER_ERROR,
      );
    }
    return { deleted: true };
  }
  async upsert(body: { id: string; email?: string; displayName?: string; avatarUrl?: string }): Promise<unknown> {
    if (this.supabase == null) {
      throw new HttpException(
        { error: 'DB_NOT_CONFIGURED', message: 'User storage is not configured' },
        HttpStatus.SERVICE_UNAVAILABLE,
      );
    }
    const { data, error } = await this.supabase
      .from(this.table)
      .upsert(
        {
          id: body.id,
          email: body.email ?? null,
          display_name: body.displayName ?? null,
          ...(body.avatarUrl !== undefined ? { avatar_url: body.avatarUrl } : {}),
          updated_at: new Date().toISOString(),
        },
        { onConflict: 'id' },
      )
      .select()
      .single();

    if (error) {
      throw new HttpException(
        { error: 'DB_ERROR', message: error.message },
        HttpStatus.INTERNAL_SERVER_ERROR,
      );
    }

    return data;
  }
}
