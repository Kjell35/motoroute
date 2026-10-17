import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/config/env.dart';
import '../../domain/models/place.dart';

/// Pairing mit der PC-Planung: Token anfordern, Plan abrufen („Plan abrufen“).
class PairingException implements Exception {
  const PairingException(this.message);
  final String message;
}

class PairingStart {
  const PairingStart({
    required this.token,
    required this.planUrl,
    this.planUrls = const [],
    required this.expiresInSeconds,
  });
  final String token;
  final String planUrl;

  /// Alle Kandidaten-URLs (LAN/Hotspot/…) für den QR-Code — App-zu-App-Pairing.
  /// Leerer Default = Backend ohne Multi-Address-Support (older Deployment).
  final List<String> planUrls;
  final int expiresInSeconds;
}

class PairingRepository {
  PairingRepository({http.Client? client}) : _client = client ?? http.Client();
  final http.Client _client;

  /// Extrahiert das Plan-Token aus einer MotoRoute-Plan-URL; `null` bei fremden URLs.
  static String? planTokenFromUrl(String value) {
    final Uri? uri = Uri.tryParse(value.trim());
    if (uri == null || !uri.path.contains('/plan/')) return null;
    final parts = uri.path.split('/plan/');
    if (parts.length < 2 || parts.last.trim().isEmpty) return null;
    return parts.last.trim().toUpperCase();
  }

  /// Ursprung (Scheme+Host+Port) einer Plan-URL; `null` ohne Host.
  /// Der gescannte QR-Code nennt das Backend der **gebenden** App — die
  /// nehmende App soll exakt diesen Host ansprechen (LAN/Hotspot-Szenario).
  static String? planOriginFromUrl(String value) {
    final Uri? uri = Uri.tryParse(value.trim());
    if (uri == null || uri.host.isEmpty || !uri.path.contains('/plan/')) return null;
    return uri.hasPort
        ? '${uri.scheme}://${uri.host}:${uri.port}'
        : '${uri.scheme}://${uri.host}';
  }

  Future<PairingStart> start() async {
    final Uri uri = Uri.parse('${Env.apiBaseUrl}/api/v1/pairing/start');
    final http.Response response;
    try {
      response = await _client.post(uri).timeout(const Duration(seconds: 10));
    } catch (_) {
      throw const PairingException('Backend nicht erreichbar.');
    }
    if (response.statusCode != 200) {
      throw const PairingException('Pairing konnte nicht gestartet werden.');
    }
    final Map<String, dynamic> body = jsonDecode(response.body) as Map<String, dynamic>;
    // plan_urls[] ist der Multi-Address-Vertrag (LAN/Hotspot); ältere Backends
    // liefern nur plan_url — dann als Einzeiler zurückschließen.
    final List<String> urls = (body['plan_urls'] as List<dynamic>?)
            ?.map((url) => url as String)
            .toList(growable: false) ??
        <String>[
          body['plan_url'] as String,
        ];
    return PairingStart(
      token: body['token'] as String,
      planUrl: body['plan_url'] as String,
      planUrls: urls,
      expiresInSeconds: body['expires_in_seconds'] as int,
    );
  }

  /// Holt den am Computer/geben Gerät geplanten Plan. Liefert `null`, wenn der
  /// Token unbekannt/abgelaufen ist (404) und sonst die aktuellen Punkte.
  /// `baseUrl` überschreibt die konfigurierte Basis (Scan-Flow nimmt den
  /// im QR-Code kodierten Host); Default ist `Env.apiBaseUrl`.
  Future<List<Place>?> fetchPlan(String token, {String? baseUrl}) async {
    String origin = (baseUrl == null || baseUrl.trim().isEmpty)
        ? Env.apiBaseUrl
        : baseUrl.trim();
    if (origin.endsWith('/')) origin = origin.substring(0, origin.length - 1);
    final Uri uri = Uri.parse('$origin/api/v1/pairing/${Uri.encodeComponent(token.toUpperCase())}');
    final http.Response response;
    try {
      response = await _client.get(uri).timeout(const Duration(seconds: 10));
    } catch (_) {
      throw const PairingException('Backend nicht erreichbar.');
    }
    if (response.statusCode == 404) return null;
    if (response.statusCode != 200) {
      throw const PairingException('Plan konnte nicht abgerufen werden.');
    }
    final Map<String, dynamic> body = jsonDecode(response.body) as Map<String, dynamic>;
    return (body['points'] as List<dynamic>? ?? const [])
        .map((point) => Place(
              id: 'pairing:${point['label']}:${point['lat']},${point['lon']}',
              label: point['label'] as String,
              detail: point['detail'] as String?,
              latitude: (point['lat'] as num).toDouble(),
              longitude: (point['lon'] as num).toDouble(),
            ))
        .toList(growable: false);
  }

  /// Scan-Flow: Nimmt die gescannte QR-URL und holt den Plan vom im QR-Code
  /// kodierten Host. Ist dieser von hier aus nicht erreichbar (z. B. QR enthält
  /// die Hotspot-Adresse, das Telefon sitzt im LAN), fällt der Aufruf auf die
  /// konfigurierte `Env.apiBaseUrl` zurück — im Hotspot-Testaufbau zeigt sie
  /// auf denselben Backend-Host. Ein 404 wird NICHT gefallbackt: Erreichtes
  /// Backend ohne Plan ist ein echter Zustand, kein Netzwerkproblem.
  Future<List<Place>?> fetchPlanFromScan(String scannedUrl) async {
    final String? token = planTokenFromUrl(scannedUrl);
    if (token == null) {
      throw const PairingException('Das ist kein MotoRoute-Plan-QR-Code.');
    }
    final String? origin = planOriginFromUrl(scannedUrl);
    if (origin != null && origin != Env.apiBaseUrl) {
      try {
        return await fetchPlan(token, baseUrl: origin);
      } on PairingException {
        // Gescannter Host nicht erreichbar → konfigurierte Basis versuchen.
      }
    }
    return fetchPlan(token);
  }
}
