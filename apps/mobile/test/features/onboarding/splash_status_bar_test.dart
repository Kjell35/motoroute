import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:motoroute_app/core/theme/app_theme.dart';
import 'package:motoroute_app/features/auth/auth_providers.dart';
import 'package:motoroute_app/features/onboarding/splash_screen.dart';

/// Haengender Restore: der Splash bleibt lange genug sichtbar, um die
/// Statusleisten-Annotation zu pruefen.
class _HangingRestoreAuthController extends AuthController {
  @override
  Future<void> restore() => Completer<void>().future;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Splash fordert im hellen Schema helle Statusleisten-Symbole an',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(ProviderScope(
      overrides: [
        authControllerProvider.overrideWith(
          (ref) => _HangingRestoreAuthController(),
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        routes: {
          '/': (_) => const SplashScreen(),
          '/welcome': (_) => const Scaffold(body: Text('Login Screen')),
          '/onboarding': (_) => const Scaffold(body: Text('Onboarding')),
          '/home': (_) => const Scaffold(body: Text('Home')),
        },
      ),
    ));
    await tester.pump();

    final region = tester.widget<AnnotatedRegion<SystemUiOverlayStyle>>(
      find
          .descendant(
            of: find.byType(SplashScreen),
            matching: find.byType(AnnotatedRegion<SystemUiOverlayStyle>),
          )
          .first,
    );
    // Der Splash bleibt dunkel, also helle Symbole - unabhaengig vom Schema.
    expect(region.value, AppTheme.statusOverlayDark);
    expect(region.value.statusBarIconBrightness, Brightness.light);

    // Restore-Timeout (4 s) + Mindestdauer (900 ms) ablaufen lassen, damit
    // kein Timer offen bleibt.
    await tester.pump(const Duration(seconds: 6));
    await tester.pump();
    expect(find.text('Login Screen'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
