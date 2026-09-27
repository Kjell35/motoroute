import { Module } from '@nestjs/common';
import { SupabaseModule } from '../../supabase/supabase.module';
import { AuthProvider, SupabaseAuthService } from '../../guards';
import { BadgesController } from './badges.controller';
import { BadgesService } from './badges.service';

/**
 * Badges-Modul ("Pass-Knacker" & Trophäen).
 *
 * ACHTUNG (gleiche Falle wie im Chat-/Telemetry-Modul): Die Guards
 * (AuthProvider) injizieren SupabaseAuthService - ohne Registrierung
 * hier bricht der DI-Container beim Start ab -> Render-Rollback.
 */
@Module({
  imports: [SupabaseModule],
  controllers: [BadgesController],
  providers: [BadgesService, SupabaseAuthService, AuthProvider],
})
export class BadgesModule {}
