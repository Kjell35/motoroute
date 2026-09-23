import { Module } from '@nestjs/common';
import { SupabaseModule } from '../../supabase/supabase.module';
import { SearchModule } from '../search/search.module';
import { RideHistoryController } from './ride-history.controller';
import { RideHistoryService } from './ride-history.service';

/**
 * Fahrhistorie im Benutzerprofil: Auto-Sync aus abgeschlossenen
 * Navigationen, Privacy-Schalter (Default privat) und öffentliche
 * Profilsicht mit Karte (Strecken + Orte).
 */
@Module({
  imports: [SupabaseModule, SearchModule],
  controllers: [RideHistoryController],
  providers: [RideHistoryService],
})
export class RideHistoryModule {}
