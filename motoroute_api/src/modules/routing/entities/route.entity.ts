import { RoutePreferenceDto, WaypointDto } from '../dto/create-route.dto';

export interface RouteSegment {
  instruction: string;
  distanceMeters: number;
  durationSeconds: number;
}

/**
 * Domain representation of a computed route - deliberately decoupled
 * from GraphHopperRouteResult (see graphhopper.client.ts) so the rest
 * of the app (and, mirrored, the Flutter client's Route entity from
 * Phase 1/2 Teil E) never depends on GraphHopper's response shape.
 */
export class Route {
  id: string;
  waypoints: WaypointDto[];
  preference: RoutePreferenceDto;
  geometry: [number, number][];
  distanceMeters: number;
  durationSeconds: number;
  segments: RouteSegment[];
  createdAt: Date;
}
