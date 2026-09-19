import {
  StormAlert,
  WeatherSample,
  detectStorm,
  formatDistanceWarning,
  worstAlert,
} from './storm-detector';

function sample(overrides: Partial<WeatherSample> = {}): WeatherSample {
  return {
    time: '2026-09-18T10:00:00Z',
    tempC: 18,
    precipitationMmH: 0,
    conditionCode: 800,
    windSpeedMs: 4,
    windGustMs: 8,
    ...overrides,
  };
}

describe('detectStorm', () => {
  it('gibt none für unauffälliges Wetter', () => {
    const alert = detectStorm(sample());
    expect(alert.severity).toBe('none');
    expect(alert.message).toBe('');
  });

  it('advisory ab 2.5 mm/h Regen', () => {
    expect(detectStorm(sample({ precipitationMmH: 2.5 })).severity).toBe('advisory');
    expect(detectStorm(sample({ precipitationMmH: 2.4 })).severity).toBe('none');
  });

  it('danger ab 7.6 mm/h Starkregen', () => {
    const alert = detectStorm(sample({ precipitationMmH: 8 }));
    expect(alert.severity).toBe('danger');
    expect(alert.kind).toBe('rain');
    expect(alert.message).toContain('Starkregen');
  });

  it('JEDE Gewitter-Condition (2xx) ist danger', () => {
    for (const code of [200, 210, 230, 500]) {
      const alert = detectStorm(sample({ conditionCode: code }));
      if (code < 300) {
        expect(alert.severity).toBe('danger');
        expect(alert.kind).toBe('thunderstorm');
      } else {
        expect(alert.severity).toBe('none');
      }
    }
  });

  it('Sturmböen ab 17.2 m/s danger, advisory ab 10.8 m/s', () => {
    const danger = detectStorm(sample({ windGustMs: 17.2 }));
    expect(danger.severity).toBe('danger');
    expect(danger.kind).toBe('gusts');
    expect(detectStorm(sample({ windGustMs: 10.8 })).severity).toBe('advisory');
    expect(detectStorm(sample({ windGustMs: 10.7 })).severity).toBe('none');
  });

  it('fehlende Böen sind kein Alarm', () => {
    const s = sample();
    delete (s as { windGustMs?: number }).windGustMs;
    expect(detectStorm(s).severity).toBe('none');
  });

  it('Gewitter + Starkregen = mixed und danger', () => {
    const alert = detectStorm(sample({ conditionCode: 211, precipitationMmH: 10 }));
    expect(alert.severity).toBe('danger');
    expect(alert.kind).toBe('mixed');
    expect(alert.message).toContain('Gewitter');
    expect(alert.message).toContain('Starkregen');
  });

  it('Schneefall erscheint als Baustein', () => {
    const alert = detectStorm(sample({ conditionCode: 601 }));
    expect(alert.message).toContain('Schneefall');
    expect(alert.severity).toBe('advisory');
  });
});

describe('worstAlert', () => {
  it('null bei leeren/none-Listen', () => {
    expect(worstAlert([])).toBeNull();
    const none: StormAlert = { severity: 'none', message: '', kind: 'rain' };
    expect(worstAlert([none])).toBeNull();
  });

  it('wählt die höchste Severity, Gleichstand -> der erste', () => {
    const advisory: StormAlert = { severity: 'advisory', message: 'Regen', kind: 'rain' };
    const danger: StormAlert = { severity: 'danger', message: 'Gewitter', kind: 'thunderstorm' };
    expect(worstAlert([advisory, danger])).toBe(danger);
    expect(worstAlert([advisory, advisory])).toBe(advisory);
  });
});

describe('formatDistanceWarning', () => {
  const thunder: StormAlert = {
    severity: 'danger',
    message: 'Gewitter',
    kind: 'thunderstorm',
  };

  it('formuliert im geforderten Stil "In 20 km zieht ein Gewitter auf"', () => {
    expect(formatDistanceWarning(thunder, 20_000)).toBe('In 20 km zieht ein Gewitter auf: Gewitter');
  });

  it('kurze Distanzen = Am Startpunkt, lange = Streckenabschnitt', () => {
    expect(formatDistanceWarning(thunder, 300)).toContain('Am Startpunkt');
    expect(formatDistanceWarning(thunder, 150_000)).toContain('Auf späterem Streckenabschnitt');
  });

  it('Regen vs. Böen Verb-Auswahl', () => {
    const rain: StormAlert = { severity: 'advisory', message: 'Regen', kind: 'rain' };
    const gusts: StormAlert = { severity: 'advisory', message: 'Böen', kind: 'gusts' };
    expect(formatDistanceWarning(rain, 10_000)).toContain('kommt Regen auf');
    expect(formatDistanceWarning(gusts, 10_000)).toContain('sind Sturmböen möglich');
  });

  it('none -> leerer String', () => {
    expect(formatDistanceWarning({ severity: 'none', message: '', kind: 'rain' }, 1000)).toBe('');
  });
});
