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
 * Thin wrapper around the routing engine. Primär ist der EIGENE
 * GraphHopper (GRAPHHOPPER_URL) - er unterstützt Custom Models und
 * damit Kurven-Präferenzen (Schnell/Kurvig/...) und Vermeidungsregeln.
 *
 * OHNE konfigurierten GraphHopper - oder wenn er nicht erreichbar ist -
 * fällt der Client auf OSRM zurück (ROUTING_FALLBACK_URL, Default:
 * öffentlicher OSRM-Demo-Server). Der Fallback fährt NUR Auto-Profil:
 * Kurven-Präferenzen und Vermeidungen werden dort ignoriert (ehrliche
 * Degradation - die Navigation funktioniert trotzdem). Das ist der
 * Zero-Config-Weg für Cloud-Deployments ohne lokale Java-Instanz.
 *
 * This is the ONLY place in the backend that knows the engines'
 * request/response shapes - everything else (RoutingService,
 * controllers) works with our own domain types. That isolation is
 * deliberate: swapping engines changes exactly this file.
 */
@Injectable()
export class GraphHopperClient {
  private readonly logger = new Logger(GraphHopperClient.name);
  private readonly http: AxiosInstance; // GraphHopper (wenn konfiguriert)
  private readonly osrmHttp: AxiosInstance; // Fallback-Engine
  private readonly ghConfigured: boolean;

  constructor(private readonly config: ConfigService) {
    const ghUrl = this.config.get<string>('GRAPHHOPPER_URL')?.trim();
    this.ghConfigured = !!ghUrl;
    this.http = axios.create({ baseURL: ghUrl, timeout: 8000 });

    const osrmBase = (
      this.config.get<string>('ROUTING_FALLBACK_URL') ?? 'https://router.project-osrm.org'
    ).replace(/\/+$/, '');
    this.osrmHttp = axios.create({ baseURL: osrmBase, timeout: 12000 });

    if (!this.ghConfigured) {
      this.logger.warn(
        `GRAPHHOPPER_URL nicht gesetzt - Routing läuft über OSRM-Fallback (${osrmBase}). ` +
          'Kurven-/Vermeidungs-Präferenzen werden dort nicht angewendet.',
      );
    }
  }

  async route(params: {
    profile: string;
    waypoints: WaypointDto[];
    avoidPriorityRules: Array<Record<string, string>>;
  }): Promise<GraphHopperRouteResult> {
    if (this.ghConfigured) {
      try {
        return await this.routeGraphHopper(params);
      } catch (err) {
        // 4xx heißt: Wegpunkte/Profil-Problem - OSRM würde dasselbe
        // antworten, kein Sinn im Fallback. Alles andere (Server down,
        // Timeout, 5xx) -> Fallback versuchen.
        if (err instanceof HttpException && err.getStatus() < 500) throw err;
        this.logger.warn(
          `GraphHopper nicht erreichbar (${
            err instanceof Error ? err.message : String(err)
          }) - OSRM-Fallback`,
        );
      }
    }
    return this.routeOsrm(params);
  }

  private async routeGraphHopper(params: {
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

  // ---------------------------------------------------------------------------
  // OSRM-Fallback (GET /route/v1/driving/... - Auto-Profil)
  // ---------------------------------------------------------------------------

  private async routeOsrm(params: {
    profile: string;
    waypoints: WaypointDto[];
    avoidPriorityRules: Array<Record<string, string>>;
  }): Promise<GraphHopperRouteResult> {
    const coords = params.waypoints.map((w) => `${w.lng},${w.lat}`).join(';');

    try {
      const { data } = await this.osrmHttp.get(
        `/route/v1/driving/${coords}?overview=full&geometries=geojson&steps=true`,
      );
      if (data.code !== 'Ok' || !data.routes?.[0]) {
        throw new HttpException('No route found for the given waypoints', HttpStatus.NOT_FOUND);
      }
      const route = data.routes[0];
      return {
        distanceMeters: route.distance,
        durationSeconds: route.duration,
        geometry: route.geometry.coordinates,
        instructions: this.osrmInstructions(route.legs),
      };
    } catch (err) {
      if (err instanceof HttpException) throw err;
      this.logger.error(`OSRM fallback request failed: ${err}`);
      throw new HttpException(
        'Routing engine is currently unavailable',
        HttpStatus.SERVICE_UNAVAILABLE,
      );
    }
  }

  private osrmInstructions(
    legs: Array<any>,
  ): Array<{ text: string; distanceMeters: number; durationSeconds: number }> {
    const out: Array<{ text: string; distanceMeters: number; durationSeconds: number }> = [];
    for (const leg of legs ?? []) {
      for (const step of leg.steps ?? []) {
        const text = this.osrmManeuverText(step.maneuver ?? {});
        if (text) {
          out.push({
            text,
            distanceMeters: step.distance ?? 0,
            durationSeconds: step.duration ?? 0,
          });
        }
      }
    }
    return out.length > 0
      ? out
      : [{ text: 'Route folgen', distanceMeters: 0, durationSeconds: 0 }];
  }

  /**
   * OSRM-Maneuver -> kurze deutsche Anweisung (App-Sprache). Bewusst
   * kompakt - OSRM liefert weniger Kontext als GraphHopper.
   */
  private osrmManeuverText(maneuver: {
    type?: string;
    modifier?: string;
    exit?: number;
  }): string | null {
    const type = maneuver.type ?? '';
    const mod = maneuver.modifier ?? '';
    const dir = mod.includes('left') ? 'links' : mod.includes('right') ? 'rechts' : '';
    const grade = mod.startsWith('sharp')
      ? 'Scharf '
      : mod.startsWith('slight')
        ? 'Leicht '
        : '';

    switch (type) {
      case 'depart':
        return 'Losfahren';
      case 'arrive':
        return 'Ziel erreicht';
      case 'turn':
      case 'end of road':
        if (mod === 'uturn') return 'Wenden';
        return dir
          ? `${grade}${dir[0].toUpperCase()}${dir.slice(1)} abbiegen`
          : 'Geradeaus weiterfahren';
      case 'continue':
      case 'new name':
        return dir ? `${dir === 'links' ? 'Links' : 'Rechts'} weiterfahren` : 'Geradeaus weiterfahren';
      case 'merge':
        return 'Einfädeln';
      case 'on ramp':
        return 'Auffahrt nehmen';
      case 'off ramp':
        return 'Abfahrt nehmen';
      case 'fork':
        return dir ? `An der Gabelung ${dir} halten` : 'Geradeaus weiterfahren';
      case 'roundabout':
      case 'rotary':
      case 'roundabout turn':
        return maneuver.exit
          ? `Im Kreisverkehr, ${maneuver.exit}. Ausfahrt`
          : 'In den Kreisverkehr';
      case 'exit roundabout':
      case 'exit rotary':
        return 'Kreisverkehr verlassen';
      case 'notification':
        return null;
      default:
        return 'Weiterfahren';
    }
  }
}
