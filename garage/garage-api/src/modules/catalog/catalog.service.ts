import { prisma } from '../../common/prisma';
import { SPEC_KEYS } from '../../common/spec-keys';

export interface ResolvedSpecs {
  variantId: string | null;
  specs: { key: string; labelDe: string; labelEn: string; value: string; unit: string | null }[];
}

/**
 * Katalog-Service (Anforderung 3 + 12 + 13): zentrale Fahrzeugdatenbank
 * mit Suche nach Hersteller -> Modell -> Variante/Baujahr.
 */
export class CatalogService {
  /** Hersteller-Liste (aktive zuerst). */
  async manufacturers(includeInactive = false) {
    return prisma.manufacturer.findMany({
      where: includeInactive ? {} : { isActive: true },
      orderBy: { name: 'asc' },
      select: { id: true, name: true, country: true, isActive: true },
    });
  }

  /** Modelle eines Herstellers. */
  async models(manufacturerId: string) {
    return prisma.model.findMany({
      where: { manufacturerId, isActive: true },
      orderBy: { name: 'asc' },
      select: { id: true, name: true, category: true },
    });
  }

  /** Varianten eines Modells inkl. Baujahresbereich. */
  async variants(modelId: string) {
    return prisma.variant.findMany({
      where: { modelId, model: { isActive: true } },
      orderBy: { name: 'asc' },
      select: { id: true, name: true, years: true },
    });
  }

  /**
   * Freitext-Suche (Anforderung 13): "BMW R 1250 GS 2024" oder Schritt-
   * weise ueber die Endpunkte. Alle Begriffe muessen (UND) in Hersteller,
   * Modell oder Variante vorkommen.
   */
  async search(q: string, category?: 'motorcycle' | 'car', year?: number, limit = 25) {
    const terms = q.trim().split(/\s+/).filter((t) => t.length >= 2).slice(0, 4);

    const variants = await prisma.variant.findMany({
      where: {
        ...(category ? { model: { category } } : {}),
        ...(terms.length > 0
          ? {
              OR: [
                { name: { contains: terms[0], mode: 'insensitive' as const } },
                { model: { name: { contains: terms[0], mode: 'insensitive' as const } } },
                { model: { manufacturer: { name: { contains: terms[0], mode: 'insensitive' as const } } } },
              ],
              AND: terms.slice(1).map((t) => ({
                OR: [
                  { name: { contains: t, mode: 'insensitive' as const } },
                  { model: { name: { contains: t, mode: 'insensitive' as const } } },
                  { model: { manufacturer: { name: { contains: t, mode: 'insensitive' as const } } } },
                ],
              })),
            }
          : {}),
      },
      take: limit,
      select: {
        id: true,
        name: true,
        years: true,
        model: {
          select: { name: true, category: true, manufacturer: { select: { name: true } } },
        },
      },
    });

    // Baujahr-Filter im Ergebnis (years ist Freitext-Bereich).
    const filtered = year
      ? variants.filter((v) => {
          const m = v.years?.match(/(\d{4})\s*[-–]?\s*(\d{4})?/);
          if (!m) return false;
          const from = Number(m[1]);
          const to = m[2] ? Number(m[2]) : new Date().getFullYear();
          return year >= from && year <= to;
        })
      : variants;

    return {
      results: filtered.map((v) => ({
        variantId: v.id,
        manufacturer: v.model.manufacturer.name,
        model: v.model.name,
        variant: v.name,
        category: v.model.category,
        years: v.years,
      })),
    };
  }

  /** Specs einer Variante (optional nach Baujahr gefiltert). */
  async specsForVariant(variantId: string, year?: number): Promise<ResolvedSpecs> {
    const rows = await prisma.vehicleSpec.findMany({
      where: { variantId },
      orderBy: { key: 'asc' },
    });
    const applicable = year
      ? rows.filter((r) => (r.yearFrom == null || year >= r.yearFrom) && (r.yearTo == null || year <= r.yearTo))
      : rows.filter((r) => r.yearFrom == null); // ohne Jahr: nur allgemeingueltige

    const seen = new Map<string, { key: string; value: string; unit: string | null }>();
    for (const r of applicable) {
      if (!seen.has(r.key)) seen.set(r.key, { key: r.key, value: r.value, unit: r.unit });
    }

    // Nur definierte Schluessel ausliefern (geordnete Anzeige).
    const ordered = [...SPEC_KEYS]
      .map((def) => {
        const hit = seen.get(def.key);
        return hit ? { ...hit, labelDe: def.labelDe, labelEn: def.labelEn } : null;
      })
      .filter((x): x is NonNullable<typeof x> => x !== null);

    return { variantId, specs: ordered };
  }
}

export const catalogService = new CatalogService();
