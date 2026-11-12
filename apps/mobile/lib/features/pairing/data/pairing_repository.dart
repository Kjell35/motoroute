import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/network/api_client.dart';

/// „Route am Computer planen“ (M3-Feature) — Repository-Port des
/// neuen Backend-Vertrags in die alte App-Struktur. Die geplanten
/// Punkte werden als [PairingPoint] geliefert; die alten Screens
/// (Waypoint-Verwaltung, Scan) übersetzen sie in `Waypoint`-Objekte.
class PairingException implements Exception {
  const PairingException(this.message);
  final String message;
}

class PairingPoint {
  const PairingPoint({
    required this.label,
    required this.lat,
    required this.lng,
    this.detail,
  });
  final String label;
  final String? detail;
  final double lat;
  final double lng;
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
  /// Leerer Default = Backend ohne Multi-Address-Support (ältere Deployments).
  final List<String> planUrls;
  final int expiresInSeconds;
}

class PairingConfig {
  const PairingConfig._();

  /// Nur ein explizit konfiguriertes Backend verwenden. Die frühere
  /// Emulator-Loopback-URL war in Release-APKs auf realen Geräten und am
  /// Desktop unerreichbar.
  static const String apiBaseUrl = String.fromEnvironment(
    'MOTOROUTE_API_BASE_URL',
    defaultValue: '',
  );

  static const String publicBaseUrl = String.fromEnvironment(
    'MOTOROUTE_PAIRING_PUBLIC_BASE_URL',
  );
}

class PairingRepository {
  PairingRepository({
    http.Client? client,
    String? apiBaseUrl,
    String? publicBaseUrl,
  })  : _client = client ?? http.Client(),
        _apiBaseUrl = _normalizeOrigin(
          apiBaseUrl ??
              (PairingConfig.apiBaseUrl.isNotEmpty
                  ? PairingConfig.apiBaseUrl
                  : ApiClient.baseUrl),
        ),
        _publicBaseUrl =
            _normalizeOrigin(publicBaseUrl ?? PairingConfig.publicBaseUrl);

  final http.Client _client;
  final String _apiBaseUrl;
  final String? _publicBaseUrl;

  static String _normalizeOrigin(String? value) =>
      (value ?? '').trim().replaceFirst(RegExp(r'/+$'), '');

  Future<PairingStart> start() async {
    if (_apiBaseUrl.isEmpty) {
      throw const PairingException(
          'Routenplanung ist nicht erreichbar: Backend-URL fehlt.');
    }
    final Uri uri = Uri.parse('$_apiBaseUrl/api/v1/pairing/start');
    final http.Response response;
    try {
      response = await _client.post(uri).timeout(const Duration(seconds: 25));
    } catch (_) {
      throw const PairingException('Backend nicht erreichbar.');
    }
    if (response.statusCode != 200) {
      throw const PairingException('Pairing konnte nicht gestartet werden.');
    }
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Expected JSON object');
      }
      return _parseStart(decoded);
    } on Object {
      throw const PairingException('Ungültige Antwort vom Pairing-Backend.');
    }
  }

  PairingStart _parseStart(Map<String, dynamic> body) {
    final token = body['token'] as String;
    final rawUrls = (body['plan_urls'] as List<dynamic>?)
            ?.map((url) => url as String)
            .toList(growable: false) ??
        <String>[body['plan_url'] as String];
    final apiOrigin = Uri.parse(_apiBaseUrl).origin;
    final publicOrigin = _publicBaseUrl ?? apiOrigin;
    final urls = rawUrls.map((url) {
      final uri = Uri.parse(url);
      if (uri.path.endsWith('/plan/$token') &&
          (uri.host.isEmpty ||
              uri.host == 'localhost' ||
              uri.host == '127.0.0.1')) {
        return '$publicOrigin${uri.path}';
      }
      return url;
    }).toList(growable: false);
    if (urls.isEmpty || token.isEmpty || body['expires_in_seconds'] is! int) {
      throw const FormatException('Incomplete pairing response');
    }
    return PairingStart(
      token: token,
      planUrl: urls.first,
      planUrls: urls,
      expiresInSeconds: body['expires_in_seconds'] as int,
    );
  }

  /// Holt den geplanten Plan. `baseUrl` überschreibt die konfigurierte
  /// Basis (Scan-Flow nimmt den im QR-Code kodierten Host); Default ist
  /// `PairingConfig.apiBaseUrl`.
  Future<List<PairingPoint>?> fetchPlan(String token, {String? baseUrl}) async {
    String origin = (baseUrl == null || baseUrl.trim().isEmpty)
        ? _apiBaseUrl
        : baseUrl.trim();
    if (origin.isEmpty) {
      throw const PairingException('Pairing-Backend ist nicht konfiguriert.');
    }
    if (origin.endsWith('/')) origin = origin.substring(0, origin.length - 1);
    final Uri uri = Uri.parse(
        '$origin/api/v1/pairing/${Uri.encodeComponent(token.toUpperCase())}');
    final http.Response response;
    try {
      response = await _client.get(uri).timeout(const Duration(seconds: 25));
    } catch (_) {
      throw const PairingException('Backend nicht erreichbar.');
    }
    if (response.statusCode == 404) return null;
    if (response.statusCode != 200) {
      throw const PairingException('Plan konnte nicht abgerufen werden.');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const PairingException('Ungültige Plan-Antwort.');
    }
    final body = decoded;
    return (body['points'] as List<dynamic>? ?? const [])
        .map((point) => PairingPoint(
              label: point['label'] as String,
              detail: point['detail'] as String?,
              lat: (point['lat'] as num).toDouble(),
              lng: (point['lon'] as num).toDouble(),
            ))
        .toList(growable: false);
  }

  /// Scan-Flow: Nimmt die gescannte QR-URL und holt den Plan vom im
  /// QR-Code kodierten Host. Ist dieser nicht erreichbar, fällt der
  /// Aufruf auf die konfigurierte Basis zurück. Ein 404 wird NICHT
  /// gefallbackt (erreichtes Backend ohne Plan = echter Zustand).
  Future<List<PairingPoint>?> fetchPlanFromScan(String scannedUrl) async {
    final String? token = planTokenFromUrl(scannedUrl);
    if (token == null) {
      throw const PairingException('Das ist kein MotoRoute-Plan-QR-Code.');
    }
    final String? origin = planOriginFromUrl(scannedUrl);
    if (origin != null && origin != _apiBaseUrl) {
      try {
        return await fetchPlan(token, baseUrl: origin);
      } on PairingException {
        // Gescannter Host nicht erreichbar → konfigurierte Basis versuchen.
      }
    }
    return fetchPlan(token);
  }

  /// Extrahiert das Plan-Token aus einer MotoRoute-Plan-URL; `null` bei fremden URLs.
  static String? planTokenFromUrl(String value) {
    final Uri? uri = Uri.tryParse(value.trim());
    if (uri == null || !uri.path.contains('/plan/')) return null;
    final parts = uri.path.split('/plan/');
    if (parts.length < 2 || parts.last.trim().isEmpty) return null;
    return parts.last.trim().toUpperCase();
  }

  /// Ursprung (Scheme+Host+Port) einer Plan-URL; `null` ohne Host.
  static String? planOriginFromUrl(String value) {
    final Uri? uri = Uri.tryParse(value.trim());
    if (uri == null || uri.host.isEmpty || !uri.path.contains('/plan/')) {
      return null;
    }
    return uri.hasPort
        ? '${uri.scheme}://${uri.host}:${uri.port}'
        : '${uri.scheme}://${uri.host}';
  }
}
