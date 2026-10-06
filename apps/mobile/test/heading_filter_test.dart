import 'package:flutter_test/flutter_test.dart';

import 'package:motoroute/domain/services/heading_filter.dart';

void main() {
  group('HeadingFilter', () {
    test('gibt ersten Wert unverändert als Startwert', () {
      final HeadingFilter f = HeadingFilter();
      expect(f.push(90), 90);
    });

    test('Nord-West-Übergang (350→10) mittelt über 0, nicht über 180', () {
      final HeadingFilter f = HeadingFilter(minDeltaDegrees: 0);
      f.push(350);
      f.push(355);
      final double result = f.push(5)!;
      // 356.66 ist das gleiche wie -3.33, was nah an 0 ist.
      // Wir prüfen den Abstand zirkulär.
      final double diff = (result - 0).abs() % 360;
      final double angularDist = diff > 180 ? 360 - diff : diff;
      expect(angularDist, lessThan(5.0));
    });

    test('Hysterese: kleine Schwankungen ändern den Heading nicht', () {
      final HeadingFilter f = HeadingFilter(
        windowSize: 5,
        minDeltaDegrees: 12,
      );
      f.push(90);
      f.push(96);
      f.push(85);
      expect(f.smoothedHeading, closeTo(90, 3));
    });

    test('große Wendung wird übernommen', () {
      final HeadingFilter f = HeadingFilter(windowSize: 3);
      f.push(90);
      f.push(180);
      f.push(180);
      f.push(180);
      expect(f.smoothedHeading, closeTo(180, 1));
    });

    test('null-Fix verändert nichts', () {
      final HeadingFilter f = HeadingFilter();
      f.push(45);
      expect(f.push(null), closeTo(45, 0.001));
    });

    test('reset löscht Fenster', () {
      final HeadingFilter f = HeadingFilter();
      f.push(180);
      f.reset();
      expect(f.smoothedHeading, isNull);
      expect(f.push(10), 10);
    });
  });
}
