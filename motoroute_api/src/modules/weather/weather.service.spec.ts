import { ConfigService } from '@nestjs/config';
import { PoiCategory } from '../poi/dto/query-pois.dto';
import { WeatherService, sampleRoute, wmoCodeToOwm } from './weather.service';

describe('wmoCodeToOwm', () => {
  it('mappt WMO-Codes konservativ auf OWM-Gruppen', () => {
    expect(wmoCodeToOwm(0)).toBe(800); // klar
    expect(wmoCodeToOwm(3)).toBe(801); // bedeckt
    expect(wmoCodeToOwm(45)).toBe(701); // Nebel
    expect(wmoCodeToOwm(55)).toBe(300); // Niesel
    expect(wmoCodeToOwm(61)).toBe(500); // Regen
    expect(wmoCodeToOwm(65)).toBe(500); // starker Regen
    expect(wmoCodeToOwm(71)).toBe(600); // Schnee
    expect(wmoCodeToOwm(82)).toBe(522); // heftige Schauer
    expect(wmoCodeToOwm(95)).toBe(201); // Gewitter
    expect(wmoCodeToOwm(99)).toBe(201); // Gewitter mit Hagel
    expect(wmoCodeToOwm(null)).toBe(800); // defensiv
  });
});

describe('sampleRoute', () => {
  it('verteilt Samples gleichmäßig inkl. ETA-Anteilen', () => {
    // 2-Grad-Ost-West-Linie (~222 km), 2 h Fahrzeit.
    const geometry: number[][] = [
      [11, 48],
      [12, 48],
      [13, 48],
    ];
    const samples = sampleRoute(geometry, 7200);
    expect(samples.length).toBeGreaterThanOrEqual(2);
    expect(samples[0].distanceFromStartM).toBe(0);
    expect(samples[0].etaSeconds).toBe(0);
    const last = samples[samples.length - 1];
    expect(last.etaSeconds).toBeCloseTo(7200, 0);
    expect(last.lat).toBeCloseTo(48, 5);
    expect(last.lng).toBeCloseTo(13, 5);
  });

  it('leere/degenerate Geometrie -> keine Samples', () => {
    expect(sampleRoute([], 100)).toEqual([]);
    expect(sampleRoute([[11, 48]], 100)).toEqual([]);
  });
});

function buildService(
  env: Record<string, string | undefined>,
  poiFind: jest.Mock,
): WeatherService {
  const config = new ConfigService(env);
  return new WeatherService(config, { findInBoundingBox: poiFind } as never);
}

function owmHour(overrides: Record<string, unknown> = {}) {
  return {
    dt: Math.floor(Date.now() / 1000),
    temp: 18,
    wind_speed: 4,
    weather: [{ id: 800 }],
    ...overrides,
  };
}

describe('WeatherService', () => {
  const geometry: number[][] = [
    [11, 48],
    [11.01, 48],
  ];

  it('keyless ab Werk: Open-Meteo liefert den Report ohne OWM-Key (WMO-Mapping)', async () => {
    const poiFind = jest.fn();
    const service = buildService({}, poiFind);

    // Open-Meteo-Mock (WMO-Codes): Gewitter (95) -> OWM-201 -> danger.
    // Zeitpunkt dynamisch (~10 min ab jetzt), damit pickClosestHour
    // immer innerhalb des 45-min-Fensters liegt.
    const iso = new Date(Date.now() + 10 * 60_000).toISOString().slice(0, 16);
    jest.spyOn(require('axios'), 'get').mockResolvedValue({
      data: {
        hourly: {
          time: [iso],
          temperature_2m: [18],
          precipitation: [9],
          wind_gusts_10m: [20],
          weathercode: [95],
        },
      },
    });

    const report = await service.getRouteWeather(geometry, 600);
    expect(report.isEnabled).toBe(true);
    expect(report.segments.length).toBeGreaterThan(0);
    expect(report.alert).not.toBeNull();
    expect(report.alert!.severity).toBe('danger');
    expect(report.alert!.message).toContain('Gewitter');
  });

  it('OWM-Key gesetzt: Provider wechselt auf One Call (OWM-Antwortform)', async () => {
    const service = buildService({ OPENWEATHER_API_KEY: 'k' }, jest.fn());
    const axiosGet = jest.spyOn(require('axios'), 'get');
    axiosGet.mockReset();
    axiosGet.mockResolvedValue({
      data: { hourly: [owmHour()] },
    });

    const report = await service.getRouteWeather(geometry, 600);
    expect(report.isEnabled).toBe(true);
    // mockReset oben: der einzige Call ist der dieses Tests.
    expect(axiosGet.mock.calls[0][0]).toContain('openweathermap.org');
  });

  it('baut eine Warnung mit Fahrtrichtungs-Message + Shelters', async () => {
    const poiFind = jest.fn().mockResolvedValue([
      {
        id: 'h1',
        name: 'Bikerhotel',
        category: PoiCategory.MOTO_HOTEL,
        lat: 48.001,
        lng: 11.005,
      },
    ]);

    const service = buildService({ OPENWEATHER_API_KEY: 'k' }, poiFind);

    // OWM-Mock: nächste Stunde = Gewitter.
    jest.spyOn(require('axios'), 'get').mockResolvedValue({
      data: { hourly: [owmHour({ weather: [{ id: 211 }], rain: { '1h': 9 } })] },
    });

    const report = await service.getRouteWeather(geometry, 600);

    expect(report.isEnabled).toBe(true);
    expect(report.segments.length).toBeGreaterThan(0);
    expect(report.alert).not.toBeNull();
    expect(report.alert!.severity).toBe('danger');
    expect(report.alert!.message).toContain('Gewitter');
    expect(report.shelters).toHaveLength(1);
    expect(report.shelters[0].name).toBe('Bikerhotel');
  });

  it('unauffälliges Wetter: alert=null, shelters leer, POI-Service nicht gerufen', async () => {
    const poiFind = jest.fn();
    const service = buildService({ OPENWEATHER_API_KEY: 'k' }, poiFind);
    jest.spyOn(require('axios'), 'get').mockResolvedValue({
      data: { hourly: [owmHour()] },
    });

    const report = await service.getRouteWeather(geometry, 600);
    expect(report.alert).toBeNull();
    expect(report.shelters).toEqual([]);
    expect(poiFind).not.toHaveBeenCalled();
  });

  it('OWM-Ausfall degradiert: leere Segmente, kein Throw', async () => {
    const service = buildService({ OPENWEATHER_API_KEY: 'k' }, jest.fn());
    jest.spyOn(require('axios'), 'get').mockRejectedValue(new Error('down'));

    const report = await service.getRouteWeather(geometry, 600);
    expect(report.isEnabled).toBe(true);
    expect(report.segments).toEqual([]);
    expect(report.alert).toBeNull();
  });

  it('Shelter-Fehler kippt die Wetterwarnung nicht', async () => {
    const poiFind = jest.fn().mockRejectedValue(new Error('POI down'));
    const service = buildService({ OPENWEATHER_API_KEY: 'k' }, poiFind);
    jest.spyOn(require('axios'), 'get').mockResolvedValue({
      data: { hourly: [owmHour({ weather: [{ id: 211 }] })] },
    });

    const report = await service.getRouteWeather(geometry, 600);
    expect(report.alert).not.toBeNull();
    expect(report.shelters).toEqual([]);
  });
});
