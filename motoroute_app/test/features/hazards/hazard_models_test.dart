import 'package:flutter_test/flutter_test.dart';
import 'package:motoroute_app/features/hazards/hazard_repository.dart';

void main() {
  group('HazardType', () {
    test('parst Backend-Enum-Werte exakt', () {
      expect(HazardType.from('rollsplitt'), HazardType.rollsplitt);
      expect(HazardType.from('sperrung'), HazardType.sperrung);
      expect(HazardType.from('baustelle'), HazardType.baustelle);
      expect(HazardType.from('oelspur'), HazardType.oelspur);
    });

    test('unbekannter Wert fällt defensiv auf baustelle zurück', () {
      expect(HazardType.from(null), HazardType.baustelle);
      expect(HazardType.from('blitzertyp'), HazardType.baustelle);
    });

    test('apiValue ist der SQL-Enum-Name', () {
      for (final t in HazardType.values) {
        expect(t.apiValue, t.name);
      }
    });
  });

  group('HazardReport.fromJson', () {
    test('parst alle Felder der nearby-Antwort', () {
      final now = DateTime.now().toUtc();
      final r = HazardReport.fromJson({
        'id': 'h-1',
        'report_type': 'oelspur',
        'description': 'Kurvenausgang, rutschig',
        'latitude': 48.12,
        'longitude': 11.58,
        'upvotes': 7,
        'created_at': now.subtract(const Duration(hours: 1)).toIso8601String(),
        'expires_at': now.add(const Duration(hours: 12)).toIso8601String(),
        'distance_m': 420,
      });
      expect(r.id, 'h-1');
      expect(r.type, HazardType.oelspur);
      expect(r.description, 'Kurvenausgang, rutschig');
      expect(r.upvotes, 7);
      expect(r.distanceM, 420);
      expect(r.isExpired, isFalse);
    });

    test('fehlende Felder: defensiv ohne Crash (upvotes >= 1)', () {
      final r = HazardReport.fromJson({
        'id': 'h-2',
        'report_type': 'sperrung',
        'latitude': 48,
        'longitude': 11,
      });
      expect(r.upvotes, 1);
      expect(r.description, isEmpty);
      expect(r.distanceM, 0);
    });

    test('isExpired erkennt abgelaufene Meldungen', () {
      final r = HazardReport.fromJson({
        'id': 'h-3',
        'report_type': 'baustelle',
        'latitude': 48,
        'longitude': 11,
        'expires_at': '2020-01-01T00:00:00.000Z',
      });
      expect(r.isExpired, isTrue);
    });
  });
}
