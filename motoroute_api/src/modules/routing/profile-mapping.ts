import { RouteStyle, VehicleType } from './dto/create-route.dto';

/**
 * Single source of truth mapping (style, vehicleType) -> the GraphHopper
 * profile name defined in graphhopper/config.yml. Kept as an explicit
 * table (not a string-concatenation convention) so an unsupported
 * combination fails with a clear error instead of silently requesting a
 * profile name that doesn't exist on the GraphHopper server.
 *
 * Car and bicycle currently only support FAST - the product spec
 * (Phase 1/2) scopes curvy/unpaved styles to motorcycle only for MVP.
 * Extending this is a matter of adding profiles to config.yml/
 * custom_models and a row here, not a code change elsewhere.
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
  },
  [VehicleType.BICYCLE]: {
    [RouteStyle.FAST]: 'bicycle_fast',
  },
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
