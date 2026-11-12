import 'package:flutter_test/flutter_test.dart';
import 'package:motoroute_app/features/garage/garage_input.dart';

void main() {
  group('parseGarageDate', () {
    test('akzeptiert ISO und deutsches Format', () {
      expect(parseGarageDate('2026-11-12'), DateTime(2026, 11, 12));
      expect(parseGarageDate('12.11.2026'), DateTime(2026, 11, 12));
      expect(parseGarageDate(' 1.2.2026 '), DateTime(2026, 2, 1));
    });

    test('lehnt nicht existierende Tage ab statt sie zu verschieben', () {
      expect(parseGarageDate('2026-02-31'), isNull);
      expect(parseGarageDate('31.02.2026'), isNull);
      expect(parseGarageDate('2026-13-01'), isNull);
    });

    test('lehnt fremde Formate und leere Eingaben ab', () {
      expect(parseGarageDate(''), isNull);
      expect(parseGarageDate('12/11/2026'), isNull);
      expect(parseGarageDate('2026-11'), isNull);
      expect(parseGarageDate('gestern'), isNull);
    });
  });

  test('isoDate liefert immer JJJJ-MM-TT', () {
    expect(isoDate(DateTime(2026, 1, 5)), '2026-01-05');
    expect(isoDate(DateTime(2026, 11, 12)), '2026-11-12');
  });

  group('parseDecimal', () {
    test('versteht Komma und Punkt', () {
      expect(parseDecimal('24,80'), 24.8);
      expect(parseDecimal('24.80'), 24.8);
      expect(parseDecimal('5'), 5.0);
      // Leerzeichen als Tausender-Trenner sind erlaubt.
      expect(parseDecimal(' 1 234,5 '), 1234.5);
    });

    test('lehnt Unlesbares und Negative ab', () {
      expect(parseDecimal(''), isNull);
      expect(parseDecimal('abc'), isNull);
      expect(parseDecimal('-3'), isNull);
      expect(parseDecimal('1.234,56'), isNull);
    });
  });
}
