import { serializeVehicleForOwner, serializeVehicleForOthers } from '../src/common/privacy';
import type { RawVehicleLike } from '../src/common/privacy';

const base: RawVehicleLike = {
  id: 'v-1',
  category: 'motorcycle',
  manufacturerName: 'BMW',
  modelName: 'R 1250 GS',
  variantName: 'Standard',
  year: 2024,
  firstRegistration: new Date('2024-03-01'),
  nickname: 'Gustav',
  color: 'Blau',
  licensePlate: 'M-XY 1234',
  odometerKm: 42350,
  purchaseDate: new Date('2024-04-01'),
  purchasePriceCents: 2_049_000,
  notes: 'Erste Inspektion beim Händler.',
  photoUrl: null,
  isPublic: false,
  ownerId: 'user-1',
  createdAt: new Date('2026-01-01'),
  updatedAt: new Date('2026-01-01'),
};

describe('Privatsphäre-Serialisierung', () => {
  it('Owner sieht alle Felder inkl. Kennzeichen/Kaufpreis/Notizen', () => {
    const out = serializeVehicleForOwner(base) as Record<string, unknown>;
    expect(out['licensePlate']).toBe('M-XY 1234');
    expect(out['purchasePriceCents']).toBe(2_049_000);
    expect(out['notes']).toContain('Inspektion');
  });

  it('Fremde Augen sehen KEINE privaten Felder (Anforderung 15)', () => {
    const out = serializeVehicleForOthers(base) as Record<string, unknown>;
    expect(out).not.toHaveProperty('licensePlate');
    expect(out).not.toHaveProperty('purchasePriceCents');
    expect(out).not.toHaveProperty('purchaseDate');
    expect(out).not.toHaveProperty('notes');
    // Öffentliche Basinfo bleiben:
    expect(out['manufacturerName']).toBe('BMW');
    expect(out['odometerKm']).toBe(42350);
  });
});
