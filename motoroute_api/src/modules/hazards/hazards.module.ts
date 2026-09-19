import { Module } from '@nestjs/common';
import { SupabaseModule } from '../../supabase/supabase.module';
import { AuthProvider, SupabaseAuthService } from '../../guards';
import { HazardsController } from './hazards.controller';
import { HazardsService } from './hazards.service';

/**
 * Community-Gefahrenradar: Meldung + Abfrage von Gefahrenstellen
 * (Rollsplitt, Sperrungen, Baustellen, Ölspuren). Alle Persistenz- und
 * Autorisierungslogik liegt in schema_hazards.sql (RLS + SECURITY
 * DEFINER-RPCs) - der Service ist ein thin client.
 */
@Module({
  imports: [SupabaseModule],
  controllers: [HazardsController],
  providers: [HazardsService, AuthProvider, SupabaseAuthService],
})
export class HazardsModule {}
