import { Module } from '@nestjs/common';
import { SupabaseModule } from '../../supabase/supabase.module';
import { AuthProvider, OptionalAuthProvider, SupabaseAuthService } from '../../guards';
import { TelemetryController } from './telemetry.controller';
import { TelemetryService } from './telemetry.service';

@Module({
  imports: [SupabaseModule],
  controllers: [TelemetryController],
  // Die Guards (AuthProvider/OptionalAuthProvider) injizieren
  // SupabaseAuthService - ohne Registrierung hier bricht der
  // DI-Container beim Start ab (genau wie im Chat-Modul-Doku-Kommentar:
  // -> DER GESAMTE SERVER startet nicht / Render-Rollback).
  providers: [TelemetryService, SupabaseAuthService, AuthProvider, OptionalAuthProvider],
})
export class TelemetryModule {}
