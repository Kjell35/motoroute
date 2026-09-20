import { Module } from '@nestjs/common';
import { SupabaseModule } from '../../supabase/supabase.module';
import { PoiController } from './poi.controller';
import { PoiService } from './poi.service';

@Module({
  imports: [SupabaseModule],
  controllers: [PoiController],
  providers: [PoiService],
  // Export fuer WeatherService (Sturm-Warnung schlägt Schutz-POIs nach).
  // Fehlender Export liess den DI-Container beim Start abbrechen - der
  // GESAMTE Server startete nicht (Ursache: "Verbindung zum Server
  // fehlgeschlagen" in der App).
  exports: [PoiService],
})
export class PoiModule {}
