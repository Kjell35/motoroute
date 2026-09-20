import { Module } from '@nestjs/common';
import { SupabaseModule } from '../../supabase/supabase.module';
import { AuthProvider, SupabaseAuthService } from '../../guards';
import { AuthController } from './auth.controller';
import { AuthService } from './auth.service';

@Module({
  // SupabaseAuthService + AuthProvider (JWT-Guard) brauchen das
  // SupabaseModule bzw. den konfigurierten Client - ohne Import brach
  // der DI-Container beim Start ab (der Server startete GAR NICHT,
  // echte Ursache von "Verbindung zum Server fehlgeschlagen").
  imports: [SupabaseModule],
  controllers: [AuthController],
  providers: [AuthService, AuthProvider, SupabaseAuthService],
})
export class AuthModule {}
