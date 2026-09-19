import 'package:flutter_test/flutter_test.dart';
import 'package:motoroute_app/core/utils/geo.dart';
import 'package:motoroute_app/features/navigation_session/navigation_providers.dart'
    show kOffRouteThresholdMeters;

void main() {
  group('haversineMeters', () {
    test('Distanz München -> Garmisch liegt bei ca. 82 km (Luftlinie)', () {
      // Referenzwert gegen Karten-Entfernungsmesser verifiziert; Toleranz
      // bewusst groß genug für Kugel-Näherung, klein genug um groben
      // Unsinn zu fangen.
      final d = haversineMeters(48.1351, 11.5820, 47.4210, 11.8757);
      expect(d, inInclusiveRange(78000, 86000));
    });

    test('identische Punkte haben Distanz 0', () {
      expect(haversineMeters(48.0, 11.0, 48.0, 11.0), 0);
    });
  });

  group('distanceToSegmentMeters', () {
    test('Punkt genau auf dem Segment -> Distanz ~0', () {
      final d = distanceToSegmentMeters(11.5, 48.1, 11.0, 48.0, 12.0, 48.2);
      expect(d, lessThan(1500));
    });

    test('Punkt 1 Grad vom Segment entfernt -> ca. 111 km', () {
      // Senkrecht über dem Segmentmittelpunkt (südlich).
      final d = distanceToSegmentMeters(11.5, 47.1, 11.0, 48.0, 12.0, 48.2);
      expect(d, greaterThan(100000));
    });
  });

  group('distanceToRouteMeters', () {
    test('GPS-Punkt nahe der Route -> unter jeder praktischen Schwelle', () {
      final geometry = [
        [11.0, 48.0],
        [12.0, 48.0],
      ];
      // 0.0003 deg Breite = ca. 33 m - innerhalb der 60-m-Schwelle.
      final d = distanceToRouteMeters(48.0003, 11.5, geometry);
      expect(d, lessThan(kOffRouteThresholdMeters));
    });

    test('GPS-Punkt weit weg von der Route -> Off-Route-Schwelle überschritten', () {
      final geometry = [
        [11.0, 48.0],
        [12.0, 48.0],
      ];
      final d = distanceToRouteMeters(47.5, 11.5, geometry);
      expect(d, greaterThan(kOffRouteThresholdMeters));
    });

    test('leere Geometrie -> unendlich (kein falsches On-Route)', () {
      expect(distanceToRouteMeters(48.0, 11.0, []), double.infinity);
    });
  });

  group('cumulativeDistances', () {
    test('startet bei 0 und akkumuliert', () {
      final cumulative = cumulativeDistances([
        [11.0, 48.0],
        [11.0, 48.01],
        [11.0, 48.02],
      ]);
      expect(cumulative[0], 0);
      expect(cumulative[2], greaterThan(cumulative[1]));
      // 2 Grad Breite = ca. 2222 m
      expect(cumulative[2], inInclusiveRange(2000, 2500));
    });
  });
}
