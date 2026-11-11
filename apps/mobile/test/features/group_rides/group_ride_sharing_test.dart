import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:mocktail/mocktail.dart';

import 'package:motoroute_app/features/chat/chat_providers.dart';
import 'package:motoroute_app/features/chat/data/chat_realtime.dart';
import 'package:motoroute_app/features/chat/data/chat_repository.dart'
    show ChatUser;
import 'package:motoroute_app/features/group_rides/group_ride_providers.dart';
import 'package:motoroute_app/features/group_rides/group_ride_repository.dart';
import 'package:motoroute_app/features/map/data/location_repository.dart';
import 'package:motoroute_app/features/settings/energy_saver.dart'
    show LocationAccuracyPreset, LocationTuning;

class _MockRepo extends Mock implements GroupRideRepository {}

class _MockLocation extends Mock implements LocationRepository {}

Position _position(double lat, double lng) => Position(
      latitude: lat,
      longitude: lng,
      timestamp: DateTime.utc(2026),
      accuracy: 5,
      altitude: 500,
      altitudeAccuracy: 1,
      heading: 0,
      headingAccuracy: 1,
      speed: 10,
      speedAccuracy: 1,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    registerFallbackValue(const LocationTuning(
      accuracy: LocationAccuracyPreset.low,
      distanceFilterMeters: 30,
    ));
  });

  late ProviderContainer container;
  late _MockRepo repo;
  late _MockLocation location;
  late StreamController<Position> positions;

  ProviderSubscription<GroupRideState> listenRoute(String routeId) {
    final sub = container.listen(groupRideProvider(routeId), (_, __) {});
    addTearDown(sub.close);
    return sub;
  }

  setUp(() {
    repo = _MockRepo();
    location = _MockLocation();
    positions = StreamController<Position>.broadcast();

    when(() => repo.liveState(any(), any())).thenAnswer((_) async => []);
    when(() => repo.startSharing(any(), any(),
        lat: any(named: 'lat'), lng: any(named: 'lng'))).thenAnswer((_) async {});
    when(() => repo.stopSharing(any(), any())).thenAnswer((_) async {});
    when(() => repo.heartbeat(any(), any(),
            lat: any(named: 'lat'), lng: any(named: 'lng')))
        .thenThrow(Exception('kein Netz'));
    when(() => location.ensurePermission()).thenAnswer((_) async => true);
    when(() => location.getCurrentPosition())
        .thenAnswer((_) async => _position(48, 11));
    when(() => location.watchPosition(
          tuning: any(named: 'tuning'),
          backgroundNavigation: any(named: 'backgroundNavigation'),
          notificationTitle: any(named: 'notificationTitle'),
          notificationText: any(named: 'notificationText'),
        )).thenAnswer((_) => positions.stream);

    container = ProviderContainer(overrides: [
      groupRideRepositoryProvider.overrideWithValue(repo),
      chatRealtimeProvider
          .overrideWithValue(ChatRealtimeClient(wsBaseUrl: 'ws://localhost:0')),
      chatSessionTokenProvider.overrideWith((ref) => 'token-1'),
      chatMeProvider.overrideWith((ref) async => const ChatUser(id: 'u1')),
      locationRepositoryProvider.overrideWithValue(location),
    ]);
    addTearDown(() {
      container.dispose();
      positions.close();
    });
  });

  test('drei fehlgeschlagene Beats beenden die Freigabe sichtbar und raeumen auf',
      () async {
    listenRoute('r1');
    final c = container.read(groupRideProvider('r1').notifier);
    await c.enableSharing();
    expect(container.read(groupRideProvider('r1')).isSharing, isTrue);

    for (var i = 0; i < 3; i++) {
      positions.add(_position(48 + i * 0.01, 11));
      await pumpEventQueue();
    }

    final state = container.read(groupRideProvider('r1'));
    expect(state.isSharing, isFalse,
        reason: 'ein toter Stream darf nicht als "teilt" angezeigt werden');
    expect(state.error, contains('unterbrochen'));
    verify(() => repo.stopSharing('token-1', 'r1')).called(1);

    await c.refresh(silent: true);
    expect(container.read(groupRideProvider('r1')).error, contains('unterbrochen'),
        reason: 'der 20-s-Refresh darf den Hinweis nicht wegwischen');
  });

  test('Neustart nach Funkloch beginnt wieder bei null Fehlschlaegen', () async {
    listenRoute('r1');
    final c = container.read(groupRideProvider('r1').notifier);
    await c.enableSharing();
    for (var i = 0; i < 3; i++) {
      positions.add(_position(48, 11));
      await pumpEventQueue();
    }
    expect(container.read(groupRideProvider('r1')).isSharing, isFalse);

    await c.enableSharing();
    expect(container.read(groupRideProvider('r1')).isSharing, isTrue);
    positions.add(_position(48, 11));
    await pumpEventQueue();
    expect(container.read(groupRideProvider('r1')).isSharing, isTrue,
        reason: 'ein einzelner Fehlschlag nach Neustart darf nicht sofort abreissen');
  });

  test('doppeltes Aktivieren startet keinen zweiten Upload', () async {
    listenRoute('r1');
    final c = container.read(groupRideProvider('r1').notifier);
    await c.enableSharing();
    await c.enableSharing();
    verify(() => repo.startSharing('token-1', 'r1',
        lat: any(named: 'lat'), lng: any(named: 'lng'))).called(1);
    verify(() => location.watchPosition(
          tuning: any(named: 'tuning'),
          backgroundNavigation: true,
          notificationTitle: 'MotoRoute Gruppenfahrt',
          notificationText: 'Dein Standort wird mit der Gruppe geteilt.',
        )).called(1);
  });

  test('Freigabe laeuft weiter, wenn der Screen geschlossen wird', () async {
    when(() => repo.heartbeat(any(), any(),
            lat: any(named: 'lat'), lng: any(named: 'lng')))
        .thenAnswer((_) async {});
    final screen = container.listen(groupRideProvider('r1'), (_, __) {});
    await container.read(groupRideProvider('r1').notifier).enableSharing();

    screen.close();
    await pumpEventQueue();
    expect(container.exists(groupRideProvider('r1')), isFalse,
        reason: 'Timer und WebSocket-Abos muessen mit dem Screen enden');

    positions.add(_position(48, 11));
    await pumpEventQueue();
    verify(() => repo.heartbeat('token-1', 'r1',
        lat: any(named: 'lat'), lng: any(named: 'lng'))).called(1);

    final again = listenRoute('r1');
    await pumpEventQueue();
    expect(container.read(groupRideProvider('r1')).isSharing, isTrue,
        reason: 'beim Wiedereintritt muss die laufende Freigabe sichtbar sein');
    again.close();
  });

  test('Start auf anderer Route beendet die erste Freigabe', () async {
    listenRoute('r1');
    await container.read(groupRideProvider('r1').notifier).enableSharing();

    listenRoute('r2');
    await container.read(groupRideProvider('r2').notifier).enableSharing();

    verify(() => repo.stopSharing('token-1', 'r1')).called(1);
    verify(() => repo.startSharing('token-1', 'r2',
        lat: any(named: 'lat'), lng: any(named: 'lng'))).called(1);
    expect(container.read(groupRideProvider('r1')).isSharing, isFalse);
    expect(container.read(groupRideProvider('r2')).isSharing, isTrue);
  });

  test('verwaiste Server-Freigabe wird erkannt und kann geloescht werden',
      () async {
    when(() => repo.liveState(any(), any())).thenAnswer((_) async => [
          const LiveRider(
              userId: 'u1', lat: 48, lng: 11, started: true, finished: false),
        ]);
    listenRoute('r1');
    final c = container.read(groupRideProvider('r1').notifier);
    await c.load();

    var state = container.read(groupRideProvider('r1'));
    expect(state.isSharing, isTrue);
    expect(state.isStaleSharing, isTrue,
        reason: 'Serverzeile ohne lokalen Stream ist eine verwaiste Freigabe');

    when(() => repo.liveState(any(), any())).thenAnswer((_) async => []);
    await c.disableSharing();
    verify(() => repo.stopSharing('token-1', 'r1')).called(1);

    state = container.read(groupRideProvider('r1'));
    expect(state.isSharing, isFalse);
    expect(state.isStaleSharing, isFalse);
  });

  test('Neu starten loescht die alte Zeile und startet den Stream', () async {
    when(() => repo.liveState(any(), any())).thenAnswer((_) async => [
          const LiveRider(
              userId: 'u1', lat: 48, lng: 11, started: true, finished: false),
        ]);
    listenRoute('r1');
    final c = container.read(groupRideProvider('r1').notifier);
    await c.load();
    expect(container.read(groupRideProvider('r1')).isStaleSharing, isTrue);

    when(() => repo.liveState(any(), any())).thenAnswer((_) async => []);
    await c.restartSharing();

    verify(() => repo.stopSharing('token-1', 'r1')).called(1);
    verify(() => repo.startSharing('token-1', 'r1',
        lat: any(named: 'lat'), lng: any(named: 'lng'))).called(1);
    final state = container.read(groupRideProvider('r1'));
    expect(state.isSharing, isTrue);
    expect(state.isStaleSharing, isFalse);
  });
}
