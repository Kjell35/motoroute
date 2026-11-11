import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:motoroute_app/core/constants/route_enums.dart';
import 'package:motoroute_app/core/state/app_providers.dart';
import 'package:motoroute_app/features/map/data/location_repository.dart';
import 'package:motoroute_app/features/map/data/map_style.dart';
import 'package:motoroute_app/features/map/presentation/map_screen.dart';
import 'package:motoroute_app/features/navigation_session/navigation_providers.dart';
import 'package:motoroute_app/features/navigation_session/navigation_session_store.dart';
import 'package:motoroute_app/features/routing/domain/route_entities.dart';

class _DeniedLocation extends LocationRepository {
  @override
  Future<bool> ensurePermission() async => false;
}

const _route = ComputedRoute(
  id: 'stored-route',
  waypoints: [
    Waypoint(lat: 48.0, lng: 11.0, label: 'Start'),
    Waypoint(lat: 48.3, lng: 11.5, label: 'Ziel'),
  ],
  preference: RoutePreference(
    style: RouteStyle.curvy,
    vehicleType: VehicleType.motorcycle,
  ),
  geometry: [
    [11.0, 48.0],
    [11.25, 48.15],
    [11.5, 48.3],
  ],
  distanceMeters: 5000,
  durationSeconds: 600,
  segments: [
    RouteSegment(
        instruction: 'Links abbiegen',
        distanceMeters: 2500,
        durationSeconds: 300),
  ],
);

NavigationSessionSnapshot _snapshot() => NavigationSessionSnapshot(
      route: _route,
      traveledMeters: 1500,
      savedAt: DateTime.now(),
    );

/// Legt die Sitzung genau so ab, wie sie nach einem Prozess-Tod in den
/// Einstellungen steht - der Test benutzt damit den echten Store-Pfad
/// (JSON in shared_preferences) statt eines Doppels.
///
/// `setMockInitialValues` verwirft die zwischengespeicherte Instanz, jeder
/// Test startet also mit frischem Speicher.
void seed() {
  SharedPreferences.setMockInitialValues({
    NavigationSessionStore.storageKey: jsonEncode(_snapshot().toJson()),
  });
}

/// Banner-Box, damit Klicks nicht versehentlich andere Bedienelemente der
/// Karte treffen (die Karte hat eigene Schließen-Symbole).
Finder _banner() => find
    .ancestor(
      of: find.textContaining('Navigation fortsetzen'),
      matching: find.byType(Container),
    )
    .first;

Widget _app() => ProviderScope(
      overrides: [
        locationRepositoryProvider.overrideWithValue(_DeniedLocation()),
        // Fester Stil statt Asset-Laden: der Screen soll den Stack sofort
        // bauen und nicht am Asset-Timing des Test-Bundles hängen.
        mapStyleLoaderProvider.overrideWithValue((_) async => emptyMapStyle),
      ],
      child: MaterialApp(
        home: const MapScreen(),
        routes: {
          '/navigation': (_) =>
              const Scaffold(body: Text('Navigationsscreen')),
        },
      ),
    );

ProviderContainer _container(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(MapScreen)));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Karte liest die gespeicherte Sitzung und setzt sie fort',
      (tester) async {
    seed();

    await tester.pumpWidget(_app());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.textContaining('Navigation fortsetzen'), findsOneWidget);
    expect(find.textContaining('noch 3,5 km'), findsOneWidget);

    await tester.tap(find.text('Fortsetzen'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final container = _container(tester);
    final state = container.read(navigationControllerProvider);
    expect(state.isNavigating, isTrue);
    expect(state.route?.id, 'stored-route');
    expect(state.traveledMeters, 1500,
        reason: 'Fortschritt muss aus der gespeicherten Sitzung kommen');
    expect(state.remainingMeters, 3500);
    expect(find.text('Navigationsscreen'), findsOneWidget);
    expect(find.textContaining('Navigation fortsetzen'), findsNothing);

    // Wieder über den echten Store gelesen: die fortgesetzte Sitzung ist
    // erneut in den Einstellungen abgelegt.
    final restored = await container.read(navigationSessionStoreProvider).load();
    expect(restored?.route.id, 'stored-route');
    expect(restored?.traveledMeters, 1500);

    // Aufräumen, damit kein unawaited Schreibvorgang in den nächsten Test
    // läuft.
    await container.read(navigationSessionStoreProvider).clear();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Schließen löscht die gespeicherte Sitzung aus den Einstellungen',
      (tester) async {
    seed();

    await tester.pumpWidget(_app());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.textContaining('Navigation fortsetzen'), findsOneWidget);

    await tester.tap(
        find.descendant(of: _banner(), matching: find.byIcon(Icons.close)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.textContaining('Navigation fortsetzen'), findsNothing);
    expect(_container(tester).read(navigationControllerProvider).isNavigating,
        isFalse);

    // Beides über den echten Pfad: der Store findet nichts mehr, und der
    // Schlüssel ist wirklich aus den Einstellungen verschwunden.
    final container = _container(tester);
    expect(await container.read(navigationSessionStoreProvider).load(), isNull);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(NavigationSessionStore.storageKey), isNull);

    await tester.pumpWidget(const SizedBox());
  });
}
