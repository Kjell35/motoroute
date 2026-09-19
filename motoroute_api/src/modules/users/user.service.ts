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
      .select('id, email, display_name, avatar_url, updated_at')
      .eq('id', user.id)
      .maybeSingle();

    if (error) {
      throw new HttpException(
        { error: 'DB_ERROR', message: error.message },
        HttpStatus.INTERNAL_SERVER_ERROR,
      );
    }

    // Profil noch nicht angelegt (Webhook verzögert): leeres Default-
    // Profil melden, statt 500 zu werfen - der Nutzer ist ja gültig
    // authentifiziert, es fehlt nur die Zeile.
    return (
      data ?? {
        id: user.id,
        email: user.email ?? null,
        display_name: null,
        avatar_url: null,
        updated_at: null,
      }
    );
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
   * Legt einen Nutzer an oder aktualisiert ihn (Upsert).
   * Wird typischerweise von einem Supabase-Webhook aufgerufen, wenn
   * sich ein Nutzer das erste Mal einloggt.
   */
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
