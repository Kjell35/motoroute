import 'package:flutter_test/flutter_test.dart';
import 'package:motoroute_app/core/utils/geo.dart';
import 'package:motoroute_app/features/ride_history/presentation/ride_stats_screen.dart';
import 'package:motoroute_app/features/tour_diary/domain/tour_entities.dart';

/// Tests für die Statistik-Berechnungen (Top-Speed aus GPS-Spur,
/// höchster Punkt, Monats-Buckets) - die UI rendert nur diese Werte.

RecordedTour tour({
  required DateTime startedAt,
  List<TrackPoint> track = const [],
  double distanceMeters = 0,
  double durationSeconds = 0,
}) {
  return RecordedTour(
    title: 'Test',
    startedAt: startedAt,
    endedAt: startedAt.add(Duration(seconds: durationSeconds.round())),
    distanceMeters: distanceMeters,
    elevationGainMeters: 0,
    durationSeconds: durationSeconds,
    track: track,
  );
}

void main() {
  group('computeTopSpeedKmh', () {
        test('leitet Geschwindigkeit aus aufeinanderfolgenden GPS-Punkten ab', () {
          // 100 m in 5 s = 72 km/h.
          final t = tour(
            startedAt: DateTime(2026, 10, 1),
            track: const [
              TrackPoint(lat: 47.99, lng: 7.84, secondsSinceStart: 0),
              TrackPoint(lat: 47.9909, lng: 7.84, secondsSinceStart: 5),
            ],
          );
          final speed = computeTopSpeedKmh([t]);
          expect(speed, greaterThan(60));
          expect(speed, lessThan(85));
        });

        test('ignoriert GPS-Jitter (dt < 1 s) und Ausreißer > 400 km/h', () {
          final t = tour(
            startedAt: DateTime(2026, 10, 1),
            track: const [
              TrackPoint(lat: 47.99, lng: 7.84, secondsSinceStart: 0),
              // Gleicher Zeitpunkt: Jitter, zählt nicht.
              TrackPoint(lat: 48.99, lng: 7.84, secondsSinceStart: 0.2),
              // 1.11 Grad lat in 5 s waere > 400 km/h - verworfen.
              TrackPoint(lat: 49.10, lng: 7.84, secondsSinceStart: 5.2),
            ],
          );
          expect(computeTopSpeedKmh([t]), 0);
        });

        test('Touren ohne Track ergeben 0', () {
          expect(computeTopSpeedKmh([tour(startedAt: DateTime(2026, 1, 1))]), 0);
        });
      });

  group('computeMaxAltitudeMeters', () {
        test('nimmt das Maximum aller elevation-Werte', () {
          final t = tour(
            startedAt: DateTime(2026, 10, 1),
            track: const [
              TrackPoint(lat: 47.99, lng: 7.84, elevationMeters: 500, secondsSinceStart: 0),
              TrackPoint(lat: 48.0, lng: 7.85, elevationMeters: 1055, secondsSinceStart: 10),
              TrackPoint(lat: 48.01, lng: 7.86, elevationMeters: 700, secondsSinceStart: 20),
            ],
          );
          expect(computeMaxAltitudeMeters([t]), 1055);
        });

        test('null, wenn keine Hoehen vorhanden sind', () {
          expect(
            computeMaxAltitudeMeters([tour(startedAt: DateTime(2026, 1, 1))]),
            isNull,
          );
        });
      });

  group('computeMonthlyKm', () {
        test('bucketed Distanzen in die letzten Monate (inkl. leerer)', () {
          final tours = [
            tour(
              startedAt: DateTime(2026, 9, 15),
              distanceMeters: 640000,
            ),
            tour(
              startedAt: DateTime(2026, 10, 2),
              distanceMeters: 278500,
            ),
            // Aelter als der 6-Monats-Fenster: faellt raus.
            tour(
              startedAt: DateTime(2025, 3, 1),
              distanceMeters: 999000,
            ),
          ];
          final months = computeMonthlyKm(tours, 6);
          expect(months, hasLength(6));
          // Aeltester Monat zuerst, Letzter = aktueller Monat.
          expect(months.last.km, closeTo(278.5, 0.1));
          expect(months[months.length - 2].km, closeTo(640.0, 0.1));
        });

        test('haversineMeters bleibt als Abhaengigkeit konsistent', () {
          // Sanitaetscheck der Geo-Basis (Gleiche Konstante wie oben).
          expect(
            haversineMeters(47.99, 7.84, 47.99, 7.84),
            0,
          );
        });
      });
}
