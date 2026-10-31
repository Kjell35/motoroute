import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:motoroute_app/features/pairing/data/pairing_repository.dart';

void main() {
  const token = 'ABCDEF0123456789ABCDEF0123456789';

  test('start uses configured service and converts relative URLs to public',
      () async {
    late Uri requested;
    final repository = PairingRepository(
      apiBaseUrl: 'https://api.example.test/',
      publicBaseUrl: 'https://planning.example.test/',
      client: MockClient((request) async {
        requested = request.url;
        return http.Response(
          '{"token":"$token","plan_url":"/plan/$token",'
          '"plan_urls":["/plan/$token"],"expires_in_seconds":1800}',
          200,
        );
      }),
    );

    final start = await repository.start();

    expect(requested, Uri.https('api.example.test', '/api/v1/pairing/start'));
    expect(start.planUrl, 'https://planning.example.test/plan/$token');
    expect(start.planUrls, [start.planUrl]);
  });

  test('unconfigured backend fails promptly with an actionable message',
      () async {
    final repository = PairingRepository(
      apiBaseUrl: '',
      client: MockClient((_) async => throw StateError('should not request')),
    );

    await expectLater(
      repository.start(),
      throwsA(
        isA<PairingException>().having(
          (error) => error.message,
          'message',
          contains('Backend-URL fehlt'),
        ),
      ),
    );
  });
}
