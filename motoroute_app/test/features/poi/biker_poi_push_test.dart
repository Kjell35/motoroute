import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:motoroute_app/features/poi/biker_poi_sync.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockDio extends Mock implements Dio {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _MockDio dio;
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

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    dio = _MockDio();
    controller = BikerPoiSyncController(dio);
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
