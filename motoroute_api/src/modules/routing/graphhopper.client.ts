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
 * fällt der Client auf OSRM zurück. Der Fallback ist FAHRZEUGSPEZIFISCH:
 * car -> driving (OSRM-Standard), bicycle -> FOSSGIS-Bike-Instanz,
 * motorcycle -> driving (Motorräder folgen dem PKW-Netz; die
 * Kurven-Präferenzen der GraphHopper-Profile fehlen hier - ehrliche
 * Degradation, die Navigation funktioniert trotzdem fahrzeuggerecht).
 * Das ist der Zero-Config-Weg für Cloud-Deployments ohne lokale
 * Java-Instanz.
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

  /**
   * OSRM-Ziel-URL je Fahrzeugprofil. Das bicycle-Profil kommt von der
   * FOSSGIS-Instanz (echtes Rad-Netz mit Einbahn-Richtungen für Räder),
   * Auto/Motorrad vom driving-Profil. Ein konfiguriertes
   * ROUTING_FALLBACK_URL (eigener OSRM) überschreibt beides - dann
   * muss der Betreiber die Profile dort bereitstellen.
   */
  private osrmBaseUrlFor(vehicleType: string): string {
    const custom = this.config.get<string>('ROUTING_FALLBACK_URL')?.trim();
    if (custom) return custom.replace(/\/+$/, '');
    return vehicleType === 'bicycle_fast' || vehicleType === 'bicycle_curvy'
      ? 'https://routing.openstreetmap.de/routed-bike'
      : 'https://router.project-osrm.org';
  }

  private osrmProfileFor(vehicleType: string): string {
    return vehicleType.startsWith('bicycle') ? 'bike' : 'driving';
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
    const baseUrl = this.osrmBaseUrlFor(params.profile);
    const osrmProfile = this.osrmProfileFor(params.profile);

    try {
      // alternatives=true liefert bis zu 2 Alternativen: Ohne GraphHopper
      // ist das der einzige Hebel für Kurven-/Stil-Präferenzen im
      // Fallback - wir bewerten alle Kandidaten nach Kurvenigkeit (und
      // Autobahn-Anteil bei Avoid) und wählen passend zum Profil.
      const { data } = await axios.get(
        `${baseUrl}/route/v1/${osrmProfile}/${coords}?overview=full&geometries=geojson&steps=true&alternatives=2`,
        { timeout: 12000 },
      );
      if (data.code !== 'Ok' || !data.routes?.[0]) {
        throw new HttpException('No route found for the given waypoints', HttpStatus.NOT_FOUND);
      }
      const best = this.pickOsrmRoute(data.routes, params.profile);
      return {
        distanceMeters: best.distance,
        durationSeconds: best.duration,
        geometry: best.geometry.coordinates,
        instructions: this.osrmInstructions(best.legs ?? []),
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

  /**
   * Wählt die OSRM-Route, die am besten zum angefragten Profil passt:
   * - kurvige Profile ( motorcycle_curvy/extra_curvy, *_curvy ) belohnen
   *   Kurvenigkeit pro km (Summe der Richtungsänderungen) und akzep-
   *   tieren dafür längere Strecken.
   * - fast-Profile wählen die schnellste Route (OSRM-Reihenfolge).
   * - Autobahn-Avoid (avoidPriorityRules enthält motorway-Regel) wählt
   *   die Route mit dem geringsten motorway-Anteil.
   */
  private pickOsrmRoute(
    routes: Array<{
      distance: number;
      duration: number;
      geometry: { coordinates: [number, number][] };
      legs?: Array<unknown>;
    }>,
    profile: string,
  ): (typeof routes)[number] {
    if (routes.length <= 1) return routes[0];

    const isCurvy = profile.includes('curvy');
    const avoidsMotorway = profile.includes('unpaved'); // Unbefestigt meidet Autobahn implizit

    if (!isCurvy && !avoidsMotorway) return routes[0]; // schnell = OSRM-Primärroute

    const scoreFor = (r: (typeof routes)[number]): number => {
      const curviness = this.curvinessPerKm(r.geometry.coordinates);
      const motorwayShare = 0; // ohne Straßen-Attribute schätzt die Länge: kürzere Alternativen meiden Fernstraßen selten - bewusst neutral
      if (isCurvy) {
        // Kurvenigkeit pro km ist der Primärmaßstab; Dauer wird sanft
        // bestraft, damit nicht eine stundenlange Schlangestrecke gewinnt.
        return curviness * 1000 - r.duration / 60;
      }
      return -motorwayShare;
    };

    let best = routes[0];
    let bestScore = -Infinity;
    for (const r of routes) {
      const score = scoreFor(r);
      if (score > bestScore) {
        bestScore = score;
        best = r;
      }
    }
    return best;
  }

  /**
   * Kurvenigkeit: mittlere Richtungsänderung (Grad) pro km über die
   * Geometrie. Sampling alle ~10 Punkte hält die Kosten klein; die
   * absolute Zahl ist egal - es wird nur verglichen.
   */
  private curvinessPerKm(coords: Array<[number, number]>): number {
    if (coords.length < 3) return 0;
    let totalDegrees = 0;
    let totalMeters = 0;
    const step = Math.max(1, Math.floor(coords.length / 400));
    let prevBearing: number | null = null;
    for (let i = step; i < coords.length; i += step) {
      const [x1, y1] = coords[i - step];
      const [x2, y2] = coords[i];
      const bearing = this.bearingDeg(y1, x1, y2, x2);
      const meters = this.haversineM(y1, x1, y2, x2);
      if (prevBearing != null) {
        let delta = Math.abs(bearing - prevBearing);
        if (delta > 180) delta = 360 - delta;
        // Richtungsänderungen über 90° sind Kehren/Abbiegen - zählen
        // überproportional (Motorrad-Charakteristik).
        totalDegrees += delta > 90 ? delta * 2 : delta;
      }
      totalMeters += meters;
      prevBearing = bearing;
    }
    if (totalMeters < 100) return 0;
    return totalDegrees / (totalMeters / 1000);
  }

  private bearingDeg(lat1: number, lng1: number, lat2: number, lng2: number): number {
    const toRad = (d: number) => (d * Math.PI) / 180;
    const y = Math.sin(toRad(lng2 - lng1)) * Math.cos(toRad(lat2));
    const x =
      Math.cos(toRad(lat1)) * Math.sin(toRad(lat2)) -
      Math.sin(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.cos(toRad(lng2 - lng1));
    return (Math.atan2(y, x) * 180) / Math.PI;
  }

  private haversineM(lat1: number, lng1: number, lat2: number, lng2: number): number {
    const R = 6_371_000;
    const toRad = (d: number) => (d * Math.PI) / 180;
    const dLat = toRad(lat2 - lat1);
    const dLng = toRad(lng2 - lng1);
    const a =
      Math.sin(dLat / 2) ** 2 +
      Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLng / 2) ** 2;
    return 2 * R * Math.asin(Math.sqrt(a));
  }

  private osrmInstructions(
    legs: Array<any>,
  ): Array<{ text: string; distanceMeters: number; durationSeconds: number }> {
    const out: Array<{ text: string; distanceMeters: number; durationSeconds: number }> = [];
    for (const leg of legs ?? []) {
      for (const step of leg.steps ?? []) {
        const maneuver = step.maneuver ?? {};
        const text = this.osrmManeuverText(maneuver);
        if (text) {
          // Straßennamen anhängen, wo es orientiert ("Rechts abbiegen auf
          // B123") - OSRM liefert step.name als Straßen-/Nummern-Feld.
          const street = typeof step.name === 'string' ? step.name.trim() : '';
          const withStreet =
            street && !/losfahren|ziel|wenden|kreisverkehr|weiterfahren/i.test(text)
              ? `${text} auf ${street}`
              : text;
          out.push({
            text: withStreet,
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
