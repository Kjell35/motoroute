import { MAINTENANCE_TYPES, maintenanceTypesFor, isMaintenanceType } from '../src/common/maintenance-types';

describe('Wartungstypen-Katalog (Anforderung 5)', () => {
  it('enthält alle geforderten Basis-Typen', () => {
    const keys = MAINTENANCE_TYPES.map((t) => t.key);
    for (const key of ['OIL_CHANGE', 'OIL_FILTER', 'AIR_FILTER', 'BRAKE_PADS', 'BRAKE_DISCS', 'TIRES', 'BATTERY', 'COOLANT', 'BRAKE_FLUID', 'SPARK_PLUGS', 'INSPECTION', 'OTHER']) {
      expect(keys).toContain(key);
    }
  });

  it('Motorrad-Typen: Kette drin, Zahnriemen/HU raus', () => {
    const keys = maintenanceTypesFor('motorcycle').map((t) => t.key);
    expect(keys).toContain('CHAIN');
    expect(keys).toContain('CHAIN_OIL');
    expect(keys).not.toContain('TIMING_BELT');
    expect(keys).not.toContain('HU');
  });

  it('Auto-Typen: Zahnriemen + HU/AU drin, Kette raus', () => {
    const keys = maintenanceTypesFor('car').map((t) => t.key);
    expect(keys).toContain('TIMING_BELT');
    expect(keys).toContain('HU');
    expect(keys).toContain('AU');
    expect(keys).not.toContain('CHAIN');
  });

  it('HU/TÜV ist dateOnly (kein km-Intervall)', () => {
    const hu = MAINTENANCE_TYPES.find((t) => t.key === 'HU')!;
    expect(hu.dateOnly).toBe(true);
    expect(hu.intervalKm).toBeUndefined();
  });

  it('isMaintenanceType lehnt Unbekanntes ab', () => {
    expect(isMaintenanceType('OIL_CHANGE')).toBe(true);
    expect(isMaintenanceType('FLUEGELWECHSEL')).toBe(false);
  });
});
