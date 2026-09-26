import { prisma } from '../../common/prisma';
import { serializeVehicleForOwner } from '../../common/privacy';
import { maintenanceTypesFor } from '../../common/maintenance-types';
import { computeReminder, worstStatus, type Reminder } from '../../common/reminders';

export class VehicleError extends Error {
  constructor(
    public status: number,
    public code: string,
    message: string,
  ) {
    super(message);
  }
}

const VEHICLE_INCLUDE = {
  variant: { select: { id: true, name: true } },
  _count: { select: { maintences: true, tires: true, documents: true, fuelEntries: true } },
} as const;

type VehicleRow = {
  id: string;
  ownerId: string;
  category: 'motorcycle' | 'car';
  manufacturerName: string;
  modelName: string;
  variantName: string | null;
  variant: { id: string; name: string } | null;
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
  createdAt: Date;
  updatedAt: Date;
  _count: { maintences: number; tires: number; documents: number; fuelEntries: number };
};

export class VehiclesService {
  /** Sicherheitsnetz: Ownership prüfen (RLS-artig auf Service-Ebene). */
  private async requireOwned(userId: string, vehicleId: string): Promise<VehicleRow> {
    const vehicle = (await prisma.vehicle.findUnique({
      where: { id: vehicleId },
      include: VEHICLE_INCLUDE,
    })) as unknown as VehicleRow | null;
    if (!vehicle || vehicle.ownerId !== userId) {
      throw new VehicleError(404, 'VEHICLE_NOT_FOUND', 'Fahrzeug nicht gefunden');
    }
    return vehicle;
  }

  async create(
    userId: string,
    dto: {
      category: 'motorcycle' | 'car';
      variantId?: string;
      manufacturerName: string;
      modelName: string;
      variantName?: string;
      year?: number;
      firstRegistration?: string;
      nickname?: string;
      color?: string;
      licensePlate?: string;
      odometerKm?: number;
      purchaseDate?: string;
      purchasePriceCents?: number;
      notes?: string;
      photoUrl?: string;
    },
  ): Promise<Record<string, unknown>> {
    let manufacturerId: string | null = null;
    let manufacturerName = dto.manufacturerName;
    let variantName = dto.variantName;

    if (dto.variantId) {
      const variant = await prisma.variant.findUnique({
        where: { id: dto.variantId },
        include: { model: { include: { manufacturer: true } } },
      });
      if (!variant) {
        throw new VehicleError(400, 'VARIANT_NOT_FOUND', 'Unbekannte Variante');
      }
      manufacturerId = variant.model.manufacturerId;
      // Snapshot aus dem Katalog, wenn der Nutzer nichts eigenes angab.
      manufacturerName = variant.model.manufacturer.name;
      if (!variantName) variantName = variant.name;
    }

      const vehicle = (await prisma.vehicle.create({
      data: {
        ownerId: userId,
        category: dto.category,
        variantId: dto.variantId ?? null,
        manufacturerId,
        manufacturerName,
        modelName: dto.modelName,
        variantName: variantName ?? null,
        year: dto.year ?? null,
        firstRegistration: dto.firstRegistration ? new Date(dto.firstRegistration) : null,
        nickname: dto.nickname ?? null,
        color: dto.color ?? null,
        licensePlate: dto.licensePlate ?? null,
        odometerKm: dto.odometerKm ?? 0,
        purchaseDate: dto.purchaseDate ? new Date(dto.purchaseDate) : null,
        purchasePriceCents: dto.purchasePriceCents ?? null,
        notes: dto.notes ?? null,
        photoUrl: dto.photoUrl ?? null,
      },
      include: VEHICLE_INCLUDE,
    })) as unknown as VehicleRow;

    return serializeVehicleForOwner(vehicle);
  }

  /** Die Garage: alle Fahrzeuge des Nutzers, gruppiert + Erinnerungs-Badge. */
  async garage(userId: string) {
    const vehicles = (await prisma.vehicle.findMany({
      where: { ownerId: userId },
      orderBy: { createdAt: 'desc' },
      include: VEHICLE_INCLUDE,
    })) as unknown as VehicleRow[];

    const motorcycles: Record<string, unknown>[] = [];
    const cars: Record<string, unknown>[] = [];

    for (const vehicle of vehicles) {
      const { worst } = await this.remindersFor(vehicle);
      const card = {
        ...serializeVehicleForOwner(vehicle),
        maintenanceWorstStatus: worst,
        counts: vehicle._count,
      };
      if (vehicle.category === 'motorcycle') motorcycles.push(card);
      else cars.push(card);
    }

    return { motorcycles, cars };
  }

  async get(userId: string, vehicleId: string): Promise<Record<string, unknown>> {
    const vehicle = await this.requireOwned(userId, vehicleId);
    return serializeVehicleForOwner(vehicle);
  }

  async update(
    userId: string,
    vehicleId: string,
    dto: Partial<{
      nickname: string;
      color: string;
      licensePlate: string;
      odometerKm: number;
      purchaseDate: string;
      purchasePriceCents: number;
      notes: string;
      photoUrl: string;
      isPublic: boolean;
    }>,
  ): Promise<Record<string, unknown>> {
    await this.requireOwned(userId, vehicleId);
    const data: Record<string, unknown> = {};
    if (dto.nickname !== undefined) data['nickname'] = dto.nickname;
    if (dto.color !== undefined) data['color'] = dto.color;
    if (dto.licensePlate !== undefined) data['licensePlate'] = dto.licensePlate;
    if (dto.odometerKm !== undefined) {
      if (dto.odometerKm < 0) throw new VehicleError(400, 'INVALID_ODOMETER', 'Kilometerstand darf nicht negativ sein');
      data['odometerKm'] = Math.round(dto.odometerKm);
    }
    if (dto.purchaseDate !== undefined) data['purchaseDate'] = dto.purchaseDate ? new Date(dto.purchaseDate) : null;
    if (dto.purchasePriceCents !== undefined) data['purchasePriceCents'] = dto.purchasePriceCents;
    if (dto.notes !== undefined) data['notes'] = dto.notes;
    if (dto.photoUrl !== undefined) data['photoUrl'] = dto.photoUrl;
    if (dto.isPublic !== undefined) data['isPublic'] = dto.isPublic;

    const vehicle = (await prisma.vehicle.update({
      where: { id: vehicleId },
      data,
      include: VEHICLE_INCLUDE,
    })) as unknown as VehicleRow;
    return serializeVehicleForOwner(vehicle);
  }

  async delete(userId: string, vehicleId: string): Promise<void> {
    await this.requireOwned(userId, vehicleId);
    await prisma.vehicle.delete({ where: { id: vehicleId } });
  }

  /** Technische Daten: aus der zentralen DB (Anforderung 3/14). */
  async specifications(userId: string, vehicleId: string) {
    const vehicle = await this.requireOwned(userId, vehicleId);
    if (!vehicle.variant) {
      return {
        vehicleId,
        source: 'none' as const,
        specs: [],
        note: 'Fahrzeug ist nicht mit der zentralen Fahrzeugdatenbank verknüpft.',
      };
    }
    const { specs } = await import('../catalog/catalog.service').then((m) =>
      m.catalogService.specsForVariant(vehicle.variant!.id, vehicle.year ?? undefined),
    );
    return { vehicleId, source: 'catalog' as const, variant: vehicle.variant, specs };
  }

  /** Erinnerungen je Fahrzeug (alle passenden Typen, aktuelle Werte). */
  async remindersFor(vehicle: VehicleRow): Promise<{ reminders: Reminder[]; worst: string }> {
    const lastByType = await prisma.maintenance.groupBy({
      by: ['type'],
      where: { vehicleId: vehicle.id },
      _max: { performedAt: true, odometerKm: true },
      _min: { nextDueDate: true, nextDueOdometerKm: true },
    });

    // groupBy reicht nicht fuer "neueste Zeile je Typ inkl. nextDue" -
    // deshalb sauber nachladen:
    const lastes = await Promise.all(
      lastByType.map(async (g) => {
        const row = await prisma.maintenance.findFirst({
          where: { vehicleId: vehicle.id, type: g.type },
          orderBy: { performedAt: 'desc' },
        });
        return row;
      }),
    );

    const lastMap = new Map(lastes.filter(Boolean).map((m) => [m!.type, m!]));
    const types = maintenanceTypesFor(vehicle.category);

    const reminders = types.map((t) =>
      computeReminder(
        { key: t.key, labelDe: t.labelDe, intervalKm: t.intervalKm, intervalDays: t.intervalDays },
        lastMap.has(t.key)
          ? {
              type: t.key,
              performedAt: lastMap.get(t.key)!.performedAt,
              odometerKm: lastMap.get(t.key)!.odometerKm,
              nextDueDate: lastMap.get(t.key)!.nextDueDate,
              nextDueOdometerKm: lastMap.get(t.key)!.nextDueOdometerKm,
            }
          : null,
        vehicle.odometerKm,
      ),
    );

    // Nur relevante zeigen: rote/gelbe immer, gruen komprimiert.
    const visible = reminders.filter((r) => r.status !== 'none');
    return { reminders: visible, worst: worstStatus(visible.map((r) => r.status)) };
  }

  async reminders(userId: string, vehicleId: string) {
    const vehicle = await this.requireOwned(userId, vehicleId);
    const { reminders, worst } = await this.remindersFor(vehicle);
    return { vehicleId, odometerKm: vehicle.odometerKm, worstStatus: worst, reminders };
  }
}

export const vehiclesService = new VehiclesService();
