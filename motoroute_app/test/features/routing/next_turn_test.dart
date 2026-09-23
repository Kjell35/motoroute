import 'package:flutter_test/flutter_test.dart';

import 'package:motoroute_app/core/constants/route_enums.dart';
import 'package:motoroute_app/core/state/app_providers.dart';
import 'package:motoroute_app/features/routing/domain/route_entities.dart';

/// Gerade ~1-km-Linie (10 Punkte à ~111 m; 0,001° Breite ≈ 111,2 m).
List<List<double>> _straightGeometry() => List.generate(
      10,
      (i) => [11.0, 48.0 + i * 0.001],
    );

ComputedRoute _route(List<RouteSegment> segments) => ComputedRoute(
      id: 'r1',
      waypoints: const [
        Waypoint(lat: 48.0, lng: 11.0, label: 'Start'),
        Waypoint(lat: 48.0, lng: 11.009, label: 'Ziel'),
      ],
      preference: const RoutePreference(style: RouteStyle.fast, vehicleType: VehicleType.motorcycle),
      geometry: _straightGeometry(),
      distanceMeters: 1000,
      durationSeconds: 90,
      segments: segments,
    );

void main() {
  test('cumulativeDistances: Start 0, monoton steigend, ~1000 m gesamt', () {
    final route = _route(const []);
    final c = route.cumulativeDistances();
    expect(c.first, 0);
    expect(c.last, greaterThan(900));
    expect(c.last, lessThan(1100));
    for (var i = 1; i < c.length; i++) {
      expect(c[i], greaterThanOrEqualTo(c[i - 1]));
    }
  });

  test('nextTurn: Hinweis am Streckenanfang hat Distanz ~0', () {
    final route = _route(const [
      RouteSegment(instruction: 'Losfahren', distanceMeters: 100, durationSeconds: 10),
      RouteSegment(instruction: 'Rechts abbiegen', distanceMeters: 400, durationSeconds: 30),
      RouteSegment(instruction: 'Ziel erreicht', distanceMeters: 500, durationSeconds: 50),
    ]);
    final next = route.nextTurn(0);
    expect(next, isNotNull);
    expect(next!.text, 'Losfahren');
    expect(next.distanceMeters, 0);
  });

  test('nextTurn nach 50 m: "Rechts abbiegen" in 50 m (Manöver am Segment-Anfang)', () {
    final route = _route(const [
      RouteSegment(instruction: 'Losfahren', distanceMeters: 100, durationSeconds: 10),
      RouteSegment(instruction: 'Rechts abbiegen', distanceMeters: 400, durationSeconds: 30),
      RouteSegment(instruction: 'Ziel erreicht', distanceMeters: 500, durationSeconds: 50),
    ]);
    final next = route.nextTurn(50);
    expect(next, isNotNull);
    expect(next!.text, 'Rechts abbiegen');
    expect(next.distanceMeters, closeTo(50, 1));
  });

  test('nextTurn: 5-m-Toleranz beim Gerade-Passieren, danach nächstes Manöver', () {
    final route = _route(const [
      RouteSegment(instruction: 'Losfahren', distanceMeters: 100, durationSeconds: 10),
      RouteSegment(instruction: 'Rechts abbiegen', distanceMeters: 400, durationSeconds: 30),
      RouteSegment(instruction: 'Ziel erreicht', distanceMeters: 500, durationSeconds: 50),
    ]);
    // Genau am Manöverpunkt (100 m): Abbiegen zeigt noch mit 0 m.
    final at = route.nextTurn(103);
    expect(at!.text, 'Rechts abbiegen');
    expect(at.distanceMeters, 0);
    // 50 m dahinter: das nächste Ereignis ist die Ankunft.
    final after = route.nextTurn(150);
    expect(after!.text, 'Ziel erreicht');
    expect(after.distanceMeters, closeTo(350, 1));
  });

  test('nextTurn hinter allen Manövern liefert null', () {
    final route = _route(const [
      RouteSegment(instruction: 'Losfahren', distanceMeters: 100, durationSeconds: 10),
      RouteSegment(instruction: 'Ziel erreicht', distanceMeters: 900, durationSeconds: 80),
    ]);
    expect(route.nextTurn(950), isNull);
  });

  test('nextTurn mit leeren Segmenten liefert null (kein Crash)', () {
    final route = _route(const []);
    expect(route.nextTurn(0), isNull);
  });
}
