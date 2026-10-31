import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:motoroute_app/features/tour_diary/data/tour_repository.dart';
import 'package:motoroute_app/features/tour_diary/domain/tour_entities.dart';

void main() {
  setUpAll(() {
    // Linux/Windows-Test-Umgebung: sqflite braucht die FFI-Implementierung.
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  Future<TourDatabase> freshDb() async {
    final db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      // singleInstance:false - sonst teilen sich die Tests EINE :memory:-DB
      // und das delete in Test 2 sieht die Zeilen aus Test 1.
      options: OpenDatabaseOptions(
        singleInstance: false,
        version: 1,
        onCreate: (d, v) async {
          await d.execute('''
            create table tours (
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
        },
      ),
    );
    return TourDatabase(existing: db);
  }

  RecordedTour sampleTour(String title) => RecordedTour(
        title: title,
        startedAt: DateTime.utc(2026, 9, 21, 10),
        endedAt: DateTime.utc(2026, 9, 21, 12),
        distanceMeters: 123456.7,
        elevationGainMeters: 890.1,
        durationSeconds: 7200,
        track: const [
          TrackPoint(lat: 47.561, lng: 10.746, elevationMeters: 1100, secondsSinceStart: 0),
          TrackPoint(lat: 47.5625, lng: 10.7485, elevationMeters: 1120, secondsSinceStart: 60),
          TrackPoint(lat: 47.564, lng: 10.751, elevationMeters: 1115, secondsSinceStart: 120),
        ],
        pois: const [TourPoiRef(label: 'Gasthof, sumse', lat: 47.56, lng: 10.74)],
      );

  test('insert + getAllTours: Round-Trip über alle Felder', () async {
    final repo = await freshDb();
    final id = await repo.insertTour(sampleTour('Alpenrunde'));
    expect(id, greaterThan(0));

    final tours = await repo.getAllTours();
    expect(tours.length, 1);
    final t = tours.first;
    expect(t.id, id);
    expect(t.title, 'Alpenrunde');
    expect(t.distanceMeters, closeTo(123456.7, 0.01));
    expect(t.elevationGainMeters, closeTo(890.1, 0.01));
    expect(t.durationSeconds, 7200);
    expect(t.track.length, 3);
    expect(t.track[1].elevationMeters, closeTo(1120, 0.01));
    expect(t.track[1].secondsSinceStart, closeTo(60, 0.01));
    // Komma im POI-Namen darf das CSV-Format nicht brechen.
    expect(t.pois.length, 1);
    expect(t.pois.first.label, 'Gasthof, sumse');
  });

  test('update + delete', () async {
    final repo = await freshDb();
    final id = await repo.insertTour(sampleTour('Alt'));
    final tour = (await repo.getAllTours()).first;

    await repo.updateTour(tour.copyWith(title: 'Neu'));
    expect((await repo.getAllTours()).first.title, 'Neu');

    await repo.deleteTour(id);
    expect(await repo.getAllTours(), isEmpty);
  });

  test('geplante Rundtour wird als Tour gespeichert und geladen', () async {
    final repo = await freshDb();
    final start = DateTime.utc(2026, 10, 1, 9);
    final planned = recordedTourFromPlan(
      title: 'Geplante Rundtour',
      startedAt: start,
      track: const [
        TrackPoint(lat: 47.5, lng: 10.7, secondsSinceStart: 0),
        TrackPoint(lat: 47.6, lng: 10.8, secondsSinceStart: 1800),
        TrackPoint(lat: 47.5, lng: 10.7, secondsSinceStart: 3600),
      ],
      distanceMeters: 50000,
      durationSeconds: 3600,
    );
    await repo.insertTour(planned);

    final tours = await repo.getAllTours();
    expect(tours.length, 1);
    final t = tours.first;
    expect(t.title, 'Geplante Rundtour');
    expect(t.startedAt, start);
    expect(t.endedAt, start.add(const Duration(hours: 1)));
    expect(t.distanceMeters, closeTo(50000, 0.01));
    expect(t.durationSeconds, closeTo(3600, 0.01));
    expect(t.elevationGainMeters, 0);
    expect(t.track.length, 3);
    expect(t.track.last.secondsSinceStart, closeTo(3600, 0.01));
  });

  test('getTour: null bei unbekannter ID', () async {
    final repo = await freshDb();
    expect(await repo.getTour(999), isNull);
  });
}
