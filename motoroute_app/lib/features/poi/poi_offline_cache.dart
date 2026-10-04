import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../../core/network/api_client.dart';

/// Offline-Fähigkeit der Biker-POI-Datenbank (Funklöcher, z. B. Alpen):
/// Die kuratierten POIs des Biker-POI-Dienstes liegen nach dem ersten
/// Online-Sync lokal in SQLite und stehen ohne jede Verbindung wieder
/// auf der Karte bereit.
///
/// Bewusst SQLite via sqflite (KEIN Isar): gleiche Wahl wie die Tour-
/// Datenbank (siehe tour_repository.dart) - rein Dart, keine Play-
/// Services, testbar via sqflite_common_ffi.

/// Die 8 Kategorien des Biker-POI-Dienstes (motoroute_poi_service,
/// TomTom-Kuratierung). Das BFF mappt sie auf 6 App-Kategorien; der
/// Rohwert reist als `sourceCategory` mit und bleibt hier ERHALTEN,
/// damit Filter/Statistiken auf Dienst-Ebene nicht verfälscht werden
/// (GARTENLOKAL ≠ BIKER_MEETUP, PENSION ≠ HOTEL).
enum BikerPoiSourceCategory {
  imbiss,
  bikertreff,
  kneipe,
  pension,
  restaurant,
  hotel,
  zeltplatz,
  gartenlokal;

  /// Rohwert im Dienst/BFF-Vertrag (kleingeschrieben, deutsch).
  String get wire => name;

  static BikerPoiSourceCategory? tryParse(String? raw) {
    if (raw == null) return null;
    for (final v in values) {
      if (v.name == raw) return v;
    }
    return null;
  }
}

/// Eine kuratierte Biker-POI-Zeile in der lokalen Datenbank.
///
/// appCategory spiegelt die bisherige BFF-Zusammenführung (gartenlokal ->
/// BIKER_MEETUP, pension -> MOTO_HOTEL), damit der Karten-Layer unverändert
/// weiterarbeitet; sourceCategory trägt die Dienst-Feinheit zusätzlich.
class CachedBikerPoi {
  final String id;
  final String name;
  final BikerPoiSourceCategory? sourceCategory;
  final String appCategory; // z. B. 'BIKER_MEETUP' (BFF-Mapping)
  final double lat;
  final double lng;
  final String? address;
  final int bikerScore;
  final bool motorcycleParking;
  final bool meetingPoint;
  final DateTime updatedAt;

  const CachedBikerPoi({
    required this.id,
    required this.name,
    required this.sourceCategory,
    required this.appCategory,
    required this.lat,
    required this.lng,
    this.address,
    required this.bikerScore,
    required this.motorcycleParking,
    required this.meetingPoint,
    required this.updatedAt,
  });

  factory CachedBikerPoi.fromSyncJson(Map<String, dynamic> json) {
    DateTime ts;
    try {
      ts = DateTime.parse(json['updatedAt'] as String? ?? '');
    } on FormatException {
      ts = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    }
    return CachedBikerPoi(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      sourceCategory: BikerPoiSourceCategory.tryParse(json['sourceCategory'] as String?),
      appCategory: json['category'] as String? ?? 'OTHER',
      lat: (json['lat'] as num).toDouble(),
      lng: (json['lon'] as num).toDouble(),
      address: json['address'] as String?,
      bikerScore: (json['bikerScore'] as num?)?.toInt() ?? 0,
      motorcycleParking:
          ((json['amenities'] as Map<String, dynamic>?)?['motorcycle_parking'] ?? false)
              as bool,
      meetingPoint:
          ((json['amenities'] as Map<String, dynamic>?)?['meeting_point'] ?? false) as bool,
      updatedAt: ts,
    );
  }

  Map<String, Object?> toRow() => {
        'id': id,
        'name': name,
        'source_category': sourceCategory?.wire,
        'app_category': appCategory,
        'lat': lat,
        'lng': lng,
        'address': address,
        'biker_score': bikerScore,
        'moto_parking': motorcycleParking ? 1 : 0,
        'meeting_point': meetingPoint ? 1 : 0,
        'updated_at': updatedAt.toUtc().toIso8601String(),
      };

  static CachedBikerPoi fromRow(Map<String, Object?> row) => CachedBikerPoi(
        id: row['id'] as String? ?? '',
        name: row['name'] as String? ?? '',
        sourceCategory: BikerPoiSourceCategory.tryParse(row['source_category'] as String?),
        appCategory: row['app_category'] as String? ?? 'OTHER',
        lat: (row['lat'] as num).toDouble(),
        lng: (row['lng'] as num).toDouble(),
        address: row['address'] as String?,
        bikerScore: (row['biker_score'] as num?)?.toInt() ?? 0,
        motorcycleParking: (row['moto_parking'] as int? ?? 0) == 1,
        meetingPoint: (row['meeting_point'] as int? ?? 0) == 1,
        updatedAt: DateTime.tryParse(row['updated_at'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      );
}

/// Lokale POI-Datenbank (SQLite via sqflite).
///
/// Upsert-Semantik über PRIMARY KEY(id): ein Delta-Sync überschreibt
/// geänderte Zeilen, `deletedIds` des BFF entfernen Zeilen physisch -
/// der DB-Stand entspricht damit exakt dem Server-Fenster des Cursors.
class PoiOfflineDatabase {
  static const _dbName = 'motoroute_pois.db';
  static const _dbVersion = 1;
  static const table = 'biker_pois';

  Database? _db;

  /// Für Tests: bereits offene (in-memory-)DB übernehmen.
  PoiOfflineDatabase({Database? existing}) : _db = existing;

  Future<Database> get db async {
    _db ??= await _open();
    return _db!;
  }

  Future<Database> _open() async {
    final dir = await getDatabasesPath();
    return openDatabase(
      p.join(dir, _dbName),
      version: _dbVersion,
      onCreate: (db, version) async {
        await db.execute('''
          create table $table (
            id text primary key,
            name text not null,
            source_category text,
            app_category text not null,
            lat real not null,
            lng real not null,
            address text,
            biker_score integer not null default 0,
            moto_parking integer not null default 0,
            meeting_point integer not null default 0,
            updated_at text not null
          )
        ''');
        await db.execute('create index idx_pois_updated on $table (updated_at)');
      },
    );
  }

  /// Delta-Upsert; nicht im [rows] enthaltene Bestandszeilen bleiben unangetastet.
  Future<void> upsertAll(List<CachedBikerPoi> rows) async {
    if (rows.isEmpty) return;
    final database = await db;
    final batch = database.batch();
    for (final row in rows) {
      batch.insert(table, row.toRow(),
          conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  Future<void> deleteByIds(List<String> ids) async {
    if (ids.isEmpty) return;
    final database = await db;
    final batch = database.batch();
    for (final id in ids) {
      batch.delete(table, where: 'id = ?', whereArgs: [id]);
    }
    await batch.commit(noResult: true);
  }

  /// Alle gecachten POIs im Viewport (Offline-Fallback für den Karten-Layer).
  /// [appCategories] filtert auf App-Kategorien (Karten-Toggles).
  Future<List<CachedBikerPoi>> inBounds({
    required double minLat,
    required double minLng,
    required double maxLat,
    required double maxLng,
    Set<String>? appCategories,
    int limit = 2000,
  }) async {
    final database = await db;
    const boundsWhere = 'lat >= ? AND lat <= ? AND lng >= ? AND lng <= ?';
    final args = <Object?>[minLat, maxLat, minLng, maxLng];
    var where = boundsWhere;
    if (appCategories != null && appCategories.isNotEmpty) {
      where =
          '($boundsWhere) AND app_category IN (${List.filled(appCategories.length, '?').join(',')})';
      args.addAll(appCategories);
    }
    final rows = await database.query(
      table,
      where: where,
      whereArgs: args,
      limit: limit,
    );
    return rows.map(CachedBikerPoi.fromRow).toList(growable: false);
  }

  /// Gesamter Bestand (App-Start-Restore in den Sync-State; Cap 5000
  /// analog dem bisherigen SharedPreferences-Cache).
  Future<List<CachedBikerPoi>> getAllBikerPois({int limit = 5000}) async {
    final database = await db;
    final rows = await database.query(
      table,
      orderBy: 'biker_score desc',
      limit: limit,
    );
    return rows.map(CachedBikerPoi.fromRow).toList(growable: false);
  }

  Future<int> count() async {
    final database = await db;
    final r = await database.rawQuery('select count(*) c from $table');
    return (r.first['c'] as int?) ?? 0;
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }
}

/// Netz-Probe für den OfflineSyncService: connectivity_plus liefert den
/// Schnitt-Typ (Mobilfunk/WLAN), eine leichte HEAD-Probe gegen das
/// eigene Backend verifiziert ERREICHBARKEIT. Beides nötig: connectivity
/// schlägt im Captive Portal fälschlich durch, die HTTP-Probe allein
/// würde bei jedem Sync-Zyklus unnötig Traffic erzeugen.
class ConnectivityProbe {
  ConnectivityProbe({Connectivity? connectivity, Dio? dio})
      : _connectivity = connectivity ?? Connectivity(),
        _dio = dio;

  final Connectivity _connectivity;

  /// Bewusst erst bei Gebrauch erzeugt: ApiClient zieht Interceptors
  /// (u. a. Cold-Start-Retry) auf; Unit-Tests injizieren ihren eigenen
  /// Dio via Konstruktor und machen dann gar keinen Netzverkehr.
  Dio? _dio;

  static const _timeout = Duration(seconds: 5);

  /// Verbindungs-Event-Stream für Reconnect-Watcher (OfflineSyncService).
  Stream<List<ConnectivityResult>> get events =>
      _connectivity.onConnectivityChanged;

  /// true = Schnitt vorhanden UND Backend erreichbar (Status < 500).
  /// Transportfehler/Timeout = false (Offline-Pfad), niemals ein Throw.
  Future<bool> isOnline() async {
    try {
      final list = await _connectivity.checkConnectivity();
      final hasInterface = list.any((s) =>
          s == ConnectivityResult.wifi ||
          s == ConnectivityResult.mobile ||
          s == ConnectivityResult.ethernet ||
          s == ConnectivityResult.vpn);
      if (!hasInterface) return false;
      return await canReachBackend();
    } catch (_) {
      return false;
    }
  }

  /// Kopfprobe gegen den Health-Endpunkt (kein Auth, kein Body). Ein
  /// 503 im Render-Kaltstart zählt als "nicht erreichbar" - der Sync
  /// versuchts beim nächsten Zyklus erneut.
  ///
  /// Bewusst EIN nackter Dio (nur Basis-URL, KEINE ApiClient-Interceptors):
  /// die Probe soll genau EINEN schnellen Versuch machen - der ColdStart-
  /// Retry-Interceptor des Sync-Clients würde sie künstlich verlangsamen
  /// und ihr Ergebnis verfälschen.
  Future<bool> canReachBackend() async {
    try {
      final client = _dio ??= Dio(
        BaseOptions(
          baseUrl: ApiClient.baseUrl,
          // 503 (Kaltstart) zählt als nicht erreichbar, alles darunter als ok.
          validateStatus: (status) => status != null && status < 500,
        ),
      );
      final res = await client.head<Object>('/v1/health').timeout(_timeout);
      final status = res.statusCode;
      return status != null && status < 500;
    } catch (_) {
      return false;
    }
  }
}
