// App smoke tests: splash navigation, resilience to auth restore failures,
// and regressions in route navigation state.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:motoroute_app/core/state/app_providers.dart';
import 'package:motoroute_app/features/poi/biker_poi_sync.dart';
import 'package:motoroute_app/features/auth/auth_providers.dart';
import 'package:motoroute_app/features/badges/presentation/badges_screen.dart';
import 'package:motoroute_app/features/map/data/location_repository.dart';
import 'package:motoroute_app/features/onboarding/splash_screen.dart';
import 'package:motoroute_app/features/shell/home_shell.dart';
import 'package:motoroute_app/features/waypoints/waypoint_management_screen.dart';
import 'package:motoroute_app/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _HangingRestoreAuthController extends AuthController {
  @override
  Future<void> restore() => Completer<void>().future;
}

class _FailingRestoreAuthController extends AuthController {
  @override
  Future<void> restore() async => throw StateError('restore failed');
}

class _EmptyBikerPoiSyncController extends BikerPoiSyncController {
  _EmptyBikerPoiSyncController() : super(Dio());

  @override
  Future<void> restoreCache() async {}

  @override
  Future<void> sync({double? lat, double? lng, double? radiusKm}) async {}
}

class _NoPermissionLocationRepository extends LocationRepository {
  @override
  Future<bool> ensurePermission() async => false;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('App-Start: Splash -> Willkommen/Login ohne Crash',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const MotoRouteApp());
    // Auth restore is deliberately capped at four seconds in the splash.
    // Let that timeout/navigation complete instead of assuming local storage
    // and the secure-store plugin always return immediately in a widget test.
    await tester.pump(const Duration(seconds: 5));
    await tester.pump();

    expect(find.byType(MotoRouteApp), findsOneWidget);
    expect(find.text('Willkommen zurück!'), findsOneWidget);
  });

  testWidgets('Mehr-Menü bietet direkten Einstieg zum Trophäenschrank',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(ProviderScope(
      overrides: [
        bikerPoiSyncProvider
            .overrideWith((ref) => _EmptyBikerPoiSyncController()),
      ],
      child: MaterialApp(
        home: const HomeShell(),
        routes: {'/badges': (_) => const BadgesScreen()},
      ),
    ));
    // Kein pumpAndSettle: Die Karte enthält laufende Animationen und
    // Hintergrund-Syncs, die nicht zum Settlen kommen müssen.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.text('Mehr').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Pass-Knacker'), findsOneWidget);
    await tester.tap(find.text('Pass-Knacker'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Bitte melde dich an, um Badges zu sammeln.'),
        findsOneWidget);
  });

  testWidgets('Wegpunktmodus bleibt beim Wechsel zur Karte aktiv',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(ProviderScope(
      overrides: [
        locationRepositoryProvider
            .overrideWithValue(_NoPermissionLocationRepository()),
      ],
      child: MaterialApp(
        home: const WaypointManagementScreen(),
        routes: {
          '/map': (_) => Consumer(
                builder: (context, ref, _) => Text(
                  'Kartentap-Modus: ${ref.watch(mapWaypointTapModeProvider)}',
                ),
              ),
        },
      ),
    ));

    expect(find.text('Auf Karte antippen'), findsOneWidget);
    await tester.tap(find.text('Auf Karte antippen'));
    await tester.pumpAndSettle();

    expect(find.text('Kartentap-Modus: true'), findsOneWidget);
  });

  for (final (description, controller) in <(String, AuthController)>[
    ('hängender Restore', _HangingRestoreAuthController()),
    ('fehlerhafter Restore', _FailingRestoreAuthController()),
  ]) {
    testWidgets('Splash verlässt den Splash bei $description', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(ProviderScope(
        overrides: [
          authControllerProvider.overrideWith((ref) => controller),
        ],
        child: MaterialApp(
          routes: {
            '/': (_) => const SplashScreen(),
            '/welcome': (_) => const Scaffold(body: Text('Login Screen')),
            '/onboarding': (_) => const Scaffold(body: Text('Onboarding')),
            '/home': (_) => const Scaffold(body: Text('Home')),
          },
        ),
      ));
      await tester.pump(const Duration(seconds: 5));
      await tester.pump();
      expect(find.text('Login Screen'), findsOneWidget);
    });
  }
}
