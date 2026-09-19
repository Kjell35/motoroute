import { Module } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { createClient, SupabaseClient } from '@supabase/supabase-js';

export const SUPABASE_CLIENT = 'SUPABASE_CLIENT';

function isPlaceholder(url: string | undefined, key: string | undefined): boolean {
  // Der .env.example-Platzhalter oder leere Werte = nicht konfiguriert.
  if (!url || !key) return true;
  return url.includes('your-project.supabase.co') || key.length < 20;
}

/**
 * Supabase-Modul.
 *
 * Bündelt einen einzigen, anwendungsweiten Supabase-Client, der mit
 * der SERVICE-ROLE-Key initialisiert ist. Das ist bewusst KEIN
 * anon-Key: der Client läuft auf dem Server, darf also auch RLS-
 * bypassende Operationen durchführen.
 *
 * Degradierung: Solange kein echtes Supabase-Projekt existiert
 * (Platzhalter in .env), wirft die Factory NICHT mehr - sonst startet
 * der ganze Dienst nicht und selbst GraphHopper-Routing/Traffic/OSM-
 * POIs wären tot. Stattdessen wird ein null-Client geliefert; die
 * abhängigen Services (PoiService.queryDatabase, UserService) prüfen
 * darauf und liefern definierte Leerwerte/Fehler statt zu crashen.
 * Produktion setzt echte Keys - dann funktioniert alles ohne Code-
 * Änderung.
 */
@Module({
  imports: [],
  providers: [
    {
      provide: SUPABASE_CLIENT,
      useFactory: (config: ConfigService): SupabaseClient | null => {
        const url = config.get<string>('SUPABASE_URL');
        const key = config.get<string>('SUPABASE_SERVICE_ROLE_KEY');

        if (isPlaceholder(url, key)) {
          return null;
        }
        return createClient(url!, key!, {
          auth: {
            autoRefreshToken: false,
            persistSession: false,
          },
        });
      },
      inject: [ConfigService],
    },
  ],
  // ConfigService wird NICHT hier exportiert: das root ConfigModule
  // (app.module, isGlobal) stellt ihn überall bereit; ein Export aus
  // diesem Modul heraus scheitert, weil das bare `ConfigModule`
  // (ohne forRoot) keinen ConfigService-Provider enthält.
  exports: [SUPABASE_CLIENT],
})
export class SupabaseModule {}
