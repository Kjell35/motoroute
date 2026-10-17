// Smoke-Test: Die App startet ohne Crash. Der Splash wiederherstellt
// keine Sitzung (keine persistierte) und leitet zur Willkommens-/Login-
// Seite weiter; mit gespeicherter Sitzung (+ "Gerät merken") würde die
// Tab-Shell mit Begrüßung kommen. shared_preferences braucht in Unit-
// Tests Mock-Initialwerte; der Splash navigiert nach min. 900 ms.
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:motoroute_app/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('App-Start: Splash -> Willkommen/Login ohne Crash', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const MotoRouteApp());
    // Splash-Anzeige + Weiter-Navigation: Timer (900 ms) feuert, dann
    // laufen Restore/SharedPreferences als Mikrotasks, danach baut die
    // Willkommensroute (eigene Pumps, keine pumpAndSettle - der Splash-
    // Fortschrittsbalken animiert endlos und würde settle blockieren).
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 1000));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(MotoRouteApp), findsOneWidget);
    // Der Willkommens-Screen zeigt seine Begrüßungs-Headline.
    expect(find.text('Willkommen zurück!'), findsOneWidget);
  });
}
