/**
 * Mapping-Layer: TomTom Traffic API v5 (incidentDetails) -> neutrales
 * TrafficIncident-Format des Backends.
 *
 * Die EINIGE Stelle, die TomTom-Feldnamen kennt - ändert TomTom die
 * Response-Struktur, ist das die eine Datei, die angepasst werden muss
 * (gleiche Isolationsphilosophie wie GraphHopperClient).
 *
 * Referenz: developer.tomtom.com/traffic-api - v5 "incidentDetails",
 * fields=incidents{type,geometry{type,coordinates},properties{...}}.
 * iconCategory (int): 0 Unknown, 1 Accident, 2 Fog, 3 DangerousConditions,
 * 4 Rain, 5 Ice, 6 Jam, 7 LaneClosed, 8 RoadClosed, 9 RoadWorks,
 * 10 Wind, 11 Flooding, 14 BrokenDownVehicle.
 * magnitudeOfDelay: 0 Unknown, 1 Minor, 2 Moderate, 3 Major.
 */
export type IncidentCategory =
  | 'ACCIDENT'
  | 'JAM'
  | 'LANE_CLOSED'
  | 'ROAD_CLOSED'
  | 'ROAD_WORKS'
  | 'BROKEN_DOWN_VEHICLE'
  | 'WEATHER'
  | 'OTHER';

export type IncidentSeverity = 'LOW' | 'MEDIUM' | 'HIGH' | 'UNKNOWN';

export interface TrafficIncident {
  id: string;
  category: IncidentCategory;
  severity: IncidentSeverity;
  /** Beschreibung (deutsch, vom Anbieter geliefert). */
  description?: string;
  from?: string;
  to?: string;
  startTime?: string;
  endTime?: string;
  /** [lng, lat]-Paare (GeoJSON-Reihenfolge), Linie ODER Einzelpunkt. */
  geometry: [number, number][];
}

const ICON_CATEGORY_MAP: Record<number, IncidentCategory> = {
  1: 'ACCIDENT',
  6: 'JAM',
  7: 'LANE_CLOSED',
  8: 'ROAD_CLOSED',
  9: 'ROAD_WORKS',
  14: 'BROKEN_DOWN_VEHICLE',
};

function mapIconCategory(iconCategory: number | undefined): IncidentCategory {
  if (iconCategory == null) return 'OTHER';
  if (ICON_CATEGORY_MAP[iconCategory]) return ICON_CATEGORY_MAP[iconCategory];
  // 2,3,4,5,10,11 = Wetter/Unwetterspezifisch
  if ([2, 3, 4, 5, 10, 11].includes(iconCategory)) return 'WEATHER';
  return 'OTHER';
}

function mapMagnitude(magnitude: number | undefined): IncidentSeverity {
  switch (magnitude) {
    case 1:
      return 'LOW';
    case 2:
      return 'MEDIUM';
    case 3:
      return 'HIGH';
    default:
      return 'UNKNOWN';
  }
}

/**
 * Normalisiert die Geometrie: v5 liefert "Line" ([[lng,lat],...]) oder
 * "Point" ([lng,lat] - FLACH!). Der Point-Fall ist der praktisch
 * wichtigste für Blitzer; ein Mapper, der ihn verwirft, wäre für die
 * App wertlos. Wir flattenen alles auf [lng,lat]-Paare; defekte
 * Elemente (leere Koordinaten) werden verworfen statt halbgarp
 * weitergereicht.
 */
function mapGeometry(geometry: any): [number, number][] {
  if (!geometry) return [];
  const coords = geometry.coordinates;
  if (!Array.isArray(coords)) return [];

  // Point: [lng, lat] - flaches Zahlen-Array.
  if (coords.length >= 2 && Number.isFinite(coords[0]) && Number.isFinite(coords[1])) {
    return [[Number(coords[0]), Number(coords[1])]];
  }

  const flat: [number, number][] = [];
  for (const c of coords) {
    if (Array.isArray(c) && c.length >= 2 && Number.isFinite(c[0]) && Number.isFinite(c[1]) && !Array.isArray(c[0])) {
      // Line: [[lng,lat], [lng,lat], ...]
      flat.push([Number(c[0]), Number(c[1])]);
    } else if (Array.isArray(c)) {
      // MultiLineString-Fall: [[ [lng,lat], ... ], ...]
      for (const inner of c) {
        if (Array.isArray(inner) && inner.length >= 2 && Number.isFinite(inner[0]) && Number.isFinite(inner[1])) {
          flat.push([Number(inner[0]), Number(inner[1])]);
        }
      }
    }
  }
  return flat;
}

export function mapTomTomIncidents(data: any): TrafficIncident[] {
  const incidents = data?.incidents;
  if (!Array.isArray(incidents)) return [];

  const mapped: TrafficIncident[] = [];
  for (const inc of incidents) {
    const props = inc.properties ?? {};
    const geometry = mapGeometry(inc.geometry);
    if (geometry.length === 0) continue;

    mapped.push({
      id: String(props.id ?? `tt-${mapped.length}`),
      category: mapIconCategory(props.iconCategory),
      severity: mapMagnitude(props.magnitudeOfDelay),
      description: props.events?.find((e: any) => e.description)?.description,
      from: props.from || undefined,
      to: props.to || undefined,
      startTime: props.startTime || undefined,
      endTime: props.endTime || undefined,
      geometry,
    });
  }
  return mapped;
}

/**
 * Baut die fields-Projektion für v5 - bewusst explizit statt "alles":
 * weniger Payload, und wir merken sofort, wenn ein erwartetes Feld
 * verschwindet.
 */
export function tomTomFieldsProjection(): string {
  return (
    '{incidents{type,geometry{type,coordinates},properties{id,iconCategory,magnitudeOfDelay,events{description,code},startTime,endTime,from,to}}}'
  );
}

/** Kategorien 0-14 komplett: lieber mehr melden als still filtern. */
export function tomTomCategoryFilter(): string {
  return '0,1,2,3,4,5,6,7,8,9,10,11,14';
}
