import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:motoroute_app/features/map/data/location_repository.dart';
import 'package:motoroute_app/features/tour_diary/data/tour_repository.dart';
import 'package:motoroute_app/features/tour_diary/tour_diary_providers.dart';
import 'package:motoroute_app/features/tour_diary/tour_recorder.dart';

class _MockLocationRepository extends Mock implements LocationRepository {}

Position _pos(double lat, double lng, {double ele = 500}) => Position(
      latitude: lat,
      longitude: lng,
      timestamp: DateTime.now(),
      accuracy: 5,
      altitude: ele,
      altitudeAccuracy: 10,
      heading: 0,
      headingAccuracy: 0,
      speed: 10,
      speedAccuracy: 1,
    );

/// Spiegel des DDL aus tour_repository.dart - hält den Test unabhängig
/// von der echte-Pfad-Öffnung (getDatabasesPath geht im Test nicht).
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late _MockLocationRepository location;
  late StreamController<Position> positionStream;
  late Database db;
  late ProviderContainer container;

  setUp(() async {
    location = _MockLocationRepository();
    positionStream = StreamController<Position>();
    when(() => location.watchPosition(tuning: any(named: 'tuning')))
        .thenAnswer((_) => positionStream.stream);

    // ALLE Overrides statisch bei Container-Erstellung - Riverpod
    // verbietet das Nachziehen von Overrides zur Laufzeit.
    db = await _openInMemoryDb();
    container = ProviderContainer(overrides: [
      locationRepositoryProvider.overrideWithValue(location),
      tourDatabaseProvider.overrideWithValue(TourDatabase(existing: db)),
    ]);
    addTearDown(container.dispose);
    addTearDown(db.close);
    addTearDown(positionStream.close);
  });

  test('sammelt Punkte, km und Höhenmeter; Stillstand erzeugt keine Punkte',
      () async {
    final recorder = container.read(tourRecorderProvider.notifier);
    recorder.start();
    expect(container.read(tourRecorderProvider).isRecording, isTrue);

    positionStream.add(_pos(47.561000, 10.746000, ele: 1100));
    await Future<void>.delayed(Duration.zero);
    positionStream.add(_pos(47.561000, 10.746000, ele: 1100)); // Stillstand
    await Future<void>.delayed(Duration.zero);
    positionStream.add(_pos(47.562500, 10.748500, ele: 1120)); // +20 m Höhe
    await Future<void>.delayed(Duration.zero);

    final state = container.read(tourRecorderProvider);
    expect(state.points.length, 2,
        reason: 'Stillstand (< 8 m Abstand) wird gefiltert');
    expect(state.distanceMeters, greaterThan(200));
    expect(state.elevationGainMeters, closeTo(20, 0.5));
  });

  test('stop speichert Tour in der In-Memory-DB', () async {
    final recorder = container.read(tourRecorderProvider.notifier);
    recorder.start();
    for (var i = 0; i < 5; i++) {
      positionStream.add(
        _pos(47.561 + i * 0.002, 10.746 + i * 0.003, ele: 1100 + i * 10),
      );
      await Future<void>.delayed(Duration.zero);
    }

    final tour = await recorder.stop(title: 'Testfahrt');
    expect(tour, isNotNull);
    expect(tour!.title, 'Testfahrt');
    expect(tour.id, isNotNull, reason: 'Tour wurde in die DB geschrieben');

    final all = await container.read(tourDatabaseProvider).getAllTours();
    expect(all.length, 1);
    expect(all.first.title, 'Testfahrt');
    expect(all.first.track.length, 5);
    expect(all.first.pois, isEmpty);
  });

  test('stop mit zu wenigen Punkten verwirft stillschweigend', () async {
    final recorder = container.read(tourRecorderProvider.notifier);
    recorder.start();
    positionStream.add(_pos(47.561, 10.746));
    await Future<void>.delayed(Duration.zero);

    final tour = await recorder.stop();
    expect(tour, isNull);
    expect(container.read(tourRecorderProvider).isRecording, isFalse);
  });
}
