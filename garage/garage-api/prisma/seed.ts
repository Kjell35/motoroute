/**
 * Katalog-Starter (Anforderung 12/18): ECHTE Fahrzeugdaten als Startpunkt
 * der zentralen Datenbank - keine Dummy-Zeilen. Erweiterbar per Admin-API.
 *
 * Ausführen: npm run seed  (nach prisma generate + db push)
 */
import { PrismaClient } from '@prisma/client';

const prisma = new PrismaClient();

async function upsertSpec(variantId: string, s: { key: string; value: string; unit?: string }): Promise<void> {
  // Prisma erlaubt KEINE null-Werte im where eines Compound-Uniques -
  // deshalb Lesen-then-Schreiben statt upsert (idempotent genug fuer den Seed).
  const existing = await prisma.vehicleSpec.findFirst({
    where: { variantId, key: s.key, yearFrom: null, yearTo: null },
  });
  if (existing) {
    await prisma.vehicleSpec.update({
      where: { id: existing.id },
      data: { value: s.value, unit: s.unit ?? null },
    });
  } else {
    await prisma.vehicleSpec.create({
      data: { variantId, key: s.key, value: s.value, unit: s.unit ?? null },
    });
  }
}

async function main(): Promise<void> {
  console.log('Seed: Starter-Katalog ...');

  // --- BMW ---
  const bmw = await prisma.manufacturer.upsert({
    where: { name: 'BMW' },
    update: {},
    create: { name: 'BMW', country: 'Deutschland' },
  });

  const r1250 = await prisma.model.upsert({
    where: { manufacturerId_name: { manufacturerId: bmw.id, name: 'R 1250 GS' } },
    update: {},
    create: { manufacturerId: bmw.id, name: 'R 1250 GS', category: 'motorcycle' },
  });

  const r1250Std = await prisma.variant.upsert({
    where: { modelId_name: { modelId: r1250.id, name: 'Standard' } },
    update: {},
    create: { modelId: r1250.id, name: 'Standard', years: '2019-2026' },
  });

  const r1250Specs = [
    { key: 'engine', value: 'Boxer 2-Zylinder, 4-Takt, DOHC, luft-/ölgekühlt' },
    { key: 'engine_displacement_cc', value: '1254', unit: 'ccm' },
    { key: 'power_hp', value: '136', unit: 'PS' },
    { key: 'torque_nm', value: '143', unit: 'Nm' },
    { key: 'fuel_type', value: 'Benzin' },
    { key: 'gearbox', value: '6-Gang' },
    { key: 'weight_kg', value: '249', unit: 'kg' },
    { key: 'tank_capacity_l', value: '20', unit: 'l' },
    { key: 'consumption', value: '4.75', unit: 'l/100km' },
    { key: 'top_speed_kmh', value: '200+', unit: 'km/h' },
    { key: 'drive', value: 'Kardan' },
    { key: 'tire_sizes', value: 'VA 120/70 R19, HA 170/55 R17' },
    { key: 'brakes', value: 'Doppelscheibe VA 305 mm, Scheibe HA 276 mm, ABS' },
  ];
  for (const s of r1250Specs) {
    await upsertSpec(r1250Std.id, s);
  }

  // --- Yamaha ---
  const yamaha = await prisma.manufacturer.upsert({
    where: { name: 'Yamaha' },
    update: {},
    create: { name: 'Yamaha', country: 'Japan' },
  });
  const mt07 = await prisma.model.upsert({
    where: { manufacturerId_name: { manufacturerId: yamaha.id, name: 'MT-07' } },
    update: {},
    create: { manufacturerId: yamaha.id, name: 'MT-07', category: 'motorcycle' },
  });
  const mt07Std = await prisma.variant.upsert({
    where: { modelId_name: { modelId: mt07.id, name: 'Standard' } },
    update: {},
    create: { modelId: mt07.id, name: 'Standard', years: '2014-2026' },
  });
  const mt07Specs = [
    { key: 'engine', value: '2-Zylinder Reihe, DOHC, flüssigkeitsgekühlt' },
    { key: 'engine_displacement_cc', value: '689', unit: 'ccm' },
    { key: 'power_hp', value: '73.4', unit: 'PS' },
    { key: 'torque_nm', value: '67', unit: 'Nm' },
    { key: 'fuel_type', value: 'Benzin' },
    { key: 'gearbox', value: '6-Gang' },
    { key: 'weight_kg', value: '184', unit: 'kg' },
    { key: 'tank_capacity_l', value: '14', unit: 'l' },
    { key: 'consumption', value: '4.2', unit: 'l/100km' },
    { key: 'top_speed_kmh', value: '205', unit: 'km/h' },
    { key: 'drive', value: 'Kette' },
    { key: 'tire_sizes', value: 'VA 120/70 ZR17, HA 180/55 ZR17' },
  ];
  for (const s of mt07Specs) {
    await upsertSpec(mt07Std.id, s);
  }

  // --- Volkswagen ---
  const vw = await prisma.manufacturer.upsert({
    where: { name: 'Volkswagen' },
    update: {},
    create: { name: 'Volkswagen', country: 'Deutschland' },
  });
  const golf = await prisma.model.upsert({
    where: { manufacturerId_name: { manufacturerId: vw.id, name: 'Golf' } },
    update: {},
    create: { manufacturerId: vw.id, name: 'Golf', category: 'car' },
  });
  const golfGti = await prisma.variant.upsert({
    where: { modelId_name: { modelId: golf.id, name: 'GTI' } },
    update: {},
    create: { modelId: golf.id, name: 'GTI', years: '2020-2026' },
  });
  const golfSpecs = [
    { key: 'engine', value: 'R4 TSI Turbo, Benzin' },
    { key: 'engine_displacement_cc', value: '1984', unit: 'ccm' },
    { key: 'power_hp', value: '245', unit: 'PS' },
    { key: 'torque_nm', value: '370', unit: 'Nm' },
    { key: 'fuel_type', value: 'Benzin' },
    { key: 'gearbox', value: '7-Gang DSG / 6-Gang manuell' },
    { key: 'weight_kg', value: '1429', unit: 'kg' },
    { key: 'tank_capacity_l', value: '50', unit: 'l' },
    { key: 'consumption', value: '6.9', unit: 'l/100km' },
    { key: 'top_speed_kmh', value: '250', unit: 'km/h' },
    { key: 'acceleration_0_100_s', value: '6.2', unit: 's' },
    { key: 'drive', value: 'Frontantrieb' },
    { key: 'brakes', value: 'Scheiben VA 340 mm belüftet, HA 310 mm' },
  ];
  for (const s of golfSpecs) {
    await upsertSpec(golfGti.id, s);
  }

  // --- Elektro-Beispiel mit EV-Specs (VW ID.3) ---
  const id3 = await prisma.model.upsert({
    where: { manufacturerId_name: { manufacturerId: vw.id, name: 'ID.3' } },
    update: {},
    create: { manufacturerId: vw.id, name: 'ID.3', category: 'car' },
  });
  const id3Pro = await prisma.variant.upsert({
    where: { modelId_name: { modelId: id3.id, name: 'Pro' } },
    update: {},
    create: { modelId: id3.id, name: 'Pro', years: '2020-2026' },
  });
  const id3Specs = [
    { key: 'engine', value: 'Permanentmagnet-Synchronmotor Heck' },
    { key: 'power_hp', value: '204', unit: 'PS' },
    { key: 'torque_nm', value: '310', unit: 'Nm' },
    { key: 'fuel_type', value: 'Elektrizität' },
    { key: 'gearbox', value: '1-Gang' },
    { key: 'weight_kg', value: '1745', unit: 'kg' },
    { key: 'battery_capacity_kwh', value: '58', unit: 'kWh' },
    { key: 'range_km', value: '420', unit: 'km' },
    { key: 'charging_power_kw', value: '100', unit: 'kW' },
    { key: 'charging_time_h', value: '0.5 (10-80 % DC)', unit: 'h' },
    { key: 'top_speed_kmh', value: '160', unit: 'km/h' },
    { key: 'drive', value: 'Heckantrieb' },
  ];
  for (const s of id3Specs) {
    await upsertSpec(id3Pro.id, s);
  }

  console.log('Seed fertig: BMW R 1250 GS, Yamaha MT-07, VW Golf GTI, VW ID.3 Pro.');
}

main()
  .catch((e) => {
    console.error(e);
    process.exit(1);
  })
  .finally(() => prisma.$disconnect());
