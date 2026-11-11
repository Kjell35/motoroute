import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:motoroute_app/core/constants/route_enums.dart';
import 'package:motoroute_app/core/state/app_providers.dart';
import 'package:motoroute_app/features/navigation_session/navigation_providers.dart';
import 'package:motoroute_app/features/navigation_session/navigation_session_store.dart';
import 'package:motoroute_app/features/routing/domain/route_entities.dart';

const _preference = RoutePreference(
  style: RouteStyle.curvy,
  vehicleType: VehicleType.motorcycle,
  avoid: {AvoidOption.highway},
);

ComputedRoute _route() => const ComputedRoute(
      id: 'route-42',
      waypoints: [
        Waypoint(lat: 48.0, lng: 11.0, label: 'Start'),
        Waypoint(lat: 48.2, lng: 11.4, label: 'Ziel'),
      ],
      preference: _preference,
      geometry: [
        [11.0, 48.0],
        [11.2, 48.1],
        [11.4, 48.2],
      ],
      distanceMeters: 2000,
      durationSeconds: 240,
      segments: [
        RouteSegment(
            instruction: 'Links abbiegen auf B12',
            distanceMeters: 900,
            durationSeconds: 100),
        RouteSegment(
            instruction: 'Ziel erreicht',
            distanceMeters: 1100,
            durationSeconds: 140),
      ],
      elevationGainMeters: 320,
    );

NavigationSessionSnapshot _snapshot({double traveled = 1200}) =>
    NavigationSessionSnapshot(
      route: _route(),
      traveledMeters: traveled,
      savedAt: DateTime(2026, 11, 6, 12),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferences prefs;
  late DateTime now;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    now = DateTime(2026, 11, 6, 12);
  });

  NavigationSessionStore store({DateTime Function()? clock}) =>
      NavigationSessionStore(
        prefs: Future.value(prefs),
        clock: clock ?? () => now,
      );

  group('NavigationSessionSnapshot', () {
    test('Round-Trip erhaelt Route, Praeferenz, Segmente und Fortschritt',
        () async {
      await store().save(_snapshot());

      final loaded = await store().load();
      expect(loaded, isNotNull);
      final route = loaded!.route;

      expect(loaded.traveledMeters, 1200);
      expect(loaded.remainingMeters, 800);
      expect(loaded.progressFraction, closeTo(0.6, 0.0001));
      expect(route.id, 'route-42');
      expect(route.waypoints, hasLength(2));
      expect(route.waypoints.last.label, 'Ziel');
      expect(route.preference.style, RouteStyle.curvy);
      expect(route.preference.vehicleType, VehicleType.motorcycle);
      expect(route.preference.avoid, {AvoidOption.highway});
      expect(route.geometry, [
        [11.0, 48.0],
        [11.2, 48.1],
        [11.4, 48.2],
      ]);
      expect(route.distanceMeters, 2000);
      expect(route.segments, hasLength(2));
      expect(route.segments.first.instruction, 'Links abbiegen auf B12');
      expect(route.elevationGainMeters, 320);
    });

    test('Fortschritt wird auf die Routenlaenge begrenzt', () {
      final snapshot = NavigationSessionSnapshot(
        route: _route(),
        traveledMeters: 9000,
        savedAt: DateTime(2026, 11, 6, 12),
      );
      expect(snapshot.remainingMeters, 0);
      expect(snapshot.progressFraction, 1.0);
    });
  });

  group('NavigationSessionStore', () {
    test('beschaedigte Sitzung wird verworfen und geloescht', () async {
      await prefs.setString(
          NavigationSessionStore.storageKey, '{"version":1,"route":');

      expect(await store().load(), isNull);
      expect(prefs.getString(NavigationSessionStore.storageKey), isNull);
    });

    test('unbekannte Formatversion wird verworfen', () async {
      final json = _snapshot().toJson()..['version'] = 99;
      await prefs.setString(
          NavigationSessionStore.storageKey, jsonEncode(json));

      expect(await store().load(), isNull);
      expect(prefs.getString(NavigationSessionStore.storageKey), isNull);
    });

    test('unbekannter Fahrstil macht die Sitzung ungueltig', () async {
      final json = _snapshot().toJson();
      (json['route'] as Map)['preference'] = {
        'style': 'WARP_SPEED',
        'vehicle': 'MOTORCYCLE',
        'avoid': <String>[],
      };
      await prefs.setString(
          NavigationSessionStore.storageKey, jsonEncode(json));

      expect(await store().load(), isNull);
    });

    test('zu alte Sitzung wird nicht fortgesetzt', () async {
      await store().save(_snapshot());
      final later = now.add(const Duration(hours: 13));

      expect(await store(clock: () => later).load(), isNull);
      expect(prefs.getString(NavigationSessionStore.storageKey), isNull);
    });

    test('Sitzung aus der Zukunft wird verworfen', () async {
      await store().save(_snapshot());
      final earlier = now.subtract(const Duration(hours: 5));

      expect(await store(clock: () => earlier).load(), isNull);
    });

    test('Drossel schreibt erst nach 250 m oder zwei Minuten', () async {
      final sessionStore = store();
      expect(sessionStore.shouldSave(0), isTrue);

      await sessionStore.save(_snapshot(traveled: 0));
      expect(sessionStore.shouldSave(120), isFalse, reason: 'zu wenig Strecke');

      expect(sessionStore.shouldSave(260), isTrue, reason: '250 m erreicht');

      await sessionStore.save(_snapshot(traveled: 260));
      expect(sessionStore.shouldSave(280), isFalse);

      now = now.add(const Duration(minutes: 2));
      expect(sessionStore.shouldSave(280), isTrue,
          reason: 'Zeitanker greift im Stau ohne Bewegung');
    });

    test('saveIfDue schreibt nicht bei jedem GPS-Fix', () async {
      final sessionStore = store();
      await sessionStore.save(_snapshot(traveled: 0));

      expect(await sessionStore.saveIfDue(_snapshot(traveled: 10)), isFalse);
      expect(await sessionStore.saveIfDue(_snapshot(traveled: 400)), isTrue);
    });

    test('clear loescht die Sitzung', () async {
      final sessionStore = store();
      await sessionStore.save(_snapshot());
      expect(await store().load(), isNotNull);

      await sessionStore.clear();
      expect(await store().load(), isNull);
      expect(prefs.getString(NavigationSessionStore.storageKey), isNull);
    });
  });

  group('Reroute-Backoff', () {
    test('verdoppelt sich und deckelt bei zwei Minuten', () {
      expect(rerouteBackoffFor(0), const Duration(seconds: 15));
      expect(rerouteBackoffFor(1), const Duration(seconds: 30));
      expect(rerouteBackoffFor(2), const Duration(minutes: 1));
      expect(rerouteBackoffFor(3), const Duration(minutes: 2));
      expect(rerouteBackoffFor(4), const Duration(minutes: 2));
      expect(rerouteBackoffFor(10), const Duration(minutes: 2));
    });
  });
}
