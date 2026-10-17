import 'package:flutter_test/flutter_test.dart';
import 'package:motoroute_app/features/group_rides/group_ride_repository.dart';
import 'package:motoroute_app/features/group_rides/group_ride_providers.dart';

void main() {
  group('LiveRider.fromJson', () {
    test('parst Position, Status und Profil', () {
      final r = LiveRider.fromJson({
        'user_id': 'u1',
        'last_lat': 48.14,
        'last_lng': 11.58,
        'started': true,
        'finished': false,
        'last_beat_at': '2026-09-18T12:00:00Z',
        'username': 'maxrider',
        'display_name': 'Max',
        'avatar_url': null,
      });
      expect(r.lat, 48.14);
      expect(r.started, isTrue);
      expect(r.finished, isFalse);
      expect(r.user?.effectiveName, 'Max');
    });

    test('ohne Profil: Fallback-Name „Fahrer“ in der UI', () {
      final r = LiveRider.fromJson({
        'user_id': 'u2',
        'last_lat': 0,
        'last_lng': 0,
        'started': false,
        'finished': false,
      });
      expect(r.user, isNull);
    });
  });

  group('GroupRideState-Gruppierung (Abschnitt 18: wer ist wo?)', () {
    final riders = [
      LiveRider(userId: 'a', lat: 1, lng: 1, started: true, finished: false),
      LiveRider(userId: 'b', lat: 2, lng: 2, started: false, finished: false),
      LiveRider(userId: 'c', lat: 3, lng: 3, started: true, finished: true),
    ];

    test('unterwegs = gestartet UND nicht fertig', () {
      final state = GroupRideState(riders: riders);
      expect(state.onTheRoad.map((r) => r.userId), ['a']);
    });

    test('nicht gestartet = teilt, aber started=false', () {
      final state = GroupRideState(riders: riders);
      expect(state.notStartedYet.map((r) => r.userId), ['b']);
    });

    test('fertig = finished-Flag', () {
      final state = GroupRideState(riders: riders);
      expect(state.finishedRiders.map((r) => r.userId), ['c']);
    });

    test('isSharing ist strikt opt-in: Default-State teilt NICHT', () {
      const state = GroupRideState();
      expect(state.isSharing, isFalse);
      expect(state.riders, isEmpty);
    });
  });
}
