import 'package:flutter_test/flutter_test.dart';
import 'package:motoroute_app/core/utils/formatters.dart';

void main() {
  group('formatDistanceMeters', () {
    test('unter 1 km in Metern', () {
      expect(formatDistanceMeters(850), '850 m');
    });

    test('km mit einer Nachkommastelle unter 10 km', () {
      expect(formatDistanceMeters(2350), '2,4 km');
    });

    test('ab 10 km ohne Nachkommastelle', () {
      expect(formatDistanceMeters(95400), '95 km');
    });

    test('Meilen-Umrechnung', () {
      expect(formatDistanceMeters(16093.44, unit: DistanceUnit.miles), '10 mi');
    });
  });

  group('formatDurationSeconds', () {
    test('deutlich unter einer Minute', () {
      expect(formatDurationSeconds(30), '<1 min');
    });

    test('59 Sekunden runden auf 1 Minute', () {
      expect(formatDurationSeconds(59), '1 min');
    });

    test('nur Minuten', () {
      expect(formatDurationSeconds(1500), '25 min');
    });

    test('Stunden + Minuten mit padded Minuten', () {
      expect(formatDurationSeconds(5400), '1 h 30 min');
    });
  });

  group('formatEta', () {
    test('rechnet Sekunden in Uhrzeit um', () {
      final now = DateTime(2026, 9, 17, 14, 0);
      expect(formatEta(now, 1800), '14:30');
    });

    test('rundet auf Minuten und padet zweistellig', () {
      final now = DateTime(2026, 9, 17, 9, 5);
      expect(formatEta(now, 3000), '09:55');
    });
  });

  group('formatSpeedMps', () {
    test('m/s -> km/h', () {
      expect(formatSpeedMps(18.06), '65 km/h');
    });

    test('m/s -> mph', () {
      expect(formatSpeedMps(26.82, unit: DistanceUnit.miles), '60 mph');
    });
  });
}
