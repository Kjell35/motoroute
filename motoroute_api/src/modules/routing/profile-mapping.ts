import { RouteStyle, VehicleType } from './dto/create-route.dto';

/**
 * Single source of truth mapping (style, vehicleType) -> the GraphHopper
 * profile name defined in graphhopper/config.yml. Kept as an explicit
 * table (not a string-concatenation convention) so an unsupported
 * combination fails with a clear error instead of silently requesting a
 * profile name that doesn't exist on the GraphHopper server.
 *
 * Fahrzeugebene (stand 0.3.12):
 * - MOTORCYCLE: alle 5 Styles (schnell/kurvig/extra kurvig/schnell+kurvig/unbefestigt)
 * - CAR: schnell, kurvig, schnell+kurvig (Auto darf Styles nutzen, die
 *   Straßenschönheit belohnen; unbefestigt bleibt Motorrad-scope)
 * - BICYCLE: schnell, kurvig (Radroute kann ebenfalls kurvenreich sein)
 *
 * WICHTIG: Der Profile-Wechsel ist die eigentliche Mechanik hinter
 * "Fahrzeugauswahl beeinflusst die Berechnung" - bicycle_base.json
 * schließt Kfz-Straßen aus und belohnt CYCLEWAY, car_base.json schließt
 * Nicht-Auto-Straßen aus, motorcycle_base.json nutzt motorradzugelassene
 * Straßen. Die style_*.json-Dateien sind fahrzeugagnostisch (Kurvigkeit)
 * und werden pro Profil mit dem jeweiligen Base-Modell kombiniert.
 */
const PROFILE_TABLE: Record<VehicleType, Partial<Record<RouteStyle, string>>> = {
  [VehicleType.MOTORCYCLE]: {
    [RouteStyle.FAST]: 'motorcycle_fast',
    [RouteStyle.CURVY]: 'motorcycle_curvy',
    [RouteStyle.EXTRA_CURVY]: 'motorcycle_extra_curvy',
    [RouteStyle.FAST_AND_CURVY]: 'motorcycle_fast_curvy',
    [RouteStyle.UNPAVED]: 'motorcycle_unpaved',
  },
  [VehicleType.CAR]: {
    [RouteStyle.FAST]: 'car_fast',
    [RouteStyle.CURVY]: 'car_curvy',
    [RouteStyle.FAST_AND_CURVY]: 'car_fast_curvy',
  },
  [VehicleType.BICYCLE]: {
    [RouteStyle.FAST]: 'bicycle_fast',
    [RouteStyle.CURVY]: 'bicycle_curvy',
  },
};

/** Styles, die die Style-Auswahl pro Fahrzeug anbietet (UI-Filter). */
export const SUPPORTED_STYLES: Record<VehicleType, RouteStyle[]> = {
  [VehicleType.MOTORCYCLE]: [
    RouteStyle.FAST,
    RouteStyle.CURVY,
    RouteStyle.EXTRA_CURVY,
    RouteStyle.FAST_AND_CURVY,
    RouteStyle.UNPAVED,
  ],
  [VehicleType.CAR]: [RouteStyle.FAST, RouteStyle.CURVY, RouteStyle.FAST_AND_CURVY],
  [VehicleType.BICYCLE]: [RouteStyle.FAST, RouteStyle.CURVY],
};

export class UnsupportedStyleForVehicleError extends Error {
  constructor(style: RouteStyle, vehicleType: VehicleType) {
    super(`Route style "${style}" is not supported for vehicle type "${vehicleType}"`);
    this.name = 'UnsupportedStyleForVehicleError';
  }
}

export function resolveGraphHopperProfile(style: RouteStyle, vehicleType: VehicleType): string {
  const profile = PROFILE_TABLE[vehicleType]?.[style];
  if (!profile) {
    throw new UnsupportedStyleForVehicleError(style, vehicleType);
  }
  return profile;
}

/** Prüft, ob ein Style für ein Fahrzeug unterstützt ist (UI-Filter). */
export function isStyleSupported(style: RouteStyle, vehicleType: VehicleType): boolean {
  return SUPPORTED_STYLES[vehicleType]?.includes(style) ?? false;
}
