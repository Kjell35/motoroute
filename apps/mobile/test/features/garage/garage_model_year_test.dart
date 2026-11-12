import 'package:flutter_test/flutter_test.dart';
import 'package:motoroute_app/features/garage/garage_screen.dart';

/// Das Baujahr ist optional, muss aber plausibel sein: 1900 bis zum
/// Folgejahr des aktuellen Jahres (neue Modelle erscheinen oft im Vorjahr).
void main() {
  test('nimmt plausible Jahreszahlen an', () {
    expect(parseModelYear('2019', maxYear: 2027), 2019);
    expect(parseModelYear('1900', maxYear: 2027), 1900);
    expect(parseModelYear(' 2027 ', maxYear: 2027), 2027);
  });

  test('leere Eingabe bedeutet keine Angabe', () {
    expect(parseModelYear('', maxYear: 2027), isNull);
    expect(parseModelYear('   ', maxYear: 2027), isNull);
  });

  test('zu alte und zu neue Jahrgaenge werden abgelehnt', () {
    expect(parseModelYear('1899', maxYear: 2027), isNull);
    expect(parseModelYear('1800', maxYear: 2027), isNull);
    expect(parseModelYear('2028', maxYear: 2027), isNull);
  });

  test('nicht-numerische Eingaben werden abgelehnt', () {
    expect(parseModelYear('19', maxYear: 2027), isNull);
    expect(parseModelYear('2019er', maxYear: 2027), isNull);
    expect(parseModelYear('20.19', maxYear: 2027), isNull);
    expect(parseModelYear('-2019', maxYear: 2027), isNull);
  });
}
