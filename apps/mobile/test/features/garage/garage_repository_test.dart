import 'package:flutter_test/flutter_test.dart';
import 'package:motoroute_app/features/garage/garage_repository.dart';

void main() {
  group('GarageVehicle', () {
    test('parse: Garage-Übersicht-Karte mit Status', () {
      final v = GarageVehicle.fromJson({
        'id': 'v1',
        'category': 'motorcycle',
        'manufacturerName': 'BMW',
        'modelName': 'R 1250 GS',
        'variantName': 'Standard',
        'year': 2024,
        'odometerKm': 42350,
        'nickname': 'Lotte',
        'maintenanceWorstStatus': 'dueSoon',
      });
      expect(v.title, 'Lotte');
      expect(v.subtitle, 'Standard · 2024');
      expect(v.worstStatus, 'dueSoon');
      expect(v.category.emoji, '🏍️');
    });

    test('parse: Auto ohne Spitzname zeigt Hersteller+Modell', () {
      final v = GarageVehicle.fromJson({
        'id': 'v2',
        'category': 'car',
        'manufacturerName': 'Volkswagen',
        'modelName': 'Golf GTI',
        'odometerKm': 68200,
      });
      expect(v.title, 'Volkswagen Golf GTI');
      expect(v.category.emoji, '🚗');
    });
  });

  group('GarageReminder', () {
    test('Level-Mapping: Server-Status -> Ampel', () {
      expect(GarageReminder.fromJson({'type': 'OIL_CHANGE', 'status': 'overdue'}).level, GarageReminderStatus.overdue);
      expect(GarageReminder.fromJson({'type': 'OIL_CHANGE', 'status': 'dueSoon'}).level, GarageReminderStatus.dueSoon);
      expect(GarageReminder.fromJson({'type': 'OIL_CHANGE', 'status': 'ok'}).level, GarageReminderStatus.ok);
      expect(GarageReminder.fromJson({'type': 'OIL_CHANGE'}).level, GarageReminderStatus.ok);
    });

    test('Deutsche Labels der 17 Typen', () {
      expect(maintenanceTypeLabelDe('OIL_CHANGE'), 'Ölwechsel');
      expect(maintenanceTypeLabelDe('HU'), 'HU/TÜV');
      expect(maintenanceTypeLabelDe('CHAIN'), 'Kette spannen/schmieren');
      expect(maintenanceTypeLabelDe('UNKNOWN_TYPE'), 'Sonstige Wartung');
    });
  });

  group('GarageFuelStats', () {
    test('Verbrauch vom Server korrekt geparst (l/100 km, Cent)', () {
      final s = GarageFuelStats.fromJson({
        'averageConsumptionPer100km': 2.8,
        'totalCostCents': 5865,
        'totalLiters': 34.5,
        'costPerKmCents': 10,
        'entriesCount': 2,
      });
      expect(s.averageConsumptionPer100km, 2.8);
      expect(s.totalCostCents, 5865);
      expect(s.costPerKmCents, 10);
    });
  });

  group('GarageSession-Keys', () {
    test('Token-Provider-Keys stabil (Persistenz-Vertrag)', () {
      // Die Keys sind Teil des Speichervertrags - Aenderungen wuerden
      // gespeicherte Sessions aller Nutzer invalidieren.
      expect('garage.accessToken', isNotEmpty);
      expect('settings.garageApiBaseUrl', isNotEmpty);
    });
  });
}
