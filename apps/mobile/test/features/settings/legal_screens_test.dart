import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motoroute_app/core/theme/app_colors.dart';
import 'package:motoroute_app/core/theme/app_theme.dart';
import 'package:motoroute_app/features/settings/legal_screens.dart';

void main() {
  testWidgets('Rechtstexte folgen dem hellen Schema', (tester) async {
    Future<void> pumpScreen(Widget screen, {bool withProviders = false}) async {
      final app = MaterialApp(theme: AppTheme.light, home: screen);
      await tester.pumpWidget(
        withProviders ? ProviderScope(child: app) : app,
      );
      await tester.pumpAndSettle();
    }

    // Mit den fest verdrahteten Dark-Tokens blieben die Seiten im hellen
    // Schema dunkel; die Titel haetten die helle Textfarbe geerbt.
    await pumpScreen(const PrivacyScreen());
    expect(tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor,
        AppColors.bgBaseLight);
    final caption = tester.widget<Text>(find.text(
        'Stand: September 2026 - gilt für die private Testphase (v0.3.0).'));
    expect(caption.style?.color, AppColors.textSecondaryLight);

    await pumpScreen(const ImprintScreen());
    expect(tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor,
        AppColors.bgBaseLight);

    await pumpScreen(const AboutScreen(), withProviders: true);
    expect(tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor,
        AppColors.bgBaseLight);
  });
}
