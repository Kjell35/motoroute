import { RouteStyle, VehicleType } from './dto/create-route.dto';
import { resolveGraphHopperProfile, UnsupportedStyleForVehicleError } from './profile-mapping';

describe('resolveGraphHopperProfile', () => {
  it('maps every motorcycle style to its own profile', () => {
    expect(resolveGraphHopperProfile(RouteStyle.FAST, VehicleType.MOTORCYCLE)).toBe(
      'motorcycle_fast',
    );
    expect(resolveGraphHopperProfile(RouteStyle.CURVY, VehicleType.MOTORCYCLE)).toBe(
      'motorcycle_curvy',
    );
    expect(resolveGraphHopperProfile(RouteStyle.EXTRA_CURVY, VehicleType.MOTORCYCLE)).toBe(
      'motorcycle_extra_curvy',
    );
    expect(resolveGraphHopperProfile(RouteStyle.FAST_AND_CURVY, VehicleType.MOTORCYCLE)).toBe(
      'motorcycle_fast_curvy',
    );
    expect(resolveGraphHopperProfile(RouteStyle.UNPAVED, VehicleType.MOTORCYCLE)).toBe(
      'motorcycle_unpaved',
    );
  });

  it('supports FAST for car and bicycle', () => {
    expect(resolveGraphHopperProfile(RouteStyle.FAST, VehicleType.CAR)).toBe('car_fast');
    expect(resolveGraphHopperProfile(RouteStyle.FAST, VehicleType.BICYCLE)).toBe('bicycle_fast');
  });

  it('rejects an unsupported style/vehicle combination instead of guessing', () => {
    expect(() => resolveGraphHopperProfile(RouteStyle.CURVY, VehicleType.CAR)).toThrow(
      UnsupportedStyleForVehicleError,
    );
  });
});
