import { Module } from '@nestjs/common';
import { SupabaseModule } from '../../supabase/supabase.module';
import { PairingController } from './pairing.controller';
import { PairingPlanPageController } from './pairing-plan-page.controller';
import { PairingService } from './pairing.service';

@Module({
  // SUPABASE_CLIENT (Service-Role) kommt aus dem gemeinsamen Modul.
  imports: [SupabaseModule],
  controllers: [PairingController, PairingPlanPageController],
  providers: [PairingService],
})
export class PairingModule {}
