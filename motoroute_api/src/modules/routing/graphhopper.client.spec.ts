import { HttpStatus } from '@nestjs/common';
import axios from 'axios';
import { GraphHopperClient } from './graphhopper.client';

/**
 * Tests für den Routing-Client inkl. OSRM-Fallback:
 *  1. GraphHopper konfiguriert -> GH-Antwort wird auf unsere Typen gemappt
 *  2. GraphHopper NICHT konfiguriert -> OSRM-Fallback direkt (Zero-Config-
 *     Deployment ohne lokale Java-Instanz)
 *  3. GraphHopper down (5xx) -> OSRM-Fallback greift
 *  4. 404 vom GH (Wegpunkt-Problem) -> KEIN Fallback, 404 durchgereicht
 */
jest.mock('axios');

const waypoints = [
  { lat: 47.99, lng: 7.84 },
  { lat: 47.49, lng: 11.09 },
] as any;

function configWith(values: Record<string, string | undefined>) {
  return { get: (key: string) => values[key] } as any;
}

describe('GraphHopperClient', () => {
  let gh: { post: jest.Mock };
  let osrm: { get: jest.Mock };
  const createMock = (axios.create as unknown) as jest.Mock;

  beforeEach(() => {
    gh = { post: jest.fn() };
    osrm = { get: jest.fn() };
    createMock.mockReset();
    // Reihenfolge im Konstruktor: erst GraphHopper-, dann OSRM-Instanz.
    createMock.mockImplementationOnce(() => gh).mockImplementationOnce(() => osrm);
  });

  it('mappt eine GraphHopper-Antwort auf die eigenen Typen', async () => {
    const client = new GraphHopperClient(configWith({ GRAPHHOPPER_URL: 'http://gh:8989' }));

    gh.post.mockResolvedValue({
      data: {
        paths: [
          {
            distance: 1234,
            time: 60000,
            points: { coordinates: [[7.84, 47.99]] },
            instructions: [{ text: 'links abbiegen', distance: 100, time: 10000 }],
          },
        ],
      },
    });

    const r = await client.route({ profile: 'car', waypoints, avoidPriorityRules: [] });

    expect(gh.post).toHaveBeenCalledWith(
      '/route',
      expect.objectContaining({ profile: 'car' }),
    );
    expect(r.distanceMeters).toBe(1234);
    expect(r.durationSeconds).toBe(60);
    expect(r.instructions[0].text).toBe('links abbiegen');
  });

  it('routet ohne GRAPHHOPPER_URL direkt über den OSRM-Fallback', async () => {
    const client = new GraphHopperClient(configWith({}));

    osrm.get.mockResolvedValue({
      data: {
        code: 'Ok',
        routes: [
          {
            distance: 240000,
            duration: 9000,
            geometry: { coordinates: [[7.84, 47.99], [11.09, 47.49]] },
            legs: [
              {
                steps: [
                  { maneuver: { type: 'depart' }, distance: 0, duration: 0 },
                  { maneuver: { type: 'turn', modifier: 'left' }, distance: 500, duration: 60 },
                  { maneuver: { type: 'arrive' }, distance: 0, duration: 0 },
                ],
              },
            ],
          },
        ],
      },
    });

    const r = await client.route({ profile: 'car', waypoints, avoidPriorityRules: [] });

    expect(gh.post).not.toHaveBeenCalled();
    expect(osrm.get).toHaveBeenCalledWith(
      expect.stringContaining('/route/v1/driving/7.84,47.99;11.09,47.49'),
    );
    expect(r.distanceMeters).toBe(240000);
    expect(r.instructions.map((i) => i.text)).toEqual([
      'Losfahren',
      'Links abbiegen',
      'Ziel erreicht',
    ]);
  });

  it('fällt bei GraphHopper-Ausfall (5xx) auf OSRM zurück', async () => {
    const client = new GraphHopperClient(configWith({ GRAPHHOPPER_URL: 'http://gh:8989' }));

    gh.post.mockRejectedValue({ response: { status: 500 } });
    osrm.get.mockResolvedValue({
      data: {
        code: 'Ok',
        routes: [
          { distance: 1, duration: 1, geometry: { coordinates: [] }, legs: [] },
        ],
      },
    });

    const r = await client.route({ profile: 'car', waypoints, avoidPriorityRules: [] });

    expect(osrm.get).toHaveBeenCalled();
    expect(r.distanceMeters).toBe(1);
  });

  it('reicht einen Wegpunkt-404 durch, ohne zu fallbacken', async () => {
    const client = new GraphHopperClient(configWith({ GRAPHHOPPER_URL: 'http://gh:8989' }));

    gh.post.mockResolvedValue({ data: { paths: [] } });

    await expect(
      client.route({ profile: 'car', waypoints, avoidPriorityRules: [] }),
    ).rejects.toMatchObject({ status: HttpStatus.NOT_FOUND });
    expect(osrm.get).not.toHaveBeenCalled();
  });
});
