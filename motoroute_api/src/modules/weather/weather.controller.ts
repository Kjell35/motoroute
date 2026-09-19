import { Body, Controller, Post } from '@nestjs/common';
import {
  ArrayMaxSize,
  ArrayMinSize,
  IsArray,
  IsNumber,
  Max,
  Min,
} from 'class-validator';
import { RouteWeatherReport, WeatherService } from './weather.service';

/**
 * Polyline als [[lng, lat], ...] - exakt die Geometrie, die
 * POST /v1/routes zurückgibt, damit die App sie unverändert
 * durchreichen kann (kein klientseitiges Umschreiben).
 */
export class RouteWeatherDto {
  @IsArray()
  @ArrayMinSize(2)
  @ArrayMaxSize(2000)
  @IsNumber({}, { each: true })
  @ArrayMaxSize(200)
  geometry: number[][];

  /** Gesamte Fahrzeit der Route (Sekunden) für die ETA-Zuordnung. */
  @IsNumber()
  @Min(0)
  @Max(60 * 60 * 24 * 7)
  durationSeconds: number;
}

@Controller('v1/weather')
export class WeatherController {
  constructor(private readonly weatherService: WeatherService) {}

  /**
   * Wetter-Radar für eine geplante Route. Bewusst anonym wie das
   * Routing (siehe routing.controller.ts): Das Radar ist ein reines
   * Hinweis-Feature ohne Nutzerbezug.
   */
  @Post('route')
  async getRouteWeather(@Body() dto: RouteWeatherDto): Promise<RouteWeatherReport> {
    return this.weatherService.getRouteWeather(dto.geometry, dto.durationSeconds);
  }
}
