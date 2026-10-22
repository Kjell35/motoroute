import 'package:flutter_test/flutter_test.dart';
import 'package:motoroute_app/core/utils/geo.dart';
import 'package:motoroute_app/core/utils/route_matcher.dart';

void main() {
  group('matchRoutePosition', () {
    test('projiziert auf ein Segment statt auf den nächsten Stützpunkt', () {
      final geometry = [
        [11.0, 48.0],
        [11.01, 48.0],
      ];
      final cumulative = cumulativeDistances(geometry);
      final result = matchRoutePosition(
        lat: 48.0001,
        lng: 11.005,
        geometry: geometry,
        cumulative: cumulative,
      );

      expect(result.distanceMeters, lessThan(20));
      expect(result.progressMeters, inInclusiveRange(350, 400));
      expect(result.segmentIndex, 0);
    });

    test('wählt auf einer überlappenden Route den plausiblen Folgeabschnitt',
        () {
      // Die Route quert denselben Punkt erneut. Ohne Positionskontext würde
      // der nächste geometrische Abschnitt den Fortschritt zurückspringen.
      final geometry = [
        [11.0, 48.0],
        [11.01, 48.0],
        [11.01, 48.01],
        [11.0, 48.01],
        [11.0, 48.0],
        [11.01, 48.0],
      ];
      final cumulative = cumulativeDistances(geometry);
      final firstMatch = matchRoutePosition(
        lat: 48.00001,
        lng: 11.005,
        geometry: geometry,
        cumulative: cumulative,
      );
      final laterMatch = matchRoutePosition(
        lat: 48.00001,
        lng: 11.005,
        geometry: geometry,
        cumulative: cumulative,
        previousProgressMeters: cumulative[4] + 350,
        maxBackwardMeters: 10,
        maxForwardMeters: 100,
      );

      expect(firstMatch.progressMeters, lessThan(cumulative[1]));
      expect(laterMatch.progressMeters, greaterThan(cumulative[4]));
      expect(
          laterMatch.progressMeters, greaterThanOrEqualTo(cumulative[4] + 350));
      expect(laterMatch.segmentIndex, 4);
    });

    test('GPS-Jitter darf den Streckenfortschritt nicht rückwärts bewegen', () {
      final geometry = [
        [11.0, 48.0],
        [11.01, 48.0],
        [11.02, 48.0],
      ];
      final cumulative = cumulativeDistances(geometry);
      final previous = cumulative[1] + 100;
      final result = matchRoutePosition(
        lat: 48.0,
        lng: 11.005,
        geometry: geometry,
        cumulative: cumulative,
        previousProgressMeters: previous,
        maxBackwardMeters: 30,
      );

      expect(result.progressMeters, previous);
    });
  });

  group('RouteMatcher off-route hysteresis', () {
    final geometry = [
      [11.0, 48.0],
      [11.01, 48.0],
    ];
    final cumulative = cumulativeDistances(geometry);

    test('ein einzelner GPS-Ausreißer löst noch kein Off-Route aus', () {
      final matcher = RouteMatcher(geometry: geometry, cumulative: cumulative);

      final noisy = matcher.match(lat: 48.002, lng: 11.005);
      expect(noisy.isOffRoute, isFalse);
      expect(noisy.consecutiveOffRouteFixes, 1);

      final backOnRoute = matcher.match(lat: 48.0, lng: 11.005);
      expect(backOnRoute.isOffRoute, isFalse);
      expect(backOnRoute.consecutiveOffRouteFixes, 0);
    });

    test('zwei entfernte Fixes bestätigen Abweichung; Rückkehr löscht sie', () {
      final matcher = RouteMatcher(geometry: geometry, cumulative: cumulative);

      final first = matcher.match(lat: 48.002, lng: 11.005);
      final second = matcher.match(lat: 48.002, lng: 11.005);
      final recovered = matcher.match(lat: 48.0002, lng: 11.005);

      expect(first.isOffRoute, isFalse);
      expect(second.isOffRoute, isTrue);
      expect(recovered.isOffRoute, isFalse);
      expect(recovered.consecutiveOffRouteFixes, 0);
    });
  });
}
