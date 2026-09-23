import { Module } from '@nestjs/common';
import { EventEmitterModule } from '@nestjs/event-emitter';
import { SupabaseModule } from '../../supabase/supabase.module';
import { AuthProvider, SupabaseAuthService } from '../../guards';
import { ChatController } from './chat.controller';
import { ChatService } from './chat.service';
import { ChatGateway } from './chat.gateway';

/**
 * Chat-Modul (Architekturregel Abschnitt 39): fasst alle Chat-Komponenten
 * zusammen, ohne an einzelne Screens gekoppelt zu sein. Die App konsumiert
 * ausschließlich REST + WS unter /v1/chat.
 *
 * Der EventEmitter ist global genug, um Service-Ereignisse (sendMessage,
 * deleteMessage, typing) an das Gateway weiterzureichen - bei horizontaler
 * Skalierung wird hier ein Redis-basierter Transport eingesetzt (TODO).
 */
@Module({
  imports: [SupabaseModule, EventEmitterModule.forRoot()],
  controllers: [ChatController],
  providers: [ChatService, ChatGateway, AuthProvider, SupabaseAuthService],
  // ChatGateway muss exportiert sein: BikerPoisGateway (POI-Push) und die
  // Gruppenrouten-Realtime nutzen dieselbe WS-Verbindung. ChatService
  // wird vom Marktplatz injiziert (Verkäufer-Kontakt = privater Chat).
  // Ohne Exporte kann das abhängige Modul nicht injizieren -> der
  // DI-Container bricht beim Start ab -> DER GESAMTE SERVER startet
  // nicht (die echte Ursache von "Verbindung zum Server fehlgeschlagen"
  // in der App - und des update_failed-Deploys von v0.3.15).
  exports: [ChatGateway, ChatService],
})
export class ChatModule {}
