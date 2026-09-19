import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:motoroute_app/features/chat/chat_providers.dart';
import 'package:motoroute_app/features/chat/data/chat_realtime.dart';
import 'package:motoroute_app/features/group_rides/group_ride_providers.dart';
import 'package:motoroute_app/features/group_rides/group_ride_repository.dart';

class _MockRepo extends Mock implements GroupRideRepository {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('RadarMember / RadarEvent (WS-Vertrag groupride.radar)', () {
    test('parst Mitgliederliste aus dem Radar-Frame', () {
      final m = RadarMember.fromJson({
        'userId': 'u1',
        'lat': 48.123,
        'lng': 11.456,
        'lastSeen': '2026-09-18T10:00:00.000Z',
      });
      expect(m.userId, 'u1');
      expect(m.lat, 48.123);
      expect(m.lng, 11.456);

      final e = RadarEvent(routeId: 'r1', members: [m]);
      expect(e.isLeave, isFalse);
    });

    test('Leave-Event: leftUserId gesetzt, isLeave true', () {
      const e = RadarEvent(routeId: 'r1', members: [], leftUserId: 'u2');
      expect(e.isLeave, isTrue);
      expect(e.leftUserId, 'u2');
    });
  });

  group('GroupRideController._applyRadarEvent (über Provider-Pfad)', () {
    late ProviderContainer container;
    late _MockRepo repo;
    late ChatRealtimeClient realtime;

    setUp(() {
      repo = _MockRepo();
      realtime = ChatRealtimeClient(wsBaseUrl: 'ws://localhost:0');
      when(() => repo.liveState(any(), any())).thenAnswer((_) async => []);
      container = ProviderContainer(overrides: [
        groupRideRepositoryProvider.overrideWithValue(repo),
        chatRealtimeProvider.overrideWithValue(realtime),
        chatSessionTokenProvider.overrideWith((ref) => 'token-1'),
      ]);
      addTearDown(container.dispose);
    });

    test('Radar-Update mit bekannten Nutzern: Position frisch, Profil bleibt', () async {
      // Initialer REST-Stand (Profil von u1 bekannt).
      when(() => repo.liveState(any(), any())).thenAnswer((_) async => [
            LiveRider(
              userId: 'u1',
              lat: 48.0,
              lng: 11.0,
              started: true,
              finished: false,
              lastBeatAt: '2026-09-18T09:00:00Z',
              user: null,
            ),
          ]);
      final controller = container.read(groupRideProvider('r1').notifier);
      await controller.load();

      // Radar-Event: u1 ist inzwischen weiter gefahren.
      realtime.testInjectRadarEvent(RadarEvent(
        routeId: 'r1',
        members: [
          const RadarMember(userId: 'u1', lat: 48.5, lng: 11.5, lastSeen: '2026-09-18T10:00:00Z'),
        ],
      ));
      await Future<void>.delayed(Duration.zero);

      final state = container.read(groupRideProvider('r1'));
      expect(state.riders.single.userId, 'u1');
      expect(state.riders.single.lat, 48.5);
      expect(state.riders.single.started, isTrue, reason: 'Status-Felder bleiben aus dem REST-Stand');
    });

    test('Leave-Event entfernt den Fahrer aus der Liste', () async {
      when(() => repo.liveState(any(), any())).thenAnswer((_) async => [
            LiveRider(userId: 'u1', lat: 48.0, lng: 11.0, started: true, finished: false),
            LiveRider(userId: 'u2', lat: 48.1, lng: 11.1, started: true, finished: false),
          ]);
      final controller = container.read(groupRideProvider('r1').notifier);
      await controller.load();

      realtime.testInjectRadarEvent(const RadarEvent(routeId: 'r1', members: [], leftUserId: 'u2'));
      await Future<void>.delayed(Duration.zero);

      final state = container.read(groupRideProvider('r1'));
      expect(state.riders.map((r) => r.userId), ['u1']);
    });
  });
}
