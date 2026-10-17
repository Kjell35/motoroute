/// E2E-Probe „Route am Computer planen" — läuft DART-seitig (wie die App).
///
/// Rollenverteilung:
///   1. APP     : POST /api/v1/pairing/start  → Token + plan_url
///   2. BROWSER : PUT  /api/v1/pairing/{token} (Web-Planner schreibt Punkte)
///   3. APP     : GET  /api/v1/pairing/{token} → Plan übernehmen
///   4. NEGATIV : GET  /api/v1/pairing/000000 → 404 → fetchPlan == null
///
/// Ausführen (Backend muss auf 192.168.178.101:8000 leben):
///   dart run tool/pairing_e2e_probe.dart
import 'dart:convert';
import 'dart:io';

const String base = 'http://192.168.178.101:8000';

Future<Map<String, dynamic>> _send(String method, String path, {Object? body, String? altBase}) async {
  final HttpClient client = HttpClient();
  final HttpClientRequest request = await client.openUrl(
    method,
    Uri.parse('${altBase ?? base}$path'),
  );
  if (body != null) {
    request.headers.contentType = ContentType.json;
    request.add(utf8.encode(jsonEncode(body)));
  }
  final HttpClientResponse response = await request.close().timeout(
        const Duration(seconds: 10),
      );
  final String text = await utf8.decodeStream(response);
  client.close();
  return <String, dynamic>{'status': response.statusCode, 'text': text};
}

Map<String, dynamic> _jsonCall(Map<String, dynamic> response) {
  return <String, dynamic>{
    'status': response['status'] as int,
    'body': jsonDecode(response['text'] as String) as Map<String, dynamic>,
  };
}

void _check(String what, bool condition) {
  stdout.writeln('${condition ? 'PASS  ' : 'FAIL  '} $what');
  if (!condition) {
    stdout.writeln('E2E fehlgeschlagen.');
    exitCode = 1;
  }
}

void main() async {
  // 1) APP-Rolle: Pairing anfordern.
  final Map<String, dynamic> start = _jsonCall(await _send('POST', '/api/v1/pairing/start'));
  final String token = start['body']['token'] as String;
  final String planUrl = start['body']['plan_url'] as String;
  _check('POST start → 200, 6-stelliges Token', start['status'] == 200 && token.length == 6);
  _check('plan_url verknüpft mit LAN-Backend',
      planUrl == '$base/plan/$token');

  // 2) BROWSER-Rolle: Web-Planner schreibt den Plan.
  final Map<String, dynamic> browserPut = _jsonCall(await _send(
    'PUT',
    '/api/v1/pairing/$token',
    body: <String, dynamic>{
      'points': <Map<String, dynamic>>[
        <String, dynamic>{'label': 'Start München', 'lat': 48.137, 'lon': 11.575},
        <String, dynamic>{'label': 'Tankstelle Ingolstadt', 'lat': 48.77, 'lon': 11.43},
        <String, dynamic>{'label': 'Ziel Kurvige Altroute', 'lat': 47.647, 'lon': 12.214},
      ],
    },
  ));
  _check('BROWSER-Rolle: PUT Plan → 200, 3 Punkte',
      browserPut['status'] == 200 && (browserPut['body']['points'] as List).length == 3);

  // 3) APP-Rolle: Plan abrufen (fetchPlan-Vertrag: Restitution als Places).
  final Map<String, dynamic> appGet = _jsonCall(await _send('GET', '/api/v1/pairing/$token'));
  final List<dynamic> points = appGet['body']['points'] as List<dynamic>;
  _check('APP-Rolle: GET Plan → 200 und Reihenfolge korrekt',
      appGet['status'] == 200 && points.length == 3 && points.first['label'] == 'Start München');

  // 4) NEGATIV: unbekanntes Token → 404 → die App zeigt „Token unbekannt“.
  final Map<String, dynamic> negative = _jsonCall(await _send('GET', '/api/v1/pairing/000000'));
  _check('NEGATIV: unbekannter Token → 404', negative['status'] == 404);

  // 5) Browser-Seite liefert HTML mit dem Token, damit der Nutzer sie öffnet.
  final Map<String, dynamic> page = await _send('GET', '/plan/$token');
  final String pageText = page['text'] as String;
  _check('BROWSER-Link: /plan/{token} → 200 und zeigt Token im HTML',
      page['status'] == 200 && pageText.contains(token));

  // 6) Multi-Address-Pairing: Der Start-Antwort muss MEHRERE plan_urls
  //    beiliegen (LAN-IP + WSL/vEthernet etc.), damit der QR-Code von einer
  //    App die Adresse der anderen App abdeckt (LAN/Hotspot).
  final List<dynamic> planUrls = (start['body']['plan_urls'] as List<dynamic>? ?? <dynamic>[]);
  _check('plan_urls[] enhält LAN-Backend-URL zuerst',
      planUrls.isNotEmpty && planUrls.first == '$base/plan/$token');
  if (planUrls.length > 1) {
    // plan_urls[i] ist eine VOLLSTÄNDIGE Plan-URL (…/plan/{token}); API-Base
    // ergibt sich durch Abschneiden von /plan/{token}.
    final String altBase = (planUrls[1] as String).replaceAll('/plan/$token', '');
    try {
      final Map<String, dynamic> alt = _jsonCall(
        await _send('GET', '/api/v1/pairing/$token', altBase: altBase)
            .timeout(const Duration(seconds: 8)),
      );
      _check('Zweitadresse alt. API-Base HTTP 200 auf GET pairing', alt['status'] == 200);
    } catch (error) {
      _check('Zweitadresse alt. API-Base HTTP 200 auf GET pairing', false);
      stdout.writeln('      Zweitadresse-Fehler: $error');
    }
  }

  stdout.writeln('E2E fertig (token $token, ${planUrls.length} Adresse(n)).');
}
