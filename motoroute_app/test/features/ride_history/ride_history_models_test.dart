import 'package:flutter_test/flutter_test.dart';

import 'package:motoroute_app/features/ride_history/ride_history_repository.dart';

void main() {
  test('PublicProfileHistory parst die Backend-Antwort (öffentlich)', () {
    final j = {
      'profile': {
        'userId': 'u-2',
        'displayName': 'Maxi',
        'username': 'maxi',
        'avatarUrl': null,
        'isPrivate': false,
      },
      'history': {
        'rideCount': 1,
        'totalKm': 120.0,
        'totalHours': 2.0,
        'totalElevationGain': 900.0,
        'regions': ['Bayern'],
        'rides': [
          {
            'externalId': 't-9',
            'title': 'Kurventour',
            'startedAt': '2026-09-01T08:00:00.000Z',
            'distanceMeters': 120000,
            'durationSeconds': 7200,
            'elevationGainMeters': 900,
            'region': 'Bayern',
            'description': 'Schöne Runde',
            'track': [
              {'lat': 47.5, 'lng': 10.7},
              {'lat': 47.9, 'lng': 10.9},
            ],
            'pois': [
              {'label': 'Tanke', 'lat': 47.51, 'lng': 10.71},
            ],
            'startLabel': 'Startort',
            'endLabel': 'Zielort',
            'start': null,
            'end': null,
          },
        ],
        'places': [
          {
            'externalId': 'poi-1',
            'category': 'fuel',
            'label': 'Tankstelle',
            'lat': 49.95,
            'lng': 11.57,
            'visitCount': 3,
            'lastVisitedAt': '2026-09-20T10:00:00.000Z',
          },
        ],
      },
    };

    final h = PublicProfileHistory.fromJson(j);
    expect(h.isPrivate, isFalse);
    expect(h.rideCount, 1);
    expect(h.rides, hasLength(1));
    expect(h.rides.first.track, hasLength(2));
    expect(h.rides.first.start, isNull, reason: 'hide_start_end: keine Koordinaten');
    expect(h.rides.first.startLabel, 'Startort');
    expect(h.places.first.visitCount, 3);
    expect(h.regions, ['Bayern']);
    expect(h.totalKm, closeTo(120, 0.01));
  });

  test('PublicProfileHistory: privates Profil -> keine Historie-Daten nötig', () {
    final h = PublicProfileHistory.fromJson({
      'profile': {'userId': 'u-3', 'isPrivate': true},
      'history': {
        'rideCount': 0,
        'totalKm': 0,
        'totalHours': 0,
        'totalElevationGain': 0,
        'regions': [],
        'rides': [],
        'places': [],
      },
    });
    expect(h.isPrivate, isTrue);
    expect(h.rides, isEmpty);
    expect(h.places, isEmpty);
  });

  test('MyRideHistory Defaults sind sicher (privat)', () {
    final s = MyRideHistory.fromJson({
      'settings': <String, dynamic>{},
    });
    expect(s.authPrivacy, 'private');
    expect(s.shareRides, isFalse);
    expect(s.sharePlaces, isFalse);
    expect(s.hideStartEnd, isTrue);
    expect(s.rideHistoryEnabled, isTrue);
  });
}
