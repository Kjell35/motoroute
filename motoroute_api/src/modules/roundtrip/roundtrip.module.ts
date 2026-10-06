import { Body, Controller, HttpException, HttpStatus, Injectable, Module, Post } from '@nestjs/common';
import { Type } from 'class-transformer';
import {
  IsEnum,
  IsLatitude,
  IsLongitude,
  IsNumber,
  IsOptional,
  Max,
  Min,
} from 'class-validator';
import { randomUUID } from 'crypto';
import { RoutingModule } from '../routing/routing.module';
import { GraphHopperClient } from '../routing/graphhopper.client';
import { RouteStyle, VehicleType } from '../routing/dto/create-route.dto';
import { Route } from '../routing/entities/route.entity';
import {
  isStyleSupported,
  resolveGraphHopperProfile,
} from '../routing/profile-mapping';

/**
 * Rundtour-Generator (Feature aus der Konkurrenz-Analyse "Rundtour planen"):
 * Der Nutzer gibt Start (meist aktueller Standort), Ziel-Laenge und
 * Routingprofil an - der Server erzeugt eine geschlossene Schleife und
 * liefert dieselbe Route-Entity wie POST /v1/routes, sodass App-seitig
 * Routenuebersicht und Navigation unveraendert funktionieren.
 *
 * Algorithmus (bewusst pragmatisch, keine Optimierung ueber TSP):
 * 1. Drei Zwischen-Wegpunkte auf einem Ring um den Start generieren
 *    (Ring-Radius abgeleitet aus der Ziel-Laenge, Richtung aus dem
 *    "Tour in Richtung"-Wunsch bzw. zufaellig).
 * 2. Mehrere Kandidaten (leicht variierte Richtungen) parallel ueber den
 *    normalen Routing-Stack (GraphHopper/OSRM-Fallback) rechnen.
 * 3. Kandidat mit der geringsten Abweichung zur Ziel-Laenge gewinnen.
 * 4. Bei Abweichung > 12 %: Radius skalieren und EINmal nachrechnen.
 */
export enum RoundTripDirection {
  RANDOM = 'RANDOM',
  NORTH = 'NORTH',
  EAST = 'EAST',
  SOUTH = 'SOUTH',
  WEST = 'WEST',
}

export class CreateRoundTripDto {
  @IsLatitude()
  startLat: number;

  @IsLongitude()
  startLng: number;

  @IsNumber()
  @Type(() => Number)
  @Min(5)
  @Max(1000)
  targetDistanceKm: number;

  @IsEnum(RouteStyle)
  style: RouteStyle;

  @IsOptional()
  @IsEnum(VehicleType)
  vehicleType?: VehicleType;

  @IsOptional()
  @IsEnum(RoundTripDirection)
  direction?: RoundTripDirection;
}

/** Polygoneck-Laenge bei 3 Punkten auf dem Ring: 3 * R * sqrt(3). */
const POLYGON_PERIMETER_FACTOR = 3 * Math.sqrt(3);
/** Strassendetour-Faktor: Straßen laufen nie als Luftlinie. */
const ROAD_DETOUR_FACTOR = 1.2;
/** Nachberechnen nur wenn die Abweichung zur Ziel-Laenge groesser ist. */
const REFINEMENT_THRESHOLD = 0.12;

/** Grosskreis-Distanz in Metern (kleine Hilfsfunktion, osmotisch gleich
 * zur Geometrie-Bewertung im GraphHopperClient). */
export function haversineMeters(lat1: number, lng1: number, lat2: number, lng2: number): number {
  const R = 6_371_000;
  const toRad = (d: number) => (d * Math.PI) / 180;
  const dLat = toRad(lat2 - lat1);
  const dLng = toRad(lng2 - lng1);
  const a =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLng / 2) ** 2;
  return 2 * R * Math.asin(Math.sqrt(a));
}

/**
 * Punkt auf einem Ring um (lat, lng) mit Radius radiusKm und Peilung
 * bearingDeg (0 = Nord, 90 = Ost). Standard "destination point"-Formel.
 */
export function waypointOnRing(
  lat: number,
  lng: number,
  radiusKm: number,
  bearingDeg: number,
): { lat: number; lng: number } {
  const toRad = (d: number) => (d * Math.PI) / 180;
  const toDeg = (r: number) => (r * 180) / Math.PI;
  const delta = radiusKm / 6_371;
  const bearing = toRad(bearingDeg);
  const lat1 = toRad(lat);
  const lng1 = toRad(lng);

  const lat2 = Math.asin(
    Math.sin(lat1) * Math.cos(delta) + Math.cos(lat1) * Math.sin(delta) * Math.cos(bearing),
  );
  const lng2 =
    lng1 +
    Math.atan2(
      Math.sin(bearing) * Math.sin(delta) * Math.cos(lat1),
      Math.cos(delta) - Math.sin(lat1) * Math.sin(lat2),
    );
  return { lat: toDeg(lat2), lng: ((toDeg(lng2) + 540) % 360) - 180 };
}

/** Winkel-Set (Peilungen in Grad) fuer die 3 Zwischen-Wegpunkte. */
export function loopAngles(direction: RoundTripDirection): number[] {
  const base =
    direction === RoundTripDirection.NORTH
      ? 0
      : direction === RoundTripDirection.EAST
        ? 90
        : direction === RoundTripDirection.SOUTH
          ? 180
          : direction === RoundTripDirection.WEST
            ? 270
            : Math.random() * 360;
  return [base, base + 120, base + 240].map((a) => ((a % 360) + 360) % 360);
}

@Injectable()
export class RoundTripService {
  constructor(private readonly graphHopper: GraphHopperClient) {}

  async generate(dto: CreateRoundTripDto): Promise<Route> {
    const vehicleType = dto.vehicleType ?? VehicleType.MOTORCYCLE;
    const style = dto.style;

    if (!isStyleSupported(style, vehicleType)) {
      throw new HttpException(
        {
          error: 'STYLE_NOT_SUPPORTED',
          message: `Fahrstil "${style}" ist für Fahrzeug "${vehicleType}" nicht verfügbar`,
        },
        HttpStatus.BAD_REQUEST,
      );
    }
    const profile = resolveGraphHopperProfile(style, vehicleType);

    const direction = dto.direction ?? RoundTripDirection.RANDOM;
    const baseRadiusKm =
      dto.targetDistanceKm / (POLYGON_PERIMETER_FACTOR * ROAD_DETOUR_FACTOR);

    // Kandidaten: leicht variierte Richtungen, damit die Wahl aus mehreren
    // Loops trifft statt den ersten den der Router zurueckgibt. RANDOM
    // bekommt 3 echte Zufalls-Basen, feste Richtungen +-25 Grad.
    const bases =
      direction === RoundTripDirection.RANDOM
        ? [Math.random() * 360, Math.random() * 360, Math.random() * 360]
        : (() => {
            const b = loopAngles(direction)[0];
            return [b - 25 + 360, b, b + 25] as number[];
          })();

    const candidates = bases.map((base) =>
      [base, base + 120, base + 240].map((a) => ((a % 360) + 360) % 360),
    );

    const results = await Promise.allSettled(
      candidates.map((angles) =>
        this.routeLoop(dto, angles, baseRadiusKm, profile, vehicleType, style),
      ),
    );

    let best: Route | null = null;
    for (const r of results) {
      if (r.status === 'fulfilled') {
        best = this.pickCloser(best, r.value, dto.targetDistanceKm);
      }
    }
    if (!best) {
      throw new HttpException(
        'Rundtour konnte nicht berechnet werden - Routing-Engine nicht erreichbar?',
        HttpStatus.SERVICE_UNAVAILABLE,
      );
    }

    // Ein Refinement-Schritt: Radius proportional zur Abweichung skalieren
    // und erneut rechnen. Gewinnt nur, wenn das Ergebnis naeher dran ist.
    const deviation =
      Math.abs(best.distanceMeters - dto.targetDistanceKm * 1000) /
      (dto.targetDistanceKm * 1000);
    if (deviation > REFINEMENT_THRESHOLD) {
      // Radius proportional zur Ziel-Abweichung skalieren (Strassen-Detour
      // ist nicht exakt linear) und EINmal nachrechnen.
      const scaledRadiusKm =
        (baseRadiusKm * dto.targetDistanceKm * 1000) / Math.max(best.distanceMeters, 1);
      try {
        const angles = this.anglesForRoute(best, dto);
        const refined = await this.routeLoop(
          dto,
          angles,
          scaledRadiusKm,
          profile,
          vehicleType,
          style,
        );
        best = this.pickCloser(best, refined, dto.targetDistanceKm);
      } catch {
        // Refinement ist optional - das erste Ergebnis bleibt.
      }
    }

    return best;
  }

  /** Berechnet eine geschlossene Schleife ueber die Zwischen-Wegpunkte. */
  private async routeLoop(
    dto: CreateRoundTripDto,
    angles: number[],
    radiusKm: number,
    profile: string,
    vehicleType: VehicleType,
    style: RouteStyle,
  ): Promise<Route> {
    const start = { lat: dto.startLat, lng: dto.startLng };
    const loopPoints = angles.map((a) => waypointOnRing(dto.startLat, dto.startLng, radiusKm, a));
    const waypoints = [
      { ...start, label: 'Start' },
      ...loopPoints.map((p, i) => ({ ...p, label: `Rundtour ${i + 1}` })),
      { ...start, label: 'Start' },
    ];

    const result = await this.graphHopper.route({
      profile,
      waypoints,
      avoidPriorityRules: [],
    });

    const route = new Route();
    route.id = randomUUID();
    route.waypoints = waypoints;
    route.preference = { style, vehicleType, avoid: [] };
    route.geometry = result.geometry;
    route.distanceMeters = result.distanceMeters;
    route.durationSeconds = result.durationSeconds;
    route.segments = result.instructions.map((i) => ({
      instruction: i.text,
      distanceMeters: i.distanceMeters,
      durationSeconds: i.durationSeconds,
    }));
    route.createdAt = new Date();
    return route;
  }

  private pickCloser(current: Route | null, candidate: Route, targetKm: number): Route {
    if (!current) return candidate;
    const target = targetKm * 1000;
    const dCurrent = Math.abs(current.distanceMeters - target);
    const dCandidate = Math.abs(candidate.distanceMeters - target);
    return dCandidate < dCurrent ? candidate : current;
  }

  /** Winkel-Set rekonstruieren, mit dem die gewonnene Route gebaut wurde. */
  private anglesForRoute(route: Route, dto: CreateRoundTripDto): number[] {
    const loop = route.waypoints.slice(1, 4);
    if (loop.length < 3) {
      return [90, 210, 330]; // konservativer Fallback
    }
    const base =
      (Math.atan2(loop[0].lng - dto.startLng, loop[0].lat - dto.startLat) * 180) / Math.PI;
    return [base, base + 120, base + 240].map((a) => ((a % 360) + 360) % 360);
  }
}

@Controller('v1/roundtrips')
export class RoundTripController {
  constructor(private readonly roundTripService: RoundTripService) {}

  @Post()
  async create(@Body() dto: CreateRoundTripDto) {
    return this.roundTripService.generate(dto);
  }
}

@Module({
  imports: [RoutingModule],
  controllers: [RoundTripController],
  providers: [RoundTripService],
})
export class RoundTripModule {}
