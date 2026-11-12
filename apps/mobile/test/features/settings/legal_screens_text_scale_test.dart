import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motoroute_app/core/theme/app_theme.dart';
import 'package:motoroute_app/features/settings/legal_screens.dart';

/// Grosse Systemschrift darf auf den Rechtstext-Seiten nichts abschneiden:
/// die Karten wachsen mit, der AppBar-Titel muss in eine Zeile passen.
void main() {
  const screens = <String, Widget>{
    'Datenschutz': PrivacyScreen(),
    'Impressum': ImprintScreen(),
    'Über MotoRoute': AboutScreen(),
  };

  for (final scale in <double>[1.3, 1.5]) {
    testWidgets('Rechtstexte ohne Ueberlauf bei ${scale}x Systemschrift',
        (tester) async {
      for (final entry in screens.entries) {
        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              theme: AppTheme.light,
              home: MediaQuery(
                data: MediaQueryData(
                  size: const Size(360, 800),
                  textScaler: TextScaler.linear(scale),
                ),
                child: entry.value,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull,
            reason: '${entry.key} bei ${scale}x');
        final title = tester.renderObject<RenderParagraph>(
            find.text(entry.key));
        expect(title.size.height, lessThanOrEqualTo(kToolbarHeight),
            reason: 'Titel von ${entry.key} bricht bei ${scale}x um');
      }
    });
  }
}
