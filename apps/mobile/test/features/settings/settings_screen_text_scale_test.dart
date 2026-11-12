import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motoroute_app/core/theme/app_theme.dart';
import 'package:motoroute_app/features/settings/settings_screen.dart';

/// Grosse Systemschrift darf in den Einstellungen weder Titel noch
/// Steuerelemente abschneiden: jede Sektion wird aufgeklappt und der
/// Screen auf Layout-Ueberlauf geprueft - in beiden Schemata.
void main() {
  // AppTheme.* sind Getter, deshalb kein const-Map.
  final themes = <String, ThemeData>{
    'hell': AppTheme.light,
    'dunkel': AppTheme.dark,
  };

  for (final scale in <double>[1.3, 1.5]) {
    for (final entry in themes.entries) {
      testWidgets('Einstellungen ohne Ueberlauf: ${entry.key} bei ${scale}x',
          (tester) async {
        tester.view.physicalSize = const Size(1080, 7200);
        tester.view.devicePixelRatio = 3.0;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              theme: entry.value,
              home: MediaQuery(
                data: MediaQueryData(
                  size: const Size(360, 2400),
                  textScaler: TextScaler.linear(scale),
                ),
                child: const SettingsScreen(),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle(const Duration(seconds: 2));

        Future<void> openSection(String label) async {
          await tester.scrollUntilVisible(find.text(label), 300,
              scrollable: find.byType(Scrollable).first);
          await tester.ensureVisible(find.text(label));
          await tester.pumpAndSettle(const Duration(milliseconds: 200));
          await tester.tap(find.text(label));
          await tester.pumpAndSettle(const Duration(milliseconds: 300));
        }

        // Startet eingeklappt - erst aufgeklappt zeigen sich die Controls.
        await openSection('Community');
        await openSection('Sprache & Erscheinungsbild');
        await openSection('Datenschutz & Recht');

        expect(tester.takeException(), isNull,
            reason: '${entry.key} bei ${scale}x');
      });
    }
  }
}
