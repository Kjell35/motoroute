// Smoke-Test: Die App startet ohne Crash und navigiert sauber vom
// Splash ins Onboarding. shared_preferences braucht in Unit-Tests
// Mock-Initialwerte (eingebaut im Plugin); der Splash-Weiter-Timer
// feuert nach 900 ms - danach gepumpt wird, damit keine hängenden
// Timer die Test-Invarianten verletzen.
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:motoroute_app/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('App-Start: Splash -> Onboarding ohne Crash', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const MotoRouteApp());
    // Splash-Anzeige + Weiter-Navigation (Timer 900 ms).
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 1000));
    expect(find.byType(MotoRouteApp), findsOneWidget);
  });
}
