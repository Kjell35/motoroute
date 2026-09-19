import { Module } from '@nestjs/common';
import { PoiModule } from '../poi/poi.module';
import { WeatherController } from './weather.controller';
import { WeatherService } from './weather.service';

@Module({
  imports: [PoiModule],
  controllers: [WeatherController],
  providers: [WeatherService],
})
export class WeatherModule {}
