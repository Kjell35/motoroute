import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:motoroute_app/core/network/api_client.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
      'create() liefert Dio mit Retry-Interceptor und Produktions-API als Default',
      () {
    final dio = ApiClient.create();
    expect(dio.interceptors, isNotEmpty);
    expect(dio.options.connectTimeout, const Duration(seconds: 15));
    expect(ApiClient.baseUrl, 'https://motoroute-api-8fi9.onrender.com');
    expect(dio.options.baseUrl, ApiClient.baseUrl);
  });

  test('Retry-Interceptor: connectionTimeout wird dreimal versucht, 4xx nicht',
      () async {
    final dio = ApiClient.create();
    var calls = 0;

    dio.httpClientAdapter = _CountingAdapter((options) {
      calls++;
      if (options.path.contains('timeout')) {
        // Immer Timeout -> nach 3 Versuchen endgültig fehlschlagen.
        throw DioException(
          requestOptions: options,
          type: DioExceptionType.connectionTimeout,
        );
      }
      // 400er: echte Serverantwort, NICHT wiederholt.
      return ResponseBody.fromString('{"error":"x"}', 400, headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType]
      });
    });

    // 1) Timeout-Pfad: 3 Versuche mit begrenztem Gesamtbudget, dann Fehler
    //    durchgereicht. So können kaputte API-Requests nicht endlos laden.
    await expectLater(
      dio.get<void>('/x/timeout'),
      throwsA(isA<DioException>()),
    );
    expect(calls, 3, reason: 'connectionTimeout wird bis zu 3x versucht');

    // 2) 400er-Pfad: genau 1 Versuch, kein Retry.
    calls = 0;
    await expectLater(
      dio.get<void>('/x/badrequest'),
      throwsA(isA<DioException>()),
    );
    expect(calls, 1, reason: '4xx wird nie wiederholt');
  });

  test('Retry-Interceptor: 502 (Render-Deploy-Fenster) wird wiederholt',
      () async {
    final dio = ApiClient.create();
    var calls = 0;

    dio.httpClientAdapter = _CountingAdapter((options) {
      calls++;
      if (calls == 1) {
        // Erster Versuch: Gateway-Fehler waehrend des Deploy-Fensters.
        return ResponseBody.fromString('{"error":"bad gateway"}', 502,
            headers: {
              Headers.contentTypeHeader: [Headers.jsonContentType]
            });
      }
      // Zweiter Versuch: Instanz ist hochgefahren.
      return ResponseBody.fromString('{"ok":true}', 200, headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType]
      });
    });

    final response = await dio.get<Map<String, dynamic>>('/x/health');
    expect(calls, 2,
        reason: '502 wird wiederholt, Erfolg danach durchgereicht');
    expect(response.statusCode, 200);
  });

  test('Retry-Interceptor: 404 wird NICHT wiederholt', () async {
    final dio = ApiClient.create();
    var calls = 0;

    dio.httpClientAdapter = _CountingAdapter((options) {
      calls++;
      return ResponseBody.fromString('{"error":"nf"}', 404, headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType]
      });
    });

    await expectLater(
      dio.get<void>('/x/missing'),
      throwsA(isA<DioException>()),
    );
    expect(calls, 1, reason: '404 ist eine echte Antwort, kein Retry');
  });

  test('Retry-Interceptor: abgelaufenes Zeitbudget wird nicht erneut versucht',
      () async {
    final dio = ApiClient.create();
    var calls = 0;
    dio.httpClientAdapter = _CountingAdapter((options) {
      calls++;
      return ResponseBody.fromString(
        '{"error":"bad gateway"}',
        502,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType]
        },
      );
    });

    await expectLater(
      dio.get<void>(
        '/v1/chat/conversations',
        options: Options(extra: {
          '__requestStartedAt': DateTime.now().millisecondsSinceEpoch - 61000,
        }),
      ),
      throwsA(isA<DioException>()),
    );
    expect(calls, 1, reason: 'kein weiterer Versuch nach Ablauf des Budgets');
  });
}

class _CountingAdapter implements HttpClientAdapter {
  _CountingAdapter(this._handler);
  final ResponseBody Function(RequestOptions options) _handler;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    return _handler(options);
  }
}
