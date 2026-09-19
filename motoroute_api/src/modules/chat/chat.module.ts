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
})
export class ChatModule {}
