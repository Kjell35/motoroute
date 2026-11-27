import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motoroute_app/core/state/app_providers.dart';
import 'package:motoroute_app/features/pairing/data/pairing_repository.dart';
import 'package:motoroute_app/features/pairing/data/pairing_session.dart';
import 'package:motoroute_app/features/pairing/presentation/computer_planning_sheet.dart';
import 'package:motoroute_app/features/routing/domain/route_entities.dart';

/// Fake ohne Netz: liefert sofort einen Start-Token und einen fertigen Plan.
class _FakeRepository extends PairingRepository {
  _FakeRepository(this.points) : super(apiBaseUrl: 'https://example.org');

  final List<PairingPoint> points;

  @override
  Future<PairingStart> start() async => const PairingStart(
        token: 'ABC234',
        planUrl: 'https://example.org/plan/ABC234',
        expiresInSeconds: 7200,
      );

  @override
  Future<List<PairingPoint>?> fetchPlan(String token, {String? baseUrl}) async =>
      points;
}

const _incoming = <PairingPoint>[
  PairingPoint(label: 'Eibsee', lat: 47.4211, lng: 10.9848),
  PairingPoint(label: 'Gipfel', lat: 47.49, lng: 11.095),
  PairingPoint(label: 'Hütte', lat: 47.5, lng: 11.1),
];

const _existing = <Waypoint>[
  Waypoint(lat: 48.1, lng: 11.5, label: 'Alt 1'),
  Waypoint(lat: 48.2, lng: 11.6, label: 'Alt 2'),
];

void main() {
  late List<String> pushed;

  Future<void> pumpApp(
    WidgetTester tester,
    ProviderContainer container, {
    required List<Waypoint> initial,
  }) async {
    container.read(waypointListProvider.notifier).state = initial;

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          routes: {
            '/waypoints': (context) {
              pushed.add('/waypoints');
              return const Scaffold(body: Text('Wegpunktliste'));
            },
          },
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => showModalBottomSheet<void>(
                    context: context,
                    isScrollControlled: true,
                    builder: (_) =>
                        ComputerPlanningSheet(repository: _FakeRepository(_incoming)),
                  ),
                  child: const Text('planen'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<ProviderContainer> openSheet(
    WidgetTester tester, {
    required List<Waypoint> initial,
  }) async {
    pushed = <String>[];
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await pumpApp(tester, container, initial: initial);
    await tester.tap(find.text('planen'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    return container;
  }

  /// Ein Poll-Zyklus des Dialogs (4 s) plus Zeit für die asynchrone Antwort.
  Future<void> runPoll(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 4));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('bestehende Route: Nachfrage, "Behalten" ändert nichts',
      (tester) async {
    final container = await openSheet(tester, initial: _existing);

    await runPoll(tester);
    expect(find.text('Bestehende Route ersetzen?'), findsOneWidget);
    expect(find.textContaining('2 Wegpunkte'), findsOneWidget);

    await tester.tap(find.text('Behalten'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(container.read(waypointListProvider), _existing);
    expect(find.textContaining('bleibt unverändert'), findsOneWidget);
    expect(pushed, isEmpty);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('bestehende Route: "Ersetzen" übernimmt und schließt den Dialog',
      (tester) async {
    final container = await openSheet(tester, initial: _existing);

    await runPoll(tester);
    await tester.tap(find.text('Ersetzen'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final updated = container.read(waypointListProvider);
    expect(updated.map((w) => w.label).toList(), ['Eibsee', 'Gipfel', 'Hütte']);
    expect(updated.first.lat, 47.4211);
    // Der Dialog ist zu, und es wurde KEIN zweiter Wegpunkt-Screen gepusht.
    expect(find.text('Plan abrufen'), findsNothing);
    expect(pushed, isEmpty);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Token überlebt das Schließen - später „Plan abrufen"',
      (tester) async {
    // Groessere Testflaeche: im 800x600-Standard liegt der Schliessen-Knopf
    // des Sheets unterhalb des sichtbaren Bereichs.
    tester.view.physicalSize = const Size(1000, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    pushed = <String>[];
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await pumpApp(tester, container, initial: const []);

    await tester.tap(find.text('planen'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('Token: ABC234'), findsOneWidget);

    await tester.tap(find.text('Schließen'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Plan abrufen'), findsNothing);

    final session = container.read(pairingSessionProvider);
    expect(session.isActive, isTrue);
    expect(session.start?.token, 'ABC234');
    expect(session.start?.planUrl, contains('/plan/ABC234'));

    // Dialog erneut öffnen: derselbe Code, dazu der Hinweis.
    await tester.tap(find.text('planen'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('Token: ABC234'), findsOneWidget);
    expect(find.textContaining('wiederhergestellt'), findsOneWidget);

    // Erst jetzt am Rechner gespeicherter Plan -> per Knopf holen.
    await tester.tap(find.text('Plan abrufen'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(container.read(waypointListProvider).map((w) => w.label).toList(),
        ['Eibsee', 'Gipfel', 'Hütte']);
    expect(pushed, isEmpty);
    // Eingelöst: kein zweiter Abruf desselben Plans.
    expect(container.read(pairingSessionProvider).start, isNull);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('leere Liste: keine Rückfrage, direkt übernehmen', (tester) async {
    final container = await openSheet(tester, initial: const []);

    await runPoll(tester);

    expect(find.text('Bestehende Route ersetzen?'), findsNothing);
    final updated = container.read(waypointListProvider);
    expect(updated.map((w) => w.label).toList(), ['Eibsee', 'Gipfel', 'Hütte']);
    expect(find.text('Plan abrufen'), findsNothing);
    expect(pushed, isEmpty);

    await tester.pumpWidget(const SizedBox());
  });
}
