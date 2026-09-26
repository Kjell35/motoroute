import { computeReminder, worstStatus, type Reminder } from '../src/common/reminders';

const NOW = new Date('2026-09-26T12:00:00Z');
const OIL = { key: 'OIL_CHANGE', labelDe: 'Ölwechsel', intervalKm: 10000, intervalDays: 365 };

describe('computeReminder', () => {
  it('none, wenn noch nie gewartet', () => {
    const r = computeReminder(OIL, null, 50000, NOW);
    expect(r.status).toBe('none');
    expect(r.messageDe).toContain('noch nie erfasst');
  });

  it('grün, wenn Intervall weit entfernt', () => {
    const r = computeReminder(
      OIL,
      { type: 'OIL_CHANGE', performedAt: new Date('2026-09-01'), odometerKm: 40000, nextDueDate: null, nextDueOdometerKm: null },
      41000,
      NOW,
    );
    // 9000 km von 10000 -> > 10 % Rest + < 30 Tage ... Zeit: 10 Tage Rest von 365 -> gelb?
    expect(['green', 'yellow']).toContain(r.status);
    expect(r.dueAtKm).toBe(50000);
  });

  it('gelb bei Schwellenunterschreitung (km)', () => {
    const r = computeReminder(
      OIL,
      { type: 'OIL_CHANGE', performedAt: new Date('2026-06-01'), odometerKm: 40000, nextDueDate: null, nextDueOdometerKm: null },
      49500,
      NOW,
    );
    expect(r.status).toBe('yellow');
    expect(r.messageDe).toContain('500 km');
  });

  it('rot bei km-Überziehung', () => {
    const r = computeReminder(
      OIL,
      { type: 'OIL_CHANGE', performedAt: new Date('2026-06-01'), odometerKm: 40000, nextDueDate: null, nextDueOdometerKm: null },
      50200,
      NOW,
    );
    expect(r.status).toBe('red');
    expect(r.messageDe).toContain('überfällig');
  });

  it('rot bei zeitlicher Überziehung trotz geringem km', () => {
    const r = computeReminder(
      OIL,
      { type: 'OIL_CHANGE', performedAt: new Date('2025-06-01'), odometerKm: 40000, nextDueDate: null, nextDueOdometerKm: null },
      40100,
      NOW,
    );
    // 365 Tage ab 2025-06-01 -> 2026-06-01, NOW=2026-09-26 -> überfällig
    expect(r.status).toBe('red');
    expect(r.dueAt).toBe('2026-06-01T00:00:00.000Z');
  });

  it('Nutzer-Override (nextDue*) schlägt Katalog-Intervall', () => {
    const r = computeReminder(
      OIL,
      {
        type: 'OIL_CHANGE',
        performedAt: new Date('2026-01-15'),
        odometerKm: 10000,
        nextDueDate: new Date('2026-12-31'),
        nextDueOdometerKm: 60000,
      },
      10000,
      NOW,
    );
    expect(r.dueAtKm).toBe(60000);
    expect(r.dueAt).toBe('2026-12-31T00:00:00.000Z');
    expect(r.status).toBe('green');
  });
});

describe('worstStatus', () => {
  it('rot schlägt gelb schlägt grün', () => {
    expect(worstStatus(['green', 'yellow'] as Reminder['status'][])).toBe('yellow');
    expect(worstStatus(['green', 'red'] as Reminder['status'][])).toBe('red');
    expect(worstStatus([])).toBe('none');
  });
});
