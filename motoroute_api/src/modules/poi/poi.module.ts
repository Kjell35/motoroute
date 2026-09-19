import { Module } from '@nestjs/common';
import { SupabaseModule } from '../../supabase/supabase.module';
import { PoiController } from './poi.controller';
import { PoiService } from './poi.service';

@Module({
  imports: [SupabaseModule],
  controllers: [PoiController],
  providers: [PoiService],
})
export class PoiModule {}
