import 'package:flutter_test/flutter_test.dart';
import 'package:motoroute_app/features/garage/garage_input.dart';

/// Der Kilometerstand-Editor im Fahrzeug-Detail soll ungueltige Eingaben im
/// Dialog melden statt still zu schliessen, und Rueckschritt verhindern.
void main() {
  test('unlesbare Eingabe wird benannt', () {
    expect(odometerProblem(null, currentKm: 12000),
        'Kilometerstand bitte als Zahl angeben.');
  });

  test('Rueckschritt gegenueber dem bisherigen Stand wird abgelehnt', () {
    final msg = odometerProblem(11000, currentKm: 12000);
    expect(msg, contains('12000'));
    expect(msg, contains('nicht unter'));
  });

  test('gleicher oder hoeherer Stand ist in Ordnung', () {
    expect(odometerProblem(12000, currentKm: 12000), isNull);
    expect(odometerProblem(12500, currentKm: 12000), isNull);
  });

  test('absurde Werte werden abgelehnt', () {
    expect(odometerProblem(1000000, currentKm: 12000), contains('zu hoch'));
  });
}
