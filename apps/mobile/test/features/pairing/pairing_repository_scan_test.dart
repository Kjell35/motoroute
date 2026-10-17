import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:motoroute_app/features/pairing/data/pairing_repository.dart';

/// M3-Vertragstests für den Pairing-Port: Die nehmende App holt den Plan
/// vom im QR-Code kodierten Host (LAN/Hotspot), nicht von der build-zeitlichen
/// Basis; bei Nichterreichbarkeit des QR-Hosts gibt es die Env-Fallback-Runde.
void main() {
  const String planBody = '{"points":['
      '{"label":"Start","lat":48.1,"lon":11.5},'
      '{"label":"Ziel","lat":49.4,"lon":11.1}]}';
  const String scannedUrl = 'http://192.168.43.10:8000/plan/ABC123';

  test('planOriginFromUrl/planTokenFromUrl: Scheme+Host+Port und Token', () {
    expect(
      PairingRepository.planOriginFromUrl(scannedUrl),
      'http://192.168.43.10:8000',
    );
    expect(
      PairingRepository.planOriginFromUrl('https://motoroute.example.com/plan/abc123'),
      'https://motoroute.example.com',
    );
    expect(PairingRepository.planTokenFromUrl(scannedUrl), 'ABC123');
    expect(PairingRepository.planTokenFromUrl('nicht einmal eine url'), isNull);
  });

  test('fetchPlanFromScan ruft den gescannten Host (nicht die Env-Basis) auf', () async {
    final List<String> hosts = [];
    final repo = PairingRepository(
      client: MockClient((request) async {
        hosts.add(request.url.host);
        expect(request.url.path, '/api/v1/pairing/ABC123');
        return http.Response(planBody, 200);
      }),
    );

    final points = await repo.fetchPlanFromScan(scannedUrl);

    expect(points, isNotNull);
    expect(points, hasLength(2));
    expect(points!.first.label, 'Start');
    expect(hosts, ['192.168.43.10'], reason: 'QR-Host statt Env-Default');
  });

  test('nicht erreichbarer QR-Host → Fallback auf konfigurierte Basis (2 Calls)', () async {
    final List<String> hosts = [];
    final repo = PairingRepository(
      client: MockClient((request) async {
        hosts.add('${request.url.host}:${request.url.port}');
        if (request.url.host == '192.168.43.10') {
          throw http.ClientException('Network unreachable', request.url);
        }
        return http.Response(planBody, 200);
      }),
    );

    final points = await repo.fetchPlanFromScan(scannedUrl);

    expect(points, isNotNull);
    expect(hosts, hasLength(2), reason: 'QR-Host zuerst, dann Env-Fallback');
  });

  test('404 am gescannten Host wird NICHT gefallbackt', () async {
    var calls = 0;
    final repo = PairingRepository(
      client: MockClient((request) async {
        calls++;
        return http.Response('{}', 404);
      }),
    );

    final points = await repo.fetchPlanFromScan(scannedUrl);

    expect(points, isNull);
    expect(calls, 1);
  });

  test('fremde Scan-URL wirft PairingException statt Backend-Call', () async {
    final repo = PairingRepository(
      client: MockClient((request) async => http.Response('{}', 200)),
    );

    expect(
      () => repo.fetchPlanFromScan('https://maps.google.com/?q=xyz'),
      throwsA(isA<PairingException>()),
    );
  });
}
