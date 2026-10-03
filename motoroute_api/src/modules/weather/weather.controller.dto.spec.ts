/**
 * Regression für den Audit-Fund 03.10.2026: Die alte DTO-Validierung
 * (@IsNumber({ each: true }) + doppeltes ArrayMaxSize) lehnte das
 * App-Format [[lng, lat], ...] grundsätzlich mit 400 ab - der
 * Wetter-Radar war in Produktion für JEDES Request unbenutzbar.
 * Diese Tests fixieren das korrekte Verhalten des RouteWeatherDto.
 */
import { plainToInstance } from 'class-transformer';
import { validate } from 'class-validator';
import { RouteWeatherDto } from './weather.controller';

const POLYLINE = [
  [6.96, 50.94],
  [8.68, 50.11],
  [10.452, 46.528],
];

function dto(overrides: Partial<Record<keyof RouteWeatherDto, unknown>> = {}): RouteWeatherDto {
  return plainToInstance(RouteWeatherDto, {
    geometry: POLYLINE,
    durationSeconds: 7200,
    ...overrides,
  });
}

async function expectValid(value: unknown): Promise<void> {
  const errors = await validate(plainToInstance(RouteWeatherDto, value));
  expect(errors).toHaveLength(0);
}

async function expectInvalid(value: unknown, fragment: string): Promise<void> {
  const errors = await validate(plainToInstance(RouteWeatherDto, value));
  expect(errors.length).toBeGreaterThan(0);
  const all = errors.flatMap((e) => Object.values(e.constraints ?? {})).join(' | ');
  expect(all).toContain(fragment);
}

describe('RouteWeatherDto (Polyline-Validierung)', () => {
  it('akzeptiert das App-Format [[lng, lat], ...]', async () => {
    await expectValid({ geometry: POLYLINE, durationSeconds: 7200 });
  });

  it('akzeptiert einen einzelnen Punkt-Punkt (2 Punkte sind das Minimum)', async () => {
    await expectValid({ geometry: [[6.96, 50.94], [6.97, 50.95]], durationSeconds: 0 });
  });

  it('lehnt das früher fälschlich valide flache Format [lng, lat, ...] ab', async () => {
    await expectInvalid(
      { geometry: [6.96, 50.94, 8.68, 50.11], durationSeconds: 7200 },
      'Polyline',
    );
  });

  it('lehnt Punkte ohne genau 2 Koordinaten ab', async () => {
    await expectInvalid(
      { geometry: [[6.96], [6.97, 50.95]], durationSeconds: 7200 },
      'Polyline',
    );
    await expectInvalid(
      { geometry: [[6.96, 50.94, 0], [6.97, 50.95]], durationSeconds: 7200 },
      'Polyline',
    );
  });

  it('lehnt Koordinaten außerhalb des Kartenbereichs ab', async () => {
    await expectInvalid(
      { geometry: [[200, 50.94], [6.97, 50.95]], durationSeconds: 7200 },
      'Polyline',
    );
    await expectInvalid(
      { geometry: [[6.96, 91], [6.97, 50.95]], durationSeconds: 7200 },
      'Polyline',
    );
  });

  it('lehnt < 2 Punkte ab', async () => {
    await expectInvalid({ geometry: [[6.96, 50.94]], durationSeconds: 7200 }, 'Polyline');
    await expectInvalid({ geometry: [], durationSeconds: 7200 }, 'Polyline');
  });

  it('lehnt NaN/Infinity-Koordinaten ab', async () => {
    await expectInvalid(
      { geometry: [[Number.NaN, 50.94], [6.97, 50.95]], durationSeconds: 7200 },
      'Polyline',
    );
  });

  it('lehnt nicht-numerische Werte ab', async () => {
    await expectInvalid(
      { geometry: [['lng', 'lat'] as unknown, [6.97, 50.95]], durationSeconds: 7200 },
      'Polyline',
    );
  });

  it('verlangt durationSeconds als Zahl und klemmt den Wertebereich', async () => {
    await expectInvalid({ geometry: POLYLINE }, 'durationSeconds');
    await expectInvalid({ geometry: POLYLINE, durationSeconds: '7200' }, 'durationSeconds');
    await expectInvalid({ geometry: POLYLINE, durationSeconds: -1 }, 'durationSeconds');
    await expectInvalid(
      { geometry: POLYLINE, durationSeconds: 60 * 60 * 24 * 7 + 1 },
      'durationSeconds',
    );
  });

  it('akzeptiert die dto()-Factory mit sinnvollen Defaults', async () => {
    const errors = await validate(dto());
    expect(errors).toHaveLength(0);
  });
});
