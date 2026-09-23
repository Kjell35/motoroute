import { RouteStyle, VehicleType } from './dto/create-route.dto';
import {
  isStyleSupported,
  resolveGraphHopperProfile,
  UnsupportedStyleForVehicleError,
} from './profile-mapping';

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

  it('maps car curvy styles to car profiles (vehicle-correct, not motorcycle)', () => {
    expect(resolveGraphHopperProfile(RouteStyle.CURVY, VehicleType.CAR)).toBe('car_curvy');
    expect(resolveGraphHopperProfile(RouteStyle.FAST_AND_CURVY, VehicleType.CAR)).toBe(
      'car_fast_curvy',
    );
    expect(resolveGraphHopperProfile(RouteStyle.CURVY, VehicleType.BICYCLE)).toBe('bicycle_curvy');
  });

  it('rejects styles outside the vehicle scope instead of guessing', () => {
    // Unbefestigt bleibt Motorrad-Scope (Auto/Rad: Profile existieren nicht).
    expect(() => resolveGraphHopperProfile(RouteStyle.UNPAVED, VehicleType.CAR)).toThrow(
      UnsupportedStyleForVehicleError,
    );
    expect(() => resolveGraphHopperProfile(RouteStyle.UNPAVED, VehicleType.BICYCLE)).toThrow(
      UnsupportedStyleForVehicleError,
    );
    expect(() => resolveGraphHopperProfile(RouteStyle.EXTRA_CURVY, VehicleType.CAR)).toThrow(
      UnsupportedStyleForVehicleError,
    );
  });

  it('isStyleSupported spiegelt die UI-Filter-Entscheidung', () => {
    expect(isStyleSupported(RouteStyle.CURVY, VehicleType.CAR)).toBe(true);
    expect(isStyleSupported(RouteStyle.UNPAVED, VehicleType.CAR)).toBe(false);
    expect(isStyleSupported(RouteStyle.EXTRA_CURVY, VehicleType.MOTORCYCLE)).toBe(true);
    expect(isStyleSupported(RouteStyle.FAST_AND_CURVY, VehicleType.BICYCLE)).toBe(false);
  });
});
