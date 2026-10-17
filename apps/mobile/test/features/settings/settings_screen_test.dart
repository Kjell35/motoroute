import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motoroute_app/features/settings/settings_screen.dart';

void main() {
  testWidgets('Settings rendert ohne Diagnose (entfernt) und mit Profil-Header',
      (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: SettingsScreen()),
      ),
    );
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // Diagnose ist bewusst raus (Release für normale Nutzer).
    expect(find.text('Diagnose'), findsNothing);
    expect(find.text('Tests starten'), findsNothing);

    // Calimoto-Look: Profil-Header mit Avatar + Sektionstitel in
    // Normalschreibung (nicht mehr Caps-Labels).
    expect(find.byType(CircleAvatar), findsOneWidget);
    expect(find.text('Navigation'), findsOneWidget);
  });
}
