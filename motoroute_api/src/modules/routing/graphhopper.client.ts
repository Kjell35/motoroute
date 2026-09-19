import { HttpException, HttpStatus, Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import axios, { AxiosInstance } from 'axios';
import { WaypointDto } from './dto/create-route.dto';

export interface GraphHopperRouteResult {
  distanceMeters: number;
  durationSeconds: number;
  geometry: [number, number][]; // [lng, lat] pairs, GeoJSON order
  instructions: Array<{
    text: string;
    distanceMeters: number;
    durationSeconds: number;
  }>;
}

/**
 * Thin wrapper around the internal GraphHopper server. This is the ONLY
 * place in the backend that knows GraphHopper's request/response shape -
 * everything else (RoutingService, controllers) works with our own
 * domain types. That isolation is deliberate: if we ever need to swap
 * or front GraphHopper with something else, this is the one file that
 * changes.
 */
@Injectable()
export class GraphHopperClient {
  private readonly logger = new Logger(GraphHopperClient.name);
  private readonly http: AxiosInstance;

  constructor(private readonly config: ConfigService) {
    this.http = axios.create({
      baseURL: this.config.get<string>('GRAPHHOPPER_URL'),
      timeout: 8000,
    });
  }

  async route(params: {
    profile: string;
    waypoints: WaypointDto[];
    avoidPriorityRules: Array<Record<string, string>>;
  }): Promise<GraphHopperRouteResult> {
    const { profile, waypoints, avoidPriorityRules } = params;

    const body = {
      profile,
      points: waypoints.map((w) => [w.lng, w.lat]),
      points_encoded: false,
      instructions: true,
      // Request-time custom_model override, merged on top of the
      // profile's own files by GraphHopper - see avoid-overrides.ts.
      custom_model:
        avoidPriorityRules.length > 0 ? { priority: avoidPriorityRules } : undefined,
    };

    try {
      const { data } = await this.http.post('/route', body);
      const path = data.paths?.[0];
      if (!path) {
        throw new HttpException('No route found for the given waypoints', HttpStatus.NOT_FOUND);
      }

      return {
        distanceMeters: path.distance,
        durationSeconds: path.time / 1000,
        geometry: path.points.coordinates,
        instructions: (path.instructions ?? []).map((i: any) => ({
          text: i.text,
          distanceMeters: i.distance,
          durationSeconds: i.time / 1000,
        })),
      };
    } catch (err) {
      if (err instanceof HttpException) throw err;
      this.logger.error(`GraphHopper request failed: ${err}`);
      throw new HttpException(
        'Routing engine is currently unavailable',
        HttpStatus.SERVICE_UNAVAILABLE,
      );
    }
  }
}
