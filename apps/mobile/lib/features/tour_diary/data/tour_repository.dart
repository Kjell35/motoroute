import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../domain/tour_entities.dart';

/// Lokale Touren-Datenbank (SQLite via sqflite).
///
/// Bewusst SQLite statt Isar: sqflite ist rein Dart, braucht KEINE
/// Play-Services, ist auf jedem Android-Gerät stabil und die GPX-
/// Spur liegt als kompaktes CSV/JSON-Textfeld - für ein Tagebuch
/// (Lesen: Liste + Detail, Schreiben: nach Tourende) völlig
/// ausreichend. Die GPX-Rohdaten bleiben rekonstruierbar.
class TourDatabase {
  static const _dbName = 'motoroute_tours.db';
  static const _dbVersion = 1;
  static const table = 'tours';

  Database? _db;

  Future<Database> get db async {
    _db ??= await _open();
    return _db!;
  }

  /// Für Tests: bereits offene DB übernehmen (in-memory).
  TourDatabase({Database? existing}) : _db = existing;

  Future<Database> _open() async {
    final dir = await getDatabasesPath();
    return openDatabase(
      p.join(dir, _dbName),
      version: _dbVersion,
      onCreate: (db, version) async {
        await db.execute('''
          create table $table (
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
        await db.execute(
          'create index idx_tours_started on $table (started_at desc)',
        );
      },
    );
  }

  Future<int> insertTour(RecordedTour tour) async {
    final database = await db;
    return database.insert(table, _toRow(tour));
  }

  Future<void> updateTour(RecordedTour tour) async {
    final database = await db;
    await database.update(
      table,
      _toRow(tour),
      where: 'id = ?',
      whereArgs: [tour.id],
    );
  }

  Future<void> deleteTour(int id) async {
    final database = await db;
    await database.delete(table, where: 'id = ?', whereArgs: [id]);
  }

  /// Alle Touren, neueste zuerst. Track/POIs werden MITgeladen - die
  /// Liste braucht sie für die Miniaturkarte, ein separater Detail-
  /// Query wäre bei den üblichen Touroptionen (< ein paar tausend
  /// Punkte) ohne merklichen Vorteil.
  Future<List<RecordedTour>> getAllTours() async {
    final database = await db;
    final rows = await database.query(table, orderBy: 'started_at desc');
    return rows.map(_fromRow).toList(growable: false);
  }

  Future<RecordedTour?> getTour(int id) async {
    final database = await db;
    final rows = await database.query(
      table,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : _fromRow(rows.first);
  }

  Map<String, Object?> _toRow(RecordedTour tour) => {
        if (tour.id != null) 'id': tour.id,
        'title': tour.title,
        'started_at': tour.startedAt.toIso8601String(),
        'ended_at': tour.endedAt.toIso8601String(),
        'distance_meters': tour.distanceMeters,
        'elevation_gain_meters': tour.elevationGainMeters,
        'duration_seconds': tour.durationSeconds,
        'track_json': _encodeTrack(tour.track),
        'pois_json': _encodePois(tour.pois),
      };

  RecordedTour _fromRow(Map<String, Object?> row) {
    final track = _decodeTrack(row['track_json'] as String? ?? '');
    final pois = _decodePois(row['pois_json'] as String? ?? '');
    final duration = (row['duration_seconds'] as num?)?.toDouble() ?? 0;
    return RecordedTour(
      id: row['id'] as int?,
      title: row['title'] as String? ?? 'Tour',
      startedAt: DateTime.tryParse(row['started_at'] as String? ?? '') ?? DateTime.now(),
      endedAt: DateTime.tryParse(row['ended_at'] as String? ?? '') ?? DateTime.now(),
      distanceMeters: (row['distance_meters'] as num?)?.toDouble() ?? 0,
      elevationGainMeters: (row['elevation_gain_meters'] as num?)?.toDouble() ?? 0,
      durationSeconds: duration,
      track: track,
      pois: pois,
    );
  }

  /// Kompaktes CSV: lat,lng,ele,relSek - ein Dezimalpunkt, Semikolon
  /// als Punkt-Trenner. Deutlich kleiner als JSON, ausreichend schnell.
  String _encodeTrack(List<TrackPoint> track) => track
      .map((t) => [
            t.lat.toStringAsFixed(6),
            t.lng.toStringAsFixed(6),
            t.elevationMeters?.toStringAsFixed(1) ?? '',
            t.secondsSinceStart.toStringAsFixed(1),
          ].join(','))
      .join(';');

  List<TrackPoint> _decodeTrack(String raw) {
    if (raw.isEmpty) return const [];
    final out = <TrackPoint>[];
    for (final seg in raw.split(';')) {
      final parts = seg.split(',');
      if (parts.length < 4) continue;
      final lat = double.tryParse(parts[0]);
      final lng = double.tryParse(parts[1]);
      if (lat == null || lng == null) continue;
      out.add(TrackPoint(
        lat: lat,
        lng: lng,
        elevationMeters: parts[2].isEmpty ? null : double.tryParse(parts[2]),
        secondsSinceStart: double.tryParse(parts[3]) ?? 0,
      ));
    }
    return out;
  }

  /// POIs als JSON - Labels sind freier Text (Kommas, Semikolons),
  /// da ist ein Array-Format das einzig sichere.
  String _encodePois(List<TourPoiRef> pois) => jsonEncode([
        for (final poi in pois)
          {'label': poi.label, 'lat': poi.lat, 'lng': poi.lng},
      ]);

  List<TourPoiRef> _decodePois(String raw) {
    if (raw.isEmpty || raw == '[]') return const [];
    try {
      final list = jsonDecode(raw) as List;
      return [
        for (final entry in list)
          if (entry is Map)
            TourPoiRef(
              label: entry['label'] as String? ?? 'Wegpunkt',
              lat: (entry['lat'] as num).toDouble(),
              lng: (entry['lng'] as num).toDouble(),
            ),
      ];
    } catch (_) {
      return const [];
    }
  }
}

/// POIs einer Tour: kleine Helfer, die die aktiven POI-Treffer während
/// der Fahrt gegen die Tour speichern (besuchte Stopps).
RecordedTour attachPois(RecordedTour tour, List<TourPoiRef> pois) => RecordedTour(
      id: tour.id,
      title: tour.title,
      startedAt: tour.startedAt,
      endedAt: tour.endedAt,
      distanceMeters: tour.distanceMeters,
      elevationGainMeters: tour.elevationGainMeters,
      durationSeconds: tour.durationSeconds,
      track: tour.track,
      pois: pois,
    );
