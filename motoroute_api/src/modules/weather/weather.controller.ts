import { Body, Controller, Post } from '@nestjs/common';
import {
  IsNumber,
  Max,
  Min,
  ValidateBy,
  ValidationArguments,
  buildMessage,
} from 'class-validator';
import { RouteWeatherReport, WeatherService } from './weather.service';

/**
 * Validiert eine Polyline im Route-Format [[lng, lat], ...] - exakt die
 * Geometrie, die POST /v1/routes zurückgibt und die App unverändert
 * durchreicht.
 *
 * Bewusst ein eigener Validator statt @IsNumber({ each: true }): "each"
 * validiert die ELEMENTE von geometry - das sind aber Arrays, keine
 * Zahlen, sodass das App-Format IMMER mit 400 abgelehnt wurde und der
 * Wetter-Radar in Produktion unbenutzbar war (Audit 03.10.2026: App-
 * Format -> 400, flaches Array -> 500 im Service; kein gültiges Format
 * existierte). Zusätzlich prüft er pro Punkt Bereich und Länge 2.
 *
 * Cap 50.000 Punkte (~1 MB worst case): Lange Touren (z. B. Köln ->
 * Stilfser Joch) haben ~17.000 Punkte. Der Service sampelt ohnehin auf
 * wenige Wetter-Samples herunter; der Cap schützt nur vor Missbrauch.
 * Ab v0.4.9 verdichtet die App vor dem Senden auf 2.000 Punkte.
 */
const MAX_ROUTE_POINTS = 50_000;

const IsLngLatPolyline = (maxPoints: number = MAX_ROUTE_POINTS) =>
  ValidateBy({
    name: 'isLngLatPolyline',
    constraints: [maxPoints],
    validator: {
      validate(value: unknown, args?: ValidationArguments): boolean {
        const [max] = args!.constraints as number[];
        if (!Array.isArray(value) || value.length < 2 || value.length > max) {
          return false;
        }
        return value.every(
          (p) =>
            Array.isArray(p) &&
            p.length === 2 &&
            Number.isFinite(p[0]) &&
            Number.isFinite(p[1]) &&
            p[0] >= -180 &&
            p[0] <= 180 && // lng
            p[1] >= -90 &&
            p[1] <= 90, // lat
        );
      },
      defaultMessage: buildMessage(
        (eachPrefix) =>
          `${eachPrefix}$property muss eine Polyline [[lng, lat], ...] mit 2..$constraint1 Punkten sein`,
      ),
    },
  });

export class RouteWeatherDto {
  @IsLngLatPolyline()
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
