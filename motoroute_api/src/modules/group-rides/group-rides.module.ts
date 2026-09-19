import { Module } from '@nestjs/common';
import { SupabaseModule } from '../../supabase/supabase.module';
import { AuthProvider, SupabaseAuthService } from '../../guards';
import { ChatModule } from '../chat/chat.module';
import { BikerPoisModule } from '../biker-pois/biker-pois.module';
import { GroupRidesController } from './group-rides.controller';
import { GroupRidesService } from './group-rides.service';
import { GroupRidesGateway } from './group-rides.gateway';

/**
 * Live-Gruppenfahrt: REST + WS. BikerPoisModule liefert die Realtime-
 * Bridge (Ride-Relais zum POI-Dienst) - Positionen von verifizierten
 * Mitgliedern werden dort eingespeist und als groupride.radar-Events
 * an die Ride-Räume verteilt.
 */
@Module({
  imports: [SupabaseModule, ChatModule, BikerPoisModule],
  controllers: [GroupRidesController],
  providers: [GroupRidesService, GroupRidesGateway, AuthProvider, SupabaseAuthService],
})
export class GroupRidesModule {}
