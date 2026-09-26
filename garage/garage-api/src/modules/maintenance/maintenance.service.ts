import { prisma } from '../../common/prisma';
import { isMaintenanceType, maintenanceTypeOf } from '../../common/maintenance-types';
import { VehicleError } from '../vehicles/vehicles.service';

export interface MaintenanceDto {
  type: string;
  performedAt: string;
  odometerKm: number;
  nextDueDate?: string;
  nextDueOdometerKm?: number;
  costCents?: number;
  shopName?: string;
  notes?: string;
}

export class MaintenanceService {
  private async requireOwned(userId: string, vehicleId: string) {
    const vehicle = await prisma.vehicle.findUnique({ where: { id: vehicleId } });
    if (!vehicle || vehicle.ownerId !== userId) {
      throw new VehicleError(404, 'VEHICLE_NOT_FOUND', 'Fahrzeug nicht gefunden');
    }
    return vehicle;
  }

  async list(userId: string, vehicleId: string, type?: string) {
    await this.requireOwned(userId, vehicleId);
    const rows = await prisma.maintenance.findMany({
      where: { vehicleId, ...(type ? { type } : {}) },
      orderBy: { performedAt: 'desc' },
    });
    return { maintenance: rows };
  }

  async create(userId: string, vehicleId: string, dto: MaintenanceDto) {
    await this.requireOwned(userId, vehicleId);
    if (!isMaintenanceType(dto.type)) {
      throw new VehicleError(400, 'INVALID_TYPE', `Unbekannter Wartungstyp: ${dto.type}`);
    }

    const vehicle = await prisma.vehicle.findUnique({ where: { id: vehicleId } });
    if (dto.odometerKm > (vehicle?.odometerKm ?? 0) + 5_000) {
      // Großzügige Plausibilität: Wartung kaum mehr als 5000 km über dem
      // erfassten Stand (Schreibfehler-Schutz, bewusst nicht strikt).
      throw new VehicleError(400, 'ODOMETER_MISMATCH', 'Kilometerstand der Wartung liegt weit über dem Fahrzeugstand - erst Fahrzeug aktualisieren?');
    }

    const created = await prisma.maintenance.create({
      data: {
        vehicleId,
        ownerId: userId,
        type: dto.type,
        performedAt: new Date(dto.performedAt),
        odometerKm: dto.odometerKm,
        nextDueDate: dto.nextDueDate ? new Date(dto.nextDueDate) : null,
        nextDueOdometerKm: dto.nextDueOdometerKm ?? null,
        costCents: dto.costCents ?? null,
        shopName: dto.shopName ?? null,
        notes: dto.notes ?? null,
      },
    });

    // Auto-Vorschlag: wenn der Nutzer kein nextDue angab UND der Typ ein
    // Standard-Intervall hat, speichern wir die berechneten Werte NICHT
    // (die Erinnerungslogik rechnet sie live) - bewusst, damit der Nutzer
    // per Override jederzeit abweichen kann.
    return created;
  }

  async update(userId: string, maintenanceId: string, dto: Partial<MaintenanceDto>) {
    const existing = await prisma.maintenance.findUnique({ where: { id: maintenanceId } });
    if (!existing || existing.ownerId !== userId) {
      throw new VehicleError(404, 'MAINTENANCE_NOT_FOUND', 'Wartung nicht gefunden');
    }
    if (dto.type && !isMaintenanceType(dto.type)) {
      throw new VehicleError(400, 'INVALID_TYPE', `Unbekannter Wartungstyp: ${dto.type}`);
    }
    const updated = await prisma.maintenance.update({
      where: { id: maintenanceId },
      data: {
        ...(dto.type ? { type: dto.type } : {}),
        ...(dto.performedAt ? { performedAt: new Date(dto.performedAt) } : {}),
        ...(dto.odometerKm !== undefined ? { odometerKm: dto.odometerKm } : {}),
        ...(dto.nextDueDate !== undefined ? { nextDueDate: dto.nextDueDate ? new Date(dto.nextDueDate) : null } : {}),
        ...(dto.nextDueOdometerKm !== undefined ? { nextDueOdometerKm: dto.nextDueOdometerKm } : {}),
        ...(dto.costCents !== undefined ? { costCents: dto.costCents } : {}),
        ...(dto.shopName !== undefined ? { shopName: dto.shopName } : {}),
        ...(dto.notes !== undefined ? { notes: dto.notes } : {}),
      },
    });
    return updated;
  }

  async delete(userId: string, maintenanceId: string): Promise<void> {
    const existing = await prisma.maintenance.findUnique({ where: { id: maintenanceId } });
    if (!existing || existing.ownerId !== userId) {
      throw new VehicleError(404, 'MAINTENANCE_NOT_FOUND', 'Wartung nicht gefunden');
    }
    await prisma.maintenance.delete({ where: { id: maintenanceId } });
  }

  /** Chronologische Historie (Anforderung 7): aelteste zuerst. */
  async history(userId: string, vehicleId: string) {
    await this.requireOwned(userId, vehicleId);
    const rows = await prisma.maintenance.findMany({
      where: { vehicleId },
      orderBy: { performedAt: 'asc' },
    });
    const types = new Map(rows.map((r) => [r.type, maintenanceTypeOf(r.type)?.labelDe ?? r.type]));
    return {
      history: rows.map((r) => ({
        id: r.id,
        date: r.performedAt,
        type: r.type,
        label: types.get(r.type),
        odometerKm: r.odometerKm,
        costCents: r.costCents,
        shopName: r.shopName,
        notes: r.notes,
      })),
    };
  }

  /** Kosten-Aggregation (Anforderung 8). */
  async costs(userId: string, vehicleId: string) {
    await this.requireOwned(userId, vehicleId);
    const rows = await prisma.maintenance.findMany({
      where: { vehicleId },
      select: { costCents: true, performedAt: true, type: true },
    });
    const now = new Date();
    const yearStart = new Date(now.getFullYear(), 0, 1);

    let total = 0;
    let thisYear = 0;
    const perType = new Map<string, { count: number; totalCents: number }>();
    for (const r of rows) {
      const c = r.costCents ?? 0;
      total += c;
      if (r.performedAt >= yearStart) thisYear += c;
      const agg = perType.get(r.type) ?? { count: 0, totalCents: 0 };
      agg.count += 1;
      agg.totalCents += c;
      perType.set(r.type, agg);
    }

    return {
      vehicleId,
      totalCents: total,
      thisYearCents: thisYear,
      count: rows.length,
      averagePerServiceCents: rows.length ? Math.round(total / rows.length) : 0,
      perType: [...perType.entries()].map(([type, agg]) => ({
        type,
        count: agg.count,
        totalCents: agg.totalCents,
        averageCents: Math.round(agg.totalCents / agg.count),
      })),
    };
  }
}

export const maintenanceService = new MaintenanceService();
