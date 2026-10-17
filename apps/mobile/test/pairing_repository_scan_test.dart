import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:motoroute/core/config/env.dart';
import 'package:motoroute/infrastructure/pairing/http_pairing_repository.dart';

/// Scan-Flow („Route von anderer App scannen“): Die nehmende App holt den Plan
/// vom im QR-Code kodierten Host — nicht von der build-zeitlichen Env-Basis.
/// Das ist die Voraussetzung dafür, dass Handy B die Route über Handy A's
/// Hotspot/IP laden kann, ohne mit derselben Build-Konstante gebaut zu sein.
void main() {
  const String planBody =
      '{"points":[{"label":"Start","lat":48.1,"lon":11.5},{"label":"Ziel","lat":49.4,"lon":11.1}]}';
  const String scannedUrl = 'http://192.168.43.10:8000/plan/ABC123';

  test('planOriginFromUrl liefert Scheme+Host+Port der gescannten URL', () {
    expect(
      PairingRepository.planOriginFromUrl(scannedUrl),
      'http://192.168.43.10:8000',
    );
    // Ohne expliziten Port:_origen ohne :port-Anteil.
    expect(
      PairingRepository.planOriginFromUrl('https://motoroute.example.com/plan/abc123'),
      'https://motoroute.example.com',
    );
    // Kein Host / keine Plan-URL → null.
    expect(PairingRepository.planOriginFromUrl('nicht einmal eine url'), isNull);
    expect(PairingRepository.planOriginFromUrl('http://x/plan/'), 'http://x');
  });

  test('fetchPlanFromScan ruft den gescannten Host (nicht Env) auf', () async {
    final List<String> hosts = [];
    final repo = PairingRepository(
      client: MockClient((request) async {
        hosts.add(request.url.host);
        expect(request.url.path, '/api/v1/pairing/ABC123');
        return http.Response(planBody, 200);
      }),
    );

    final places = await repo.fetchPlanFromScan(scannedUrl);

    expect(places, isNotNull);
    expect(places, hasLength(2));
    expect(hosts, ['192.168.43.10'], reason: 'QR-Host statt Env-Default');
  });

  test('nicht erreichbarer QR-Host → Fallback auf Env-Basis (2 Calls)', () async {
    final List<String> hosts = [];
    final repo = PairingRepository(
      client: MockClient((request) async {
        hosts.add('${request.url.host}:${request.url.port}');
        if (request.url.host == '192.168.43.10') {
          // Hotspot-Adresse von hier aus nicht erreichbar → Fehler → PairingException.
          throw http.ClientException('Network unreachable', request.url);
        }
        return http.Response(planBody, 200);
      }),
    );

    final places = await repo.fetchPlanFromScan(scannedUrl);

    expect(places, isNotNull);
    expect(places, hasLength(2));
    expect(hosts, ['192.168.43.10:8000', '${Uri.parse(Env.apiBaseUrl).host}:${Uri.parse(Env.apiBaseUrl).port}'],
        reason: 'QR-Host zuerst, dann Env-Fallback');
  });

  test('404 am gescannten Host wird NICHT auf Env gefallbackt', () async {
    // Erreichtes Backend ohne Plan ist ein echter Zustand (Token unbekannt/
    // abgelaufen) — ein Call genügt.
    var calls = 0;
    final repo = PairingRepository(
      client: MockClient((request) async {
        calls++;
        return http.Response('{}', 404);
      }),
    );

    final places = await repo.fetchPlanFromScan(scannedUrl);

    expect(places, isNull);
    expect(calls, 1);
  });

  test('QR-Host == Env-Basis → nur ein Call', () async {
    var calls = 0;
    final repo = PairingRepository(
      client: MockClient((request) async {
        calls++;
        return http.Response(planBody, 200);
      }),
    );

    final places = await repo.fetchPlanFromScan('${Env.apiBaseUrl}/plan/ABC123');

    expect(places, isNotNull);
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
