/**
 * Privatsphaere-Serialisierung (Anforderung 15).
 *
 * Kennzeichen, Kaufpreis, Kaufdatum und Notizen sind privat. Diese Datei
 * ist die EINZIGE Stelle, die Fahrzeugobjekte in API-Antworten umwandelt -
 * so kann kein Endpunkt versehentlich private Felder leaken. Der Owner
 * bekommt alles, fremde Augen (spaeteres Sharing/Profil) nur die whitelist.
 */

export interface RawVehicleLike {
  id: string;
  category: 'motorcycle' | 'car';
  manufacturerName: string;
  modelName: string;
  variantName: string | null;
  year: number | null;
  firstRegistration: Date | null;
  nickname: string | null;
  color: string | null;
  licensePlate: string | null;
  odometerKm: number;
  purchaseDate: Date | null;
  purchasePriceCents: number | null;
  notes: string | null;
  photoUrl: string | null;
  isPublic: boolean;
  ownerId: string;
  createdAt: Date;
  updatedAt: Date;
}

/** Private Felder - NIEMALS in geteilten/oeffentlichen Antworten. */
const PRIVATE_FIELDS = ['licensePlate', 'purchasePriceCents', 'purchaseDate', 'notes'] as const;

/** Whitelist fuer fremde Augen (spaeteres Profil-Sharing). */
export function serializeVehicleForOwner(v: RawVehicleLike): Record<string, unknown> {
  return {
    id: v.id,
    category: v.category,
    manufacturerName: v.manufacturerName,
    modelName: v.modelName,
    variantName: v.variantName,
    year: v.year,
    firstRegistration: v.firstRegistration,
    nickname: v.nickname,
    color: v.color,
    licensePlate: v.licensePlate, // Owner sieht alles
    odometerKm: v.odometerKm,
    purchaseDate: v.purchaseDate,
    purchasePriceCents: v.purchasePriceCents,
    notes: v.notes,
    photoUrl: v.photoUrl,
    isPublic: v.isPublic,
    createdAt: v.createdAt,
    updatedAt: v.updatedAt,
  };
}

export function serializeVehicleForOthers(v: RawVehicleLike): Record<string, unknown> {
  const full = serializeVehicleForOwner(v);
  const out: Record<string, unknown> = {};
  for (const [k, value] of Object.entries(full)) {
    if (!(PRIVATE_FIELDS as readonly string[]).includes(k)) {
      out[k] = value;
    }
  }
  return out;
}

/** Wartungen enthalten Kosten + Notizen - fuer fremde Augen gekappt. */
export function serializeMaintenanceForOwner(m: Record<string, unknown>): Record<string, unknown> {
  return m;
}

export function serializeMaintenanceForOthers(m: Record<string, unknown>): Record<string, unknown> {
  const { costCents: _c, notes: _n, shopName: _s, ...rest } = m;
  return rest;
}
