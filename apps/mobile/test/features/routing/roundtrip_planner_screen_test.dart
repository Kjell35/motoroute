import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:motoroute_app/core/i18n/i18n.dart';
import 'package:motoroute_app/features/routing/presentation/roundtrip_planner_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
      'Startzeit zeigt "Jetzt" ohne Auswahl und das gewählte Datum mit Uhrzeit danach',
      (tester) async {
    await tester.pumpWidget(const ProviderScope(
      child: MaterialApp(home: RoundTripPlannerScreen()),
    ));
    await tester.pump();

    expect(find.text('Jetzt'), findsOneWidget);

    await tester.tap(find.text('Startzeit'));
    await tester.pumpAndSettle();

    // Datumsauswahl: heutiges Datum bestätigen, dann Uhrzeit bestätigen.
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect(find.text('Jetzt'), findsNothing);
    expect(
      find.textContaining(RegExp(r'^\d{2}\.\d{2}\. \d{2}:\d{2}$')),
      findsOneWidget,
    );
  });

  testWidgets('Start time row shows "Start time" and "Now" in English',
      (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        i18nProvider.overrideWithValue(const I18n(AppLanguage.en)),
      ],
      child: const MaterialApp(home: RoundTripPlannerScreen()),
    ));
    await tester.pump();

    expect(find.text('Start time'), findsOneWidget);
    expect(find.text('Now'), findsOneWidget);
    expect(find.text('Startzeit'), findsNothing);
    expect(find.text('Jetzt'), findsNothing);

    await tester.tap(find.text('Start time'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect(find.text('Now'), findsNothing);
    expect(
      find.textContaining(RegExp(r'^\d{2}\.\d{2}\. \d{2}:\d{2}$')),
      findsOneWidget,
    );
  });
}
