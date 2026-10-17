import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:motoroute_app/features/poi/poi_offline_cache.dart';
import 'package:motoroute_app/features/poi/poi_offline_sync.dart';
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

Map<String, dynamic> _poiJson(
  String id, {
  String category = 'PUB',
  String? sourceCategory,
  double lat = 48.1,
  double lon = 11.5,
  int bikerScore = 80,
}) =>
    {
      'id': id,
      'name': 'POI $id',
      'category': category,
      if (sourceCategory != null) 'sourceCategory': sourceCategory,
      'lat': lat,
      'lon': lon,
      'bikerScore': bikerScore,
      'amenities': <String, dynamic>{},
      'updatedAt': '2026-09-18T09:00:00.000Z',
    };

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  TestWidgetsFlutterBinding.ensureInitialized();

  late _MockDio dio;
  late _MockProbe probe;
  late PoiOfflineDatabase db;
  late OfflineSyncService service;

  void stubDelta(Map<String, dynamic> body) {
    when(() => dio.get<Map<String, dynamic>>(
          any(),
          queryParameters: any(named: 'queryParameters'),
        )).thenAnswer(
      (_) async => Response<Map<String, dynamic>>(
        requestOptions: RequestOptions(path: '/v1/biker-pois/sync'),
        data: body,
      ),
    );
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    dio = _MockDio();
    probe = _MockProbe();
    when(() => probe.isOnline()).thenAnswer((_) async => true);
    when(() => probe.events).thenAnswer((_) => const Stream.empty());
    db = PoiOfflineDatabase(existing: await _openInMemory());
    service = OfflineSyncService(dio: dio, database: db, probe: probe);
  });

  group('OfflineSyncService.sync', () {
    test('Online-Sync: Delta landet in SQLite, Cursor wird persistiert', () async {
      stubDelta({
        'since': '2026-09-18T12:00:00.000Z',
        'hasMore': false,
        'pois': [
          _poiJson('biker-p1', category: 'PUB', sourceCategory: 'kneipe'),
          _poiJson('biker-p2', category: 'BIKER_MEETUP', sourceCategory: 'gartenlokal', lat: 47.9, lon: 10.9),
        ],
        'deletedIds': <String>[],
      });

      final result = await service.sync();

      expect(result, OfflineSyncResult.ok);
      expect(await db.count(), 2);
      // 8-Kategorien-Erhalt: Rohwert reist getrennt vom App-Mapping.
      final rows = await db.inBounds(
        minLat: 47,
        minLng: 10,
        maxLat: 49,
        maxLng: 12,
      );
      expect(
        {for (final r in rows) r.id: (r.appCategory, r.sourceCategory)}['biker-p1'],
        ('PUB', BikerPoiSourceCategory.kneipe),
      );
      expect(
        {for (final r in rows) r.id: r.sourceCategory}['biker-p2'],
        BikerPoiSourceCategory.gartenlokal,
      );
      expect(await service.readCursor(), '2026-09-18T12:00:00.000Z');
    });

    test('deletedIds entfernen Zeilen physisch aus der lokalen DB', () async {
      await db.upsertAll([
        CachedBikerPoi(
          id: 'biker-old',
          name: 'Verschwunden',
          sourceCategory: BikerPoiSourceCategory.kneipe,
          appCategory: 'PUB',
          lat: 48,
          lng: 11,
          bikerScore: 40,
          motorcycleParking: false,
          meetingPoint: false,
          updatedAt: DateTime.utc(2026, 9, 1),
        ),
      ]);
      stubDelta({
        'since': '2026-09-18T12:00:00.000Z',
        'hasMore': false,
        'pois': <Map<String, dynamic>>[],
        'deletedIds': ['biker-old'],
      });

      final result = await service.sync();

      expect(result, OfflineSyncResult.ok);
      expect(await db.count(), 0);
    });

    test('Offline (Probe false): kein HTTP-Call, Bestand bleibt, still', () async {
      await db.upsertAll([
        CachedBikerPoi(
          id: 'biker-keep',
          name: 'Bleibt',
          sourceCategory: null,
          appCategory: 'PUB',
          lat: 48,
          lng: 11,
          bikerScore: 10,
          motorcycleParking: false,
          meetingPoint: false,
          updatedAt: DateTime.utc(2026, 9, 1),
        ),
      ]);
      when(() => probe.isOnline()).thenAnswer((_) async => false);

      final result = await service.sync();

      expect(result, OfflineSyncResult.offline);
      verifyNever(() => dio.get<Map<String, dynamic>>(any(),
          queryParameters: any(named: 'queryParameters')));
      expect(await db.count(), 1);
      expect(await service.readCursor(), isNull);
    });

    test('503 (Dienst nicht konfiguriert) bleibt still wie bisher', () async {
      when(() => dio.get<Map<String, dynamic>>(any(),
              queryParameters: any(named: 'queryParameters')))
          .thenThrow(DioException(
        requestOptions: RequestOptions(path: '/v1/biker-pois/sync'),
        type: DioExceptionType.badResponse,
        response: Response<void>(
          requestOptions: RequestOptions(path: '/v1/biker-pois/sync'),
          statusCode: 503,
        ),
      ));

      final result = await service.sync();

      expect(result, OfflineSyncResult.offline);
    });

    test('Netzfehler trotz Online-Probe -> error (nicht offline)', () async {
      when(() => dio.get<Map<String, dynamic>>(any(),
              queryParameters: any(named: 'queryParameters')))
          .thenThrow(DioException(
        requestOptions: RequestOptions(path: '/v1/biker-pois/sync'),
        type: DioExceptionType.connectionError,
      ));

      final result = await service.sync();

      expect(result, OfflineSyncResult.error);
      expect(service.lastResult, OfflineSyncResult.error);
    });

    test('Cursor-Kontinuität: erster Sync Epoch, danach serverTime', () async {
      stubDelta({
        'since': '2026-09-18T12:00:00.000Z',
        'hasMore': false,
        'pois': <Map<String, dynamic>>[],
        'deletedIds': <String>[],
      });

      await service.sync();
      await service.sync();

      final captured = verify(() => dio.get<Map<String, dynamic>>(
            any(),
            queryParameters: captureAny(named: 'queryParameters'),
          )).captured.cast<Map<String, dynamic>>();
      expect(captured, hasLength(2));
      expect(captured.first['since'], '1970-01-01T00:00:00.000Z');
      expect(captured.last['since'], '2026-09-18T12:00:00.000Z');
    });

    test('Pagination: hasMore=true zieht Folgeseiten nach, Cursor erst am Ende', () async {
      var call = 0;
      when(() => dio.get<Map<String, dynamic>>(
            any(),
            queryParameters: any(named: 'queryParameters'),
          )).thenAnswer((inv) async {
        call++;
        final q = inv.namedArguments[#queryParameters] as Map<String, dynamic>;
        if (call == 1) {
          return Response<Map<String, dynamic>>(
            requestOptions: RequestOptions(path: '/v1/biker-pois/sync'),
            data: {
              'since': 'page1-cursor',
              'hasMore': true,
              'pois': [_poiJson('biker-a')],
              'deletedIds': <String>[],
            },
          );
        }
        // Seite 2 muss mit dem Folgeseiten-Cursor der Seite 1 aufgerufen werden.
        expect(q['since'], 'page1-cursor', reason: 'Folgeseite muss den neuen Cursor nutzen');
        return Response<Map<String, dynamic>>(
          requestOptions: RequestOptions(path: '/v1/biker-pois ausgelastet'),
          data: {
            'since': '2026-09-18T12:00:00.000Z',
            'hasMore': false,
            'pois': [
              _poiJson('biker-b', lat: 47.9, lon: 10.9),
              _poiJson('biker-c', lat: 47.8, lon: 10.8),
            ],
            'deletedIds': <String>[],
          },
        );
      });

      final result = await service.sync();

      expect(result, OfflineSyncResult.ok);
      expect(await db.count(), 3, reason: 'Beide Seiten müssen in der DB landen');
      expect(await service.readCursor(), '2026-09-18T12:00:00.000Z');
      expect(call, 2);
    });

    test('Abbruch mitten im Delta: verarbeitete Seite bleibt, Cursor unverändert', () async {
      var call = 0;
      when(() => dio.get<Map<String, dynamic>>(
            any(),
            queryParameters: any(named: 'queryParameters'),
          )).thenAnswer((inv) async {
        call++;
        if (call == 1) {
          return Response<Map<String, dynamic>>(
            requestOptions: RequestOptions(path: '/v1/biker-pois/sync'),
            data: {
              'since': 'page1-cursor',
              'hasMore': true,
              'pois': [_poiJson('biker-a')],
              'deletedIds': <String>[],
            },
          );
        }
        throw DioException(
          requestOptions: RequestOptions(path: '/v1/biker-pois/sync'),
          type: DioExceptionType.connectionError,
        );
      });

      final result = await service.sync();

      // anythingChanged=true → still (offline), nicht lauter error.
      expect(result, OfflineSyncResult.offline);
      expect(await db.count(), 1, reason: 'Seite 1 bleibt persistiert');
      expect(await service.readCursor(), isNull,
          reason: 'Cursor darf bei unvollständigem Delta nicht fortschreiten');
    });

    test('Kategorien-Filter geht als kommaseparierter Parameter mit', () async {
      stubDelta({
        'since': 'x',
        'hasMore': false,
        'pois': <Map<String, dynamic>>[],
        'deletedIds': <String>[],
      });

      await service.sync(categories: {'PUB', 'SNACK'});

      final captured = verify(() => dio.get<Map<String, dynamic>>(
            any(),
            queryParameters: captureAny(named: 'queryParameters'),
          )).captured.cast<Map<String, dynamic>>().single;
      expect(captured['categories'], 'PUB,SNACK');
    });
  });

  group('watchConnectivity (Reconnect-Nachhol-Sync)', () {
    test('Rückkehr eines Schnitts triggert genau einen Sync (Debounce)',
        () async {
      final controller =
          StreamController<List<ConnectivityResult>>.broadcast();
      when(() => probe.events).thenAnswer((_) => controller.stream);
      stubDelta({
        'since': 'c1',
        'hasMore': false,
        'pois': <Map<String, dynamic>>[],
        'deletedIds': <String>[],
      });

      service.watchConnectivity();
      controller.add([ConnectivityResult.none]); // Funkloch
      await Future<void>.delayed(Duration.zero);
      controller.add([ConnectivityResult.wifi]); // Reconnect
      controller.add([ConnectivityResult.wifi]); // zweites Event -> debounced

      // Debounce 2 s abwarten.
      await Future<void>.delayed(const Duration(milliseconds: 2300));

      verify(() => dio.get<Map<String, dynamic>>(
            any(),
            queryParameters: any(named: 'queryParameters'),
          )).called(1);
      await controller.close();
    });

    test('Keine Schnitt-Events: kein Sync', () async {
      final controller =
          StreamController<List<ConnectivityResult>>.broadcast();
      when(() => probe.events).thenAnswer((_) => controller.stream);
      service.watchConnectivity();

      controller.add([ConnectivityResult.none]);
      await Future<void>.delayed(const Duration(milliseconds: 2300));

      verifyNever(() => dio.get<Map<String, dynamic>>(any(),
          queryParameters: any(named: 'queryParameters')));
      await controller.close();
    });
  });
}
