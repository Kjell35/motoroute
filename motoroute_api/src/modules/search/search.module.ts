import { Module } from '@nestjs/common';
import { SearchController } from './search.controller';
import { SearchService } from './search.service';
import { TomTomGeocoder } from './tomtom-geocoder';

@Module({
  controllers: [SearchController],
  providers: [SearchService, TomTomGeocoder],
})
export class SearchModule {}
