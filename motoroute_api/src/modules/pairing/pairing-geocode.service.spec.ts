import { Test } from '@nestjs/testing';
import { ConfigService } from '@nestjs/config';
import axios from 'axios';
import { PairingGeocodeService } from './pairing-geocode.service';

// axios wird direkt importiert - deshalb hier mocken (wie in traffic.service.spec).
jest.mock('axios', () => ({ __esModule: true, default: { get: jest.fn() } }));

const axiosGet = axios.get as unknown as jest.Mock;

function buildService(): PairingGeocodeService {
  const config = {
    get: (key: string) => (key === 'NOMINATIM_URL' ? 'https://nominatim.test' : undefined),
  } as unknown as ConfigService;
  return new PairingGeocodeService(config);
}

describe('PairingGeocodeService', () => {
  beforeEach(() => {
    axiosGet.mockReset();
  });

  it('bildet Nominatim-Treffer auf label/detail/lat/lon ab', async () => {
    axiosGet.mockResolvedValue({
      status: 200,
      data: [
        {
          name: 'Eibsee',
          display_name: 'Eibsee, Grainau, Bayern, Deutschland',
          lat: '47.4582',
          lon: '10.9708',
        },
        { name: '', display_name: 'Irgendwo, Sonstwo', lat: '1', lon: '2' },
      ],
    });
    const service = buildService();
    const results = await service.search('Eibsee');

    expect(results).toHaveLength(2);
    expect(results[0]).toEqual({
      label: 'Eibsee',
      detail: 'Eibsee, Grainau, Bayern, Deutschland',
      lat: 47.4582,
      lon: 10.9708,
    });
    // Ohne name-Feld wird der erste Teil der Adresse zum Namen.
    expect(results[1].label).toBe('Irgendwo');
    const call = axiosGet.mock.calls[0];
    expect(call[0]).toBe('https://nominatim.test/search');
    expect(call[1].headers['User-Agent']).toContain('MotoRoute-Planer');
    expect(call[1].params['accept-language']).toBe('de');
  });

  it('wirft unbrauchbare Koordinaten weg und kappt bei 5 Treffern', async () => {
    const many = Array.from({ length: 9 }, (_, i) => ({
      name: `Ort ${i}`,
      display_name: `Ort ${i}`,
      lat: '47',
      lon: '11',
    }));
    many.push({ name: 'Kaputt', display_name: 'Kaputt', lat: '999', lon: '11' });
    axiosGet.mockResolvedValue({ status: 200, data: many });

    const results = await buildService().search('Ort');
    expect(results).toHaveLength(5);
    expect(results.every((r) => r.label !== 'Kaputt')).toBe(true);
  });

  it('Nominatim drosselt (429) -> 429 nach aussen', async () => {
    axiosGet.mockResolvedValue({ status: 429, data: 'slow down' });
    await expect(buildService().search('Eibsee')).rejects.toMatchObject({
      status: 429,
    });
  });

  it('Nominatim antwortet mit Serverfehler -> 502', async () => {
    axiosGet.mockResolvedValue({ status: 500, data: 'boom' });
    await expect(buildService().search('Eibsee')).rejects.toMatchObject({
      status: 502,
    });
  });

  it('Nominatim nicht erreichbar -> 503', async () => {
    axiosGet.mockRejectedValue(new Error('ECONNREFUSED'));
    await expect(buildService().search('Eibsee')).rejects.toMatchObject({
      status: 503,
    });
  });

  it('cacht identische Suchen: keine zweite Fremdanfrage', async () => {
    axiosGet.mockResolvedValue({
      status: 200,
      data: [{ name: 'Eibsee', display_name: 'Eibsee', lat: '47.4', lon: '10.9' }],
    });
    const service = buildService();
    await service.search('Eibsee');
    await service.search('  eibsee  ');
    expect(axiosGet).toHaveBeenCalledTimes(1);
  });
});
