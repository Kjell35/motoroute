import 'package:flutter_test/flutter_test.dart';

import 'package:motoroute/domain/value_objects/app_location.dart';

void main() {
  group('AppLocation', () {
    const AppLocation munich = AppLocation(
      latitude: 48.1375,
      longitude: 11.5755,
    );
    const AppLocation nuremberg = AppLocation(
      latitude: 49.4520,
      longitude: 11.0768,
    );

    test('Haversine: München–Nürnberg ≈ 150 km', () {
      final double d = munich.distanceToMeters(nuremberg);
      expect(d, inInclusiveRange(145000, 155000));
    });

    test('identische Positionen → 0 m', () {
      expect(munich.distanceToMeters(munich), 0);
    });

    test('flache Projektion: 1 Breitengrad ≈ 111,3 km', () {
      const AppLocation a = AppLocation(latitude: 48, longitude: 11);
      const AppLocation b = AppLocation(latitude: 49, longitude: 11);
      final double d = a.distanceToMeters(b);
      expect(d, inInclusiveRange(110000, 112500));
    });

    test('squaredPlanar: Schwellwert-Vergleich (70 m) funktioniert', () {
      // ~0.00063° Länge entspricht am Äquator ~70 m
      const AppLocation a = AppLocation(latitude: 0, longitude: 10.0);
      const AppLocation b = AppLocation(latitude: 0, longitude: 10.00063);
      final double sq = a.squaredPlanarDistanceMeters(b);
      expect(sq, closeTo(70 * 70, 400));
    });

    test('copyWith überschreibt nur gesetzte Felder', () {
      const AppLocation base = AppLocation(latitude: 1, longitude: 2);
      final AppLocation withHeading =
          base.copyWith(latitude: 5, headingDegrees: 270);
      expect(withHeading.latitude, 5);
      expect(withHeading.longitude, 2);
      expect(withHeading.headingDegrees, 270);
    });
  });
}
