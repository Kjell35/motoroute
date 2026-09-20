import { Module } from '@nestjs/common';
import { SupabaseModule } from '../../supabase/supabase.module';
import { AuthProvider, SupabaseAuthService } from '../../guards';
import { ChatModule } from '../chat/chat.module';
import { BikerPoisController } from './biker-pois.controller';
import { BikerPoisService } from './biker-pois.service';
import { BikerPoisRealtimeBridge } from './biker-pois.realtime';
import { BikerPoisGateway } from './biker-pois.gateway';

/**
 * Biker-POI-Modul (BFF-Proxy zum eigenständigen Kuratierungs-Dienst):
 * REST-Delta-Sync + WS-Push. Der Socket.IO-Uplink (RealtimeBridge) läuft
 * server-intern zum Dienst; Richtung App geht ausschließlich das
 * authentifizierte bikerpoi.batch-Frame über /v1/chat/ws (Gateway).
 * ChatModule wird importiert, weil das Gateway die Socket-Verwaltung des
 * ChatGateway wiederverwendet (dieselbe Verbindung wie Chat/Gruppenrouten).
 */
@Module({
  imports: [SupabaseModule, ChatModule],
  controllers: [BikerPoisController],
  providers: [BikerPoisService, BikerPoisRealtimeBridge, BikerPoisGateway, AuthProvider, SupabaseAuthService],
  // Bridge-Export fuer GroupRidesService (Live-Gruppenfahrt-Positionsuplink).
  exports: [BikerPoisRealtimeBridge],
})
export class BikerPoisModule {}
