import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motoroute_app/features/poi/biker_poi_sync.dart';
import 'package:motoroute_app/features/shell/home_shell.dart';
import 'package:motoroute_app/features/tour_diary/domain/tour_entities.dart';
import 'package:motoroute_app/features/tour_diary/presentation/tour_diary_screen.dart';
import 'package:motoroute_app/features/tour_diary/tour_diary_providers.dart';
import 'package:motoroute_app/features/waypoints/waypoint_management_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _EmptyTourDiaryController extends TourDiaryController {
  _EmptyTourDiaryController(super.ref) {
    state = const TourDiaryState();
  }

  @override
  Future<void> load() async {}
}

class _PopulatedTourDiaryController extends TourDiaryController {
  _PopulatedTourDiaryController(super.ref) {
    state = TourDiaryState(
      tours: [
        RecordedTour(
          id: 1,
          title: 'Morgenrunde',
          startedAt: DateTime(2025, 5, 1, 9),
          endedAt: DateTime(2025, 5, 1, 10),
          distanceMeters: 42000,
          elevationGainMeters: 360,
          durationSeconds: 3600,
        ),
      ],
    );
  }

  @override
  Future<void> load() async {}
}

class _EmptyBikerPoiSyncController extends BikerPoiSyncController {
  _EmptyBikerPoiSyncController() : super(Dio());

  @override
  Future<void> restoreCache() async {}

  @override
  Future<void> sync({double? lat, double? lng, double? radiusKm}) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('Touren-Tab öffnet das Tagebuch direkt', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        bikerPoiSyncProvider
            .overrideWith((ref) => _EmptyBikerPoiSyncController()),
        tourDiaryProvider.overrideWith(_EmptyTourDiaryController.new),
      ],
      child: const MaterialApp(home: HomeShell()),
    ));
    await tester.pump();

    await tester.tap(find.text('Touren'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(TourDiaryScreen), findsOneWidget);
    expect(find.text('Ziel suchen'), findsOneWidget);
    expect(find.text('Rundtour planen'), findsOneWidget);
    expect(find.text('GPX importieren'), findsOneWidget);
  });

  testWidgets('Tour-Einstiege bleiben bei vorhandenen Touren erreichbar',
      (tester) async {
    final requestedRoutes = <String?>[];
    await tester.pumpWidget(ProviderScope(
      overrides: [
        bikerPoiSyncProvider
            .overrideWith((ref) => _EmptyBikerPoiSyncController()),
        tourDiaryProvider.overrideWith(_PopulatedTourDiaryController.new),
      ],
      child: MaterialApp(
        home: const HomeShell(initialTab: 3),
        onGenerateRoute: (settings) {
          requestedRoutes.add(settings.name);
          return MaterialPageRoute<void>(
            builder: (_) => Scaffold(
              body: Text(switch (settings.name) {
                '/search' => 'Zielsuche geöffnet',
                '/roundtrip' => 'Rundtour geöffnet',
                '/tour-import' => 'GPX-Import geöffnet',
                _ => 'Unbekannte Route: ${settings.name}',
              }),
            ),
          );
        },
      ),
    ));
    await tester.pump();

    expect(find.text('Morgenrunde'), findsOneWidget);
    expect(find.text('Ziel suchen'), findsOneWidget);
    expect(find.text('Rundtour planen'), findsOneWidget);
    expect(find.text('GPX importieren'), findsOneWidget);

    await tester.tap(find.text('Ziel suchen'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(requestedRoutes, contains('/search'));
    await tester.binding.handlePopRoute();
    await tester.pump(const Duration(milliseconds: 400));

    await tester.tap(find.text('Rundtour planen'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(requestedRoutes, contains('/roundtrip'));
    await tester.binding.handlePopRoute();
    await tester.pump(const Duration(milliseconds: 400));

    await tester.tap(find.text('GPX importieren'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(requestedRoutes, contains('/tour-import'));
  });

  testWidgets('Routenplanung bleibt über den Wegpunkt-Deep-Link erreichbar',
      (tester) async {
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).pushNamed('/waypoints'),
            child: const Text('Planen'),
          ),
        ),
        routes: {
          '/waypoints': (_) => const WaypointManagementScreen(),
        },
      ),
    ));

    await tester.tap(find.text('Planen'));
    await tester.pumpAndSettle();

    expect(find.text('Routenplanung'), findsOneWidget);
    expect(find.text('Auf Karte antippen'), findsOneWidget);
    expect(find.text('Noch keine Wegpunkte - suche ein Ziel, um zu starten.'),
        findsOneWidget);
  });
}
