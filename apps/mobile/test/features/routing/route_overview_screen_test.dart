import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:motoroute_app/core/constants/route_enums.dart';
import 'package:motoroute_app/core/state/app_providers.dart';
import 'package:motoroute_app/features/routing/domain/route_entities.dart';
import 'package:motoroute_app/features/routing/route_overview_screen.dart';
import 'package:motoroute_app/features/tour_diary/data/tour_repository.dart';
import 'package:motoroute_app/features/tour_diary/tour_diary_providers.dart';

/// Gleiches DDL wie tour_repository.dart, in-memory über sqflite_ffi.
Future<Database> _openInMemoryDb() async {
  final db = await databaseFactoryFfi.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(singleInstance: false, version: 1),
  );
  await db.execute('''
    create table if not exists tours (
      id integer primary key autoincrement,
      title text not null,
      started_at text not null,
      ended_at text not null,
      distance_meters real not null,
      elevation_gain_meters real not null,
      duration_seconds real not null,
      track_json text not null,
      pois_json text not null
    )
  ''');
  return db;
}

ComputedRoute _route({required bool isRoundTrip, DateTime? plannedStart}) =>
    ComputedRoute(
      id: 'route-1',
      waypoints: const [
        Waypoint(lat: 47.561, lng: 10.746, label: 'Start'),
        Waypoint(lat: 47.6, lng: 10.8, label: 'Ziel'),
      ],
      preference: const RoutePreference(
        style: RouteStyle.fast,
        vehicleType: VehicleType.motorcycle,
      ),
      geometry: const [
        [10.746, 47.561],
        [10.8, 47.6],
      ],
      distanceMeters: 12000,
      durationSeconds: 1800,
      segments: const [],
      isRoundTrip: isRoundTrip,
      plannedStart: plannedStart,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<(ProviderContainer, Database)> pumpOverview(
    WidgetTester tester, {
    required ComputedRoute route,
  }) async {
    late Database db;
    late ProviderContainer container;
    await tester.runAsync(() async {
      db = await _openInMemoryDb();
    });
    container = ProviderContainer(overrides: [
      tourDatabaseProvider.overrideWithValue(TourDatabase(existing: db)),
    ]);
    addTearDown(container.dispose);
    addTearDown(() => db.close());
    container.read(activeRouteProvider.notifier).state = route;

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: RouteOverviewScreen()),
    ));
    // Kartenstil wird asynchron aus dem Asset geladen.
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
    return (container, db);
  }

  testWidgets('zeigt "Als Tour speichern" nicht für normale Routen',
      (tester) async {
    await pumpOverview(tester, route: _route(isRoundTrip: false));

    expect(find.text('Als Tour speichern'), findsNothing);
  });

  testWidgets(
      'zeigt "Als Tour speichern" für geplante Rundtour und speichert sie',
      (tester) async {
    final (_, db) = await pumpOverview(
      tester,
      route: _route(isRoundTrip: true),
    );

    final button = find.text('Als Tour speichern');
    expect(button, findsOneWidget);

    await tester.tap(button);
    // Die Speicherung läuft echtes I/O (SQLite) - bis zum Snackbar pollen.
    for (var i = 0;
        i < 50 && find.text('Tour gespeichert').evaluate().isEmpty;
        i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }

    expect(find.text('Tour gespeichert'), findsOneWidget);

    final rows = await tester.runAsync(() => db.query(TourDatabase.table));
    expect(rows, hasLength(1));
    expect(rows!.single['title'], 'Geplante Rundtour');
    expect(rows.single['distance_meters'], 12000);
    expect(rows.single['duration_seconds'], 1800);
  });

  testWidgets('übernimmt die gewählte Startzeit als Tourbeginn',
      (tester) async {
    final plannedStart = DateTime(2026, 11, 1, 8, 30);
    final (_, db) = await pumpOverview(
      tester,
      route: _route(isRoundTrip: true, plannedStart: plannedStart),
    );

    await tester.tap(find.text('Als Tour speichern'));
    for (var i = 0;
        i < 50 && find.text('Tour gespeichert').evaluate().isEmpty;
        i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }

    expect(find.text('Tour gespeichert'), findsOneWidget);

    final rows = await tester.runAsync(() => db.query(TourDatabase.table));
    expect(rows, hasLength(1));
    expect(
      DateTime.parse(rows!.single['started_at'] as String),
      plannedStart,
    );
  });
}
