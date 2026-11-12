import 'package:flutter_test/flutter_test.dart';
import 'package:motoroute_app/features/garage/garage_input.dart';

/// Der Dialog soll ungueltige Eingaben abfangen, bevor sie als Serverfehler
/// zurueckkommen. `null` heisst hier "keine Angabe" - ob das erlaubt ist,
/// entscheidet der Aufrufer am Feldtext.
void main() {
  test('nimmt reine Zahlen an', () {
    expect(parseOdometerKm('12500'), 12500);
    expect(parseOdometerKm('0'), 0);
  });

  test('versteht Tausenderpunkte und Leerzeichen', () {
    expect(parseOdometerKm('12.500'), 12500);
    expect(parseOdometerKm(' 12 500 '), 12500);
    expect(parseOdometerKm('1.234.567'), 1234567);
  });

  test('leere Eingabe bedeutet keine Angabe', () {
    expect(parseOdometerKm(''), isNull);
    expect(parseOdometerKm('   '), isNull);
  });

  test('Buchstaben, Kommazahlen und negative Werte sind ungueltig', () {
    expect(parseOdometerKm('12a'), isNull);
    expect(parseOdometerKm('12,5'), isNull);
    expect(parseOdometerKm('-500'), isNull);
    expect(parseOdometerKm('abc'), isNull);
  });
}
