import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:motoroute_app/core/network/api_client.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('create() liefert Dio mit Retry-Interceptor', () {
    final dio = ApiClient.create();
    expect(dio.interceptors, isNotEmpty);
    expect(dio.options.connectTimeout, const Duration(seconds: 25));
  });

  test('Retry-Interceptor: connectionTimeout wird wiederholt, 4xx nicht', () async {
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
      return ResponseBody.fromString('{"error":"x"}', 400,
          headers: {Headers.contentTypeHeader: [Headers.jsonContentType]});
    });

    // 1) Timeout-Pfad: 3 Versuche, dann Fehler durchgereicht.
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
