import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:motoroute_app/features/poi/biker_poi_sync.dart';
import 'package:motoroute_app/features/poi/poi_offline_cache.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _MockDio extends Mock implements Dio {}

class _MockProbe extends Mock implements ConnectivityProbe {}

/// In-memory-DB mit dem produktiven Schema (sqflite_common_ffi).
Future<Database> _openInMemory() => databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      // singleInstance:false - sonst teilen sich die Tests EINE :memory:-DB.
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
    );

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  TestWidgetsFlutterBinding.ensureInitialized();

  late _MockDio dio;
  late _MockProbe probe;
  late PoiOfflineDatabase db;
  late BikerPoiSyncController controller;

  // BFF-Vertrag: IDs kommen MIT biker-Präfix (Namensraum-Trennung zu OSM).
  const payload = {
    'since': '2026-09-18T12:00:00.000Z',
    'hasMore': false,
    'pois': [
      {
        'id': 'biker-p1',
        'name': 'Kurvenkönig neu',
        'category': 'PUB',
        'lat': 48.1,
        'lon': 11.5,
        'bikerScore': 88,
        'amenities': {'motorcycle_parking': true},
      },
    ],
    'deletedIds': ['p-old'],
  };

  void stubSuccess() {
    when(() => dio.get<Map<String, dynamic>>(
          any(),
          queryParameters: any(named: 'queryParameters'),
          options: any(named: 'options'),
          cancelToken: any(named: 'cancelToken'),
          onReceiveProgress: any(named: 'onReceiveProgress'),
        )).thenAnswer((_) async => Response<Map<String, dynamic>>(
          requestOptions: RequestOptions(path: '/v1/biker-pois/sync'),
          data: payload,
        ));
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    dio = _MockDio();
    probe = _MockProbe();
    when(() => probe.isOnline()).thenAnswer((_) async => true);
    when(() => probe.events).thenAnswer((_) => const Stream.empty());
    db = PoiOfflineDatabase(existing: await _openInMemory());
    controller = BikerPoiSyncController(dio, database: db, probe: probe);
  });

  group('applyPush (bikerpoi.batch über die App-WebSocket)', () {
    test('löst sofort einen Delta-Sync aus und übernimmt die neuen POIs', () async {
      stubSuccess();

      await controller.applyPush({'p1', 'p2'});

      expect(controller.state.pois, hasLength(1));
      expect(controller.state.pois.single.id, 'biker-p1');
      expect(controller.state.pois.single.bikerScore, 88);
      verify(() => dio.get<Map<String, dynamic>>(
            any(),
            queryParameters: any(named: 'queryParameters'),
            options: any(named: 'options'),
            cancelToken: any(named: 'cancelToken'),
            onReceiveProgress: any(named: 'onReceiveProgress'),
          )).called(1);
    });

    test('leere ID-Menge: kein Netzwerk-Call', () async {
      await controller.applyPush(const {});
      verifyNever(() => dio.get<dynamic>(any()));
    });

    test('Sync-Fehler (Dienst offline): Push läuft still ins Leere, kein Crash', () async {
      when(() => dio.get<Map<String, dynamic>>(
            any(),
            queryParameters: any(named: 'queryParameters'),
            options: any(named: 'options'),
            cancelToken: any(named: 'cancelToken'),
            onReceiveProgress: any(named: 'onReceiveProgress'),
          )).thenThrow(DioException(
        requestOptions: RequestOptions(path: '/v1/biker-pois/sync'),
        type: DioExceptionType.connectionError,
      ));

      await controller.applyPush({'p1'});

      expect(controller.state.isSyncing, isFalse);
      // connectionError ist KEINE 503 -> Fehlerzustand gesetzt, aber kein Crash.
      expect(controller.state.error, isNotNull);
    });
  });
}
