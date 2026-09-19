import { Injectable } from '@nestjs/common';
import { randomUUID } from 'crypto';
import { CreateRouteDto } from './dto/create-route.dto';
import { Route } from './entities/route.entity';
import { GraphHopperClient } from './graphhopper.client';
import { resolveGraphHopperProfile } from './profile-mapping';
import { buildAvoidPriorityRules } from './avoid-overrides';

@Injectable()
export class RoutingService {
  constructor(private readonly graphHopper: GraphHopperClient) {}

  async createRoute(dto: CreateRouteDto): Promise<Route> {
    const profile = resolveGraphHopperProfile(dto.preference.style, dto.preference.vehicleType);
    const avoidPriorityRules = buildAvoidPriorityRules(dto.preference.avoid);

    const result = await this.graphHopper.route({
      profile,
      waypoints: dto.waypoints,
      avoidPriorityRules,
    });

    const route = new Route();
    route.id = randomUUID();
    route.waypoints = dto.waypoints;
    route.preference = dto.preference;
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

  /**
   * Rerouting deliberately reuses createRoute() with the ORIGINAL
   * preference plus a new start waypoint - this is the concrete
   * mechanism behind Phase 1/2 Abschnitt 5's requirement that a
   * recalculated route must still respect the user's chosen style and
   * avoid-options, not silently fall back to "fastest". There is no
   * separate reroute code path in GraphHopper terms; "reroute" is a
   * product/API concept, not a routing-engine concept.
   */
  async reroute(dto: CreateRouteDto): Promise<Route> {
    return this.createRoute(dto);
  }
}
