import { Body, Controller, Post } from '@nestjs/common';
import { CreateRouteDto } from './dto/create-route.dto';
import { Route } from './entities/route.entity';
import { RoutingService } from './routing.service';

/**
 * Implements the routing endpoints specified in Phase 1/2 Teil F.
 * Auth guard intentionally omitted here for MVP scaffolding - anonymous
 * routing is an explicit product requirement ("Auth: ... optional für
 * anonyme Nutzung ohne Konto"), so this controller stays open while
 * user-scoped endpoints (saved routes, later) will carry a guard.
 *
 * Deviation from the Phase 1/2 API sketch: that draft used
 * POST /v1/routes/{id}/reroute with only {currentPosition, reason}.
 * Since routes aren't persisted server-side yet (no DB layer built in
 * this scaffold), reroute currently takes a full CreateRouteDto with an
 * updated start waypoint instead of a route id. Once Route persistence
 * exists (Sprint 9 in the MVP plan), this should switch to the
 * id-based form so the backend - not the client - is the source of
 * truth for "what preference was this route using".
 */
@Controller('v1/routes')
export class RoutingController {
  constructor(private readonly routingService: RoutingService) {}

  @Post()
  async create(@Body() dto: CreateRouteDto): Promise<Route> {
    return this.routingService.createRoute(dto);
  }

  @Post('reroute')
  async reroute(@Body() dto: CreateRouteDto): Promise<Route> {
    return this.routingService.reroute(dto);
  }
}
