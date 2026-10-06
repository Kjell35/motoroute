import {
  RoundTripService,
  CreateRoundTripDto,
  haversineMeters,
  waypointOnRing,
  loopAngles,
  RoundTripDirection,
} from './roundtrip.module';

/**
 * Tests für den Rundtour-Generator: Geometrie-Helfer, Kandidatenwahl nach
 * Längen-Nähe, Style-Verifikation und Refinement-Verhalten.
 */

function dto(overrides: Partial<CreateRoundTripDto> = {}): CreateRoundTripDto {
  return {
    startLat: 47.99,
    startLng: 7.84,
    targetDistanceKm: 120,
    style: 'CURVY' as CreateRoundTripDto['style'],
    ...overrides,
  };
}

/** GraphHopper-Client-Mock: route() liefert Distanzen der Reihe nach
 * zurück (ein Eintrag pro Kandidaten-Aufruf). */
function mockGraphHopper(distances: number[]) {
  let call = 0;
  return {
    route: jest.fn(async (params: { waypoints: Array<{ lat: number; lng: number }> }) => {
      const d = distances[Math.min(call++, distances.length - 1)];
      return {
        distanceMeters: d,
        durationSeconds: d / 15,
        geometry: params.waypoints.map((w) => [w.lng, w.lat]) as [number, number][],
        instructions: [{ text: 'Losfahren', distanceMeters: 0, durationSeconds: 0 }],
      };
    }),
  };
}

function serviceWith(gh: { route: jest.Mock }): RoundTripService {
  return new RoundTripService(gh as never);
}

describe('Rundtour-Geometrie', () => {
  it('waypointOnRing liefert einen Punkt auf dem gewünschten Ring', () => {
    const p = waypointOnRing(47.99, 7.84, 20, 45);
    const d = haversineMeters(47.99, 7.84, p.lat, p.lng);
    expect(d).toBeGreaterThan(19_500);
    expect(d).toBeLessThan(20_500);
  });

  it('loopAngles liefert drei 120°-auseinanderliegende Peilungen', () => {
    const angles = loopAngles(RoundTripDirection.NORTH);
    expect(angles).toHaveLength(3);
    expect(angles[0]).toBe(0);
    expect(angles[1]).toBe(120);
    expect(angles[2]).toBe(240);
  });

  it('RANDOM erzeugt zufällige (aber gültige) Peilungen', () => {
    const angles = loopAngles(RoundTripDirection.RANDOM);
    expect(angles).toHaveLength(3);
    for (const a of angles) {
      expect(a).toBeGreaterThanOrEqual(0);
      expect(a).toBeLessThan(360);
    }
  });
});

describe('RoundTripService.generate', () => {
  it('wählt unter den Kandidaten die Route mit der geringsten Längen-Abweichung', async () => {
    const gh = mockGraphHopper([100_000, 60_000, 125_000]);
    const svc = serviceWith(gh);
    const route = await svc.generate(dto({ targetDistanceKm: 120 }));

    // 125 km liegt näher an 120 km als 100 km und 60 km.
    expect(route.distanceMeters).toBe(125_000);
    expect(gh.route).toHaveBeenCalledTimes(3);
  });

  it('berechnet bei Abweichung > 12 % über den skalierten Radius nach', async () => {
    // Erste Runde: viel zu kurz (40 km statt 120 km) -> Refinement mit
    // groesserem Radius; der zweite Durchlauf trifft 118 km und gewinnt.
    const gh = mockGraphHopper([40_000, 118_000]);
    const svc = serviceWith(gh);
    const route = await svc.generate(dto({ targetDistanceKm: 120 }));

    expect(gh.route.mock.calls.length).toBeGreaterThanOrEqual(2);
    expect(route.distanceMeters).toBe(118_000);
  });

  it('schließt die Schleife: Start erscheint als erster UND letzter Wegpunkt', async () => {
    const gh = mockGraphHopper([120_000]);
    const svc = serviceWith(gh);
    const route = await svc.generate(dto());

    const first = route.waypoints[0];
    const last = route.waypoints[route.waypoints.length - 1];
    expect(first.lat).toBeCloseTo(last.lat, 8);
    expect(first.lng).toBeCloseTo(last.lng, 8);
    expect(route.waypoints.length).toBe(5); // Start + 3 Ring-Punkte + Start
  });

  it('lehnt nicht unterstützte Style/Fahrzeug-Kombis ab (wie /v1/routes)', async () => {
    const gh = mockGraphHopper([]);
    const svc = serviceWith(gh);
    await expect(
      svc.generate(dto({ style: 'UNPAVED' as CreateRoundTripDto['style'], vehicleType: 'BICYCLE' as never })),
    ).rejects.toMatchObject({ status: 400 });
    expect(gh.route).not.toHaveBeenCalled();
  });

  it('wirft 503, wenn alle Kandidaten fehlschlagen', async () => {
    const gh = { route: jest.fn(async () => { throw new Error('engine down'); }) };
    const svc = serviceWith(gh);
    await expect(svc.generate(dto())).rejects.toMatchObject({ status: 503 });
  });
});
