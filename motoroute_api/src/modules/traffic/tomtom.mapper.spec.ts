import { mapTomTomIncidents } from './tomtom.mapper';

describe('mapTomTomIncidents', () => {
  it('mappt iconCategory und magnitudeOfDelay auf die neutralen Typen', () => {
    const result = mapTomTomIncidents({
      incidents: [
        {
          type: 'Feature',
          geometry: { type: 'Line', coordinates: [[11.0, 48.0], [11.1, 48.01]] },
          properties: {
            id: 'tt-1',
            iconCategory: 8,
            magnitudeOfDelay: 3,
            from: 'A8 Ausfahrt',
            to: 'Kreisverkehr',
            events: [{ description: 'Gesperrt', code: 21 }],
          },
        },
      ],
    });

    expect(result).toHaveLength(1);
    expect(result[0]).toMatchObject({
      id: 'tt-1',
      category: 'ROAD_CLOSED',
      severity: 'HIGH',
      description: 'Gesperrt',
    });
    expect(result[0].geometry).toEqual([[11.0, 48.0], [11.1, 48.01]]);
  });

  it('ordnet Wetter-Kategorien (2,3,4,5,10,11) WEATHER zu', () => {
    const result = mapTomTomIncidents({
      incidents: [
        {
          geometry: { type: 'Point', coordinates: [11.0, 48.0] },
          properties: { id: 'tt-2', iconCategory: 4, magnitudeOfDelay: 1 },
        },
        {
          geometry: { type: 'Point', coordinates: [11.0, 48.0] },
          properties: { id: 'tt-3', iconCategory: 11, magnitudeOfDelay: 0 },
        },
      ],
    });

    expect(result[0].category).toBe('WEATHER');
    expect(result[0].severity).toBe('LOW');
    expect(result[1].category).toBe('WEATHER');
    expect(result[1].severity).toBe('UNKNOWN');
  });

  it('flattet MultiLineString-Geometrien', () => {
    const result = mapTomTomIncidents({
      incidents: [
        {
          geometry: {
            type: 'MultiLine',
            coordinates: [[[11.0, 48.0], [11.05, 48.005]], [[11.05, 48.005], [11.1, 48.01]]],
          },
          properties: { id: 'tt-4', iconCategory: 6, magnitudeOfDelay: 2 },
        },
      ],
    });

    expect(result[0].geometry).toHaveLength(4);
    expect(result[0].geometry[3]).toEqual([11.1, 48.01]);
  });

  it('verwirft Elemente ohne nutzbare Geometrie, statt halbgarp zu liefern', () => {
    const result = mapTomTomIncidents({
      incidents: [
        { geometry: { type: 'Line', coordinates: [] }, properties: { id: 'x' } },
        { geometry: null, properties: { id: 'y' } },
        { properties: { id: 'z' } },
        {
          geometry: { type: 'Point', coordinates: [11.0, 48.0] },
          properties: { id: 'ok', iconCategory: 9, magnitudeOfDelay: 2 },
        },
      ],
    });

    expect(result).toHaveLength(1);
    expect(result[0].category).toBe('ROAD_WORKS');
  });

  it('liefert [] für nicht-Array- oder leere Responses (Degradierung)', () => {
    expect(mapTomTomIncidents(undefined)).toEqual([]);
    expect(mapTomTomIncidents({})).toEqual([]);
    expect(mapTomTomIncidents({ incidents: [] })).toEqual([]);
  });
});
