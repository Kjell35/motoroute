import 'package:flutter_test/flutter_test.dart';
import 'package:motoroute_app/features/poi/poi_offline_cache.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  Future<PoiOfflineDatabase> openDb() async => PoiOfflineDatabase(
        existing: await databaseFactoryFfi.openDatabase(
          inMemoryDatabasePath,
          // singleInstance:false - sonst teilen sich alle Tests EINE DB.
          options: OpenDatabaseOptions(
            singleInstance: false,
            version: 1,
            onCreate: (db, _) async {
              await db.execute('''
                create table biker_pois (
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
            },
          ),
        ),
      );

  CachedBikerPoi poi(
    String id, {
    String appCategory = 'PUB',
    BikerPoiSourceCategory? source = BikerPoiSourceCategory.kneipe,
    double lat = 48.1,
    double lng = 11.5,
    int bikerScore = 77,
  }) =>
      CachedBikerPoi(
        id: id,
        name: 'POI $id',
        sourceCategory: source,
        appCategory: appCategory,
        lat: lat,
        lng: lng,
        bikerScore: bikerScore,
        motorcycleParking: true,
        meetingPoint: false,
        updatedAt: DateTime.utc(2026, 10, 1, 12),
      );

  test('Roundtrip: JSON -> Zeile -> Objekt erhält alle Felder inkl. 8er-Kategorie', () async {
    final db = await openDb();
    await db.upsertAll([
      CachedBikerPoi.fromSyncJson(_json('biker-g', category: 'BIKER_MEETUP', source: 'gartenlokal')),
    ]);

    final rows = await db.getAllBikerPois();
    expect(rows, hasLength(1));
    final r = rows.single;
    expect(r.id, 'biker-g');
    expect(r.appCategory, 'BIKER_MEETUP'); // App-Mapping erhalten
    expect(r.sourceCategory, BikerPoiSourceCategory.gartenlokal); // Rohwert erhalten
    expect(r.bikerScore, 77);
    expect(r.motorcycleParking, isTrue);
    expect(r.updatedAt, DateTime.utc(2026, 10, 1, 12));
    await db.close();
  });

  test('Upsert überschreibt geänderte Zeilen (ConflictAlgorithm.replace)', () async {
    final db = await openDb();
    await db.upsertAll([poi('x', bikerScore: 1)]);
    await db.upsertAll([poi('x', bikerScore: 99)]);

    final rows = await db.getAllBikerPois();
    expect(rows, hasLength(1));
    expect(rows.single.bikerScore, 99);
    await db.close();
  });

  test('inBounds filtert nach Viewport und App-Kategorien', () async {
    final db = await openDb();
    await db.upsertAll([
      poi('innen', lat: 48.2, lng: 11.6),
      poi('draussen', lat: 50.9, lng: 6.9),
      poi('innen-andere-kat', appCategory: 'MOTO_HOTEL', source: BikerPoiSourceCategory.hotel),
    ]);

    final hits = await db.inBounds(
      minLat: 48,
      minLng: 11,
      maxLat: 49,
      maxLng: 12,
      appCategories: {'PUB'},
    );
    expect(hits.map((e) => e.id), ['innen']);

    final ohneKat = await db.inBounds(minLat: 47, minLng: 6, maxLat: 52, maxLng: 13);
    expect(ohneKat, hasLength(3));
    await db.close();
  });

  test('8-Kategorien-Enum: alle Dienst-Werte Roundtrip-fähig', () {
    const wires = [
      'imbiss', 'bikertreff', 'kneipe', 'pension',
      'restaurant', 'hotel', 'zeltplatz', 'gartenlokal',
    ];
    expect(BikerPoiSourceCategory.values.map((e) => e.wire), wires);
    for (final w in wires) {
      expect(BikerPoiSourceCategory.tryParse(w)!.wire, w);
    }
    expect(BikerPoiSourceCategory.tryParse('unbekannt'), isNull);
    expect(BikerPoiSourceCategory.tryParse(null), isNull);
  });

  test('fromSyncJson: fehlende/defekte updatedAt fällt defensiv auf Epoch', () {
    final p = CachedBikerPoi.fromSyncJson({
      'id': 'x',
      'category': 'PUB',
      'lat': 1,
      'lon': 2,
      'bikerScore': 0,
      'updatedAt': 'kein-datum',
    });
    expect(p.updatedAt, DateTime.fromMillisecondsSinceEpoch(0, isUtc: true));
  });
}

Map<String, dynamic> _json(String id, {required String category, required String source}) => {
      'id': id,
      'name': 'N $id',
      'category': category,
      'sourceCategory': source,
      'lat': 48.1,
      'lon': 11.5,
      'bikerScore': 77,
      'amenities': {'motorcycle_parking': true, 'meeting_point': false},
      'updatedAt': '2026-10-01T12:00:00.000Z',
    };
