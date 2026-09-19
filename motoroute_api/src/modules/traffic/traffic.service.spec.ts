import { TrafficService } from './traffic.service';
import { mapTomTomIncidents } from './tomtom.mapper';

function configWith(enabled: boolean) {
  return { get: (key: string) => (key === 'TRAFFIC_API_KEY' && enabled ? 'test-key' : undefined) };
}

// axios mocken: TrafficService importiert axios direkt.
jest.mock('axios', () => ({ __esModule: true, default: { get: jest.fn() } }));
import axios from 'axios';

describe('TrafficService', () => {
  const bbox = [11.0, 48.0, 12.0, 48.5]; // minLng,minLat,maxLng,maxLat

  beforeEach(() => {
    jest.clearAllMocks();
    jest.useFakeTimers();
  });

  afterEach(() => {
    jest.useRealTimers();
  });

  it('liefert [] ohne Key (feature disabled), ohne TomTom zu rufen', async () => {
    const service = new TrafficService(configWith(false) as never);
    const result = await service.getIncidentsInBoundingBox(bbox);
    expect(result).toEqual([]);
    expect(axios.get).not.toHaveBeenCalled();
  });

  it('ruft TomTom mit vertauschter bbox-Reihenfolge (TomTom: lat zuerst) auf', async () => {
    (axios.get as jest.Mock).mockResolvedValue({ data: { incidents: [] } });
    const service = new TrafficService(configWith(true) as never);
    await service.getIncidentsInBoundingBox(bbox);

    expect(axios.get).toHaveBeenCalledTimes(1);
    const call = (axios.get as jest.Mock).mock.calls[0];
    expect(call[0]).toContain('incidentDetails');
    expect(call[1].params.bbox).toBe('48,11,48.5,12');
  });

  it('cached Ergebnisse für 60 s (zweiter Call geht nicht an TomTom)', async () => {
    (axios.get as jest.Mock).mockResolvedValue({
      data: {
        incidents: [
          {
            geometry: { type: 'Point', coordinates: [11.5, 48.2] },
            properties: { id: 'i-1', iconCategory: 6, magnitudeOfDelay: 2 },
          },
        ],
      },
    });
    const service = new TrafficService(configWith(true) as never);

    const first = await service.getIncidentsInBoundingBox(bbox);
    const second = await service.getIncidentsInBoundingBox(bbox);

    expect(axios.get).toHaveBeenCalledTimes(1);
    expect(second).toEqual(first);
    expect(mapTomTomIncidents({ incidents: [{ properties: { id: 'i-1' } }] }).length).toBe(0); // sanity: ohne Geometrie verworfen

    jest.advanceTimersByTime(61_000);
    (axios.get as jest.Mock).mockClear();
    await service.getIncidentsInBoundingBox(bbox);
    expect(axios.get).toHaveBeenCalledTimes(1); // nach TTL wieder frisch
  });

  it('degradiert bei Provider-Ausfall zu [] statt zu werfen', async () => {
    (axios.get as jest.Mock).mockRejectedValue(new Error('timeout'));
    const service = new TrafficService(configWith(true) as never);

    await expect(service.getIncidentsInBoundingBox(bbox)).resolves.toEqual([]);
  });
});
