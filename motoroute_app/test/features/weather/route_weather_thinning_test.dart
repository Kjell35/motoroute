// Audit-Fix 03.10.2026: Die App sandte die volle OSRM-Geometrie (Lang-
// strecken: 10.000+ Punkte) an den Wetter-Radar. Der Backend-DTO-Cap
// (50.000) und Payload-Größe sprechen für eine Verdichtung vor dem
// Senden; der Service sampelt ohnehin nur wenige Punkte ab.
import 'package:flutter_test/flutter_test.dart';
import 'package:motoroute_app/features/weather/route_weather_providers.dart';

void main() {
  group('thinGeometryForWeather', () {
    test('lässt kurze Routen unverändert durch', () {
      final geometry = [
        [6.96, 50.94],
        [6.97, 50.95],
        [6.98, 50.96],
      ];
      final thinned = thinGeometryForWeather(geometry, 2000);
      expect(identical(thinned, geometry), isTrue);
      expect(thinned, hasLength(3));
    });

    test('verdichtet eine Langstrecke auf maximal maxPoints', () {
      final geometry = List<List<double>>.generate(
        17000,
        (i) => [6.9 + i * 0.001, 50.9 + i * 0.0005],
      );
      final thinned = thinGeometryForWeather(geometry, 2000);
      expect(thinned.length, lessThanOrEqualTo(2000));
      expect(thinned.length, greaterThanOrEqualTo(1999));
      // Jeder Punkt bleibt eine gültige [lng, lat]-Stelle der Originalroute.
      for (final p in thinned) {
        expect(p, hasLength(2));
      }
    });

    test('behält Start und Ziel immer', () {
      final geometry = List<List<double>>.generate(
        5000,
        (i) => [i.toDouble(), i.toDouble()],
      );
      final thinned = thinGeometryForWeather(geometry, 500);
      expect(thinned.first, geometry.first);
      expect(thinned.last, geometry.last);
    });

    test('behält die Punkte-Reihenfolge', () {
      final geometry = List<List<double>>.generate(
        3000,
        (i) => [i.toDouble(), 0],
      );
      final thinned = thinGeometryForWeather(geometry, 300);
      for (var i = 1; i < thinned.length; i++) {
        expect(thinned[i][0], greaterThan(thinned[i - 1][0]));
      }
    });

    test('keine Duplikate (jeder Punkt höchstens einmal)', () {
      final geometry = List<List<double>>.generate(
        9001,
        (i) => [i.toDouble(), 0],
      );
      final thinned = thinGeometryForWeather(geometry, 1000);
      final seen = <double>{};
      for (final p in thinned) {
        expect(seen.add(p[0]), isTrue, reason: 'Duplikat bei lng=${p[0]}');
      }
    });

    test('knappe Grenze: genau maxPoints Punkte bleiben unverändert', () {
      final geometry = List<List<double>>.generate(
        2000,
        (i) => [i.toDouble(), 0],
      );
      final thinned = thinGeometryForWeather(geometry, 2000);
      expect(identical(thinned, geometry), isTrue);
    });
  });
}
