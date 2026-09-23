import { Module } from '@nestjs/common';
import { SearchController } from './search.controller';
import { SearchService } from './search.service';
import { TomTomGeocoder } from './tomtom-geocoder';

@Module({
  controllers: [SearchController],
  providers: [SearchService, TomTomGeocoder],
  // Exportiert fuer RideHistoryModule (Region-Ableitung via Reverse-
  // Geocoding beim Tour-Sync). Ohne Export crasht der DI-Container
  // beim Bootstrap (Deploy update_failed am 23.09.).
  exports: [SearchService],
})
export class SearchModule {}
