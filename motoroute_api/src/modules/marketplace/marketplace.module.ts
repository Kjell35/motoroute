import { Module } from '@nestjs/common';
import { MulterModule } from '@nestjs/platform-express';
import { SupabaseModule } from '../../supabase/supabase.module';
import { AuthProvider, SupabaseAuthService } from '../../guards';
import { ChatModule } from '../chat/chat.module';
import { SearchModule } from '../search/search.module';
import { MarketplaceController } from './marketplace.controller';
import { MarketplaceService } from './marketplace.service';
import { GeminiReviewService } from './gemini-review.service';

/**
 * Marktplatz-Modul (Fahrzeugteile & Zubehoer).
 *
 * Abhaengigkeiten:
 *  - ChatModule: Verkaeufer-Kontakt laeuft ueber den BESTEHENDEN
 *    privaten Chat (Anforderung 15) - ChatService wird injiziert.
 *  - SearchModule: SearchService wird fuer Geo-Helfer geteilt
 *    (Projektkonvention seit RideHistoryModule).
 *
 * Multer: memoryStorage (Default bei AnyFilesInterceptor ohne dest) -
 * die Buffer gehen direkt an Supabase Storage, nichts landet auf der
 * Render-Disk.
 */
@Module({
  imports: [
    SupabaseModule,
    ChatModule,
    SearchModule,
    MulterModule.register({ limits: { fileSize: 8 * 1024 * 1024, files: 8 } }),
  ],
  controllers: [MarketplaceController],
  // AuthProvider + SupabaseAuthService: guard-genutzte Module stellen
  // den JWT-Guard selbst bereit (Projektkonvention - der fehlende
  // Eintrag hat bereits einmal den Bootstrap gekillt, siehe
  // RideHistoryModule-Kommentar).
  providers: [MarketplaceService, GeminiReviewService, AuthProvider, SupabaseAuthService],
})
export class MarketplaceModule {}
