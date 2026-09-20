import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Zentraler HTTP-Client für alle Repositories. Die Basis-URL zeigt
/// AUSSCHLIESSLICH auf das eigene Backend (motoroute_api) - kein
/// Drittanbieter-Key liegt jemals im App-Bundle, siehe
/// Systemarchitektur Phase 1/2 Teil C ("Kommunikationsprinzip").
///
/// Reihenfolge der Basis-URL (wichtig für echte Geräte):
///   1. Runtime-Override aus den Einstellungen ("Server"-Feld) - wird
///      in main() via ApiClient.init() geladen und aus dem Settings-
///      Screen live aktualisiert (NEUE Clients wirken sofort, ohne
///      Neubau der App).
///   2. `--dart-define=API_BASE_URL=...` beim Build (dev/staging/prod)
///   3. Default: Android-Emulator-Loopback (10.0.2.2 -> localhost)
///
/// Die WebSocket-URL des Chats/Ride-Radars leitet sich aus derselben
/// Basis ab (baseUrl + asWebSocketUrl) - ein Regler für alles.
class ApiClient {
  ApiClient._();

  static const _envBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:3000', // Android-Emulator -> localhost
  );

  static const _overrideKey = 'settings.apiBaseUrl';

  /// Cache der gespeicherten Override-URL - synchron lesbar, damit
  /// alle bestehenden Provider-Stellen (ApiClient.create()) unverändert
  /// synchron bleiben. Initialisiert in main() (ApiClient.init()).
  static String? _cachedOverride;

  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _cachedOverride = _normalized(prefs.getString(_overrideKey));
  }

  static String? _normalized(String? value) {
    final trimmed = value?.trim() ?? '';
    return trimmed.isEmpty ? null : trimmed;
  }

  /// Effektive Basis-URL (synchron): Einstellungen schlagen Build-Flag.
  static String get baseUrl => _cachedOverride ?? _envBaseUrl;

  /// Server-URL aus den Einstellungen speichern (leer = Build-Flag
  /// bzw. Default verwenden). Wirkt auf alle danach erzeugten Clients;
  /// der Chat-WS verbindet sich beim nächsten connect() neu.
  static Future<void> saveBaseUrl(String? value) async {
    final prefs = await SharedPreferences.getInstance();
    final normalized = _normalized(value);
    if (normalized == null) {
      await prefs.remove(_overrideKey);
    } else {
      await prefs.setString(_overrideKey, normalized);
    }
    _cachedOverride = normalized;
  }

  /// Aktuell gespeicherte Override-URL (für die Settings-Anzeige).
  static Future<String?> readSavedBaseUrl() async {
    final prefs = await SharedPreferences.getInstance();
    return _normalized(prefs.getString(_overrideKey));
  }

  /// Dio-Client mit der effektiven Basis-URL. Connect-Timeout 20 s:
  /// Auf dem Render-Free-Tier schläft die Instanz nach ~15 min Leerlauf
  /// ein - der erste Request muss den Kaltstart (30-60 s) abwarten
  /// koennen. Receive 45 s: Routing-Berechnungen (OSRM-Fallback) dauern
  /// auf der Free-Instanz sichtbar laenger als lokal.
  static Dio create() {
    return Dio(
      BaseOptions(
        baseUrl: baseUrl,
        connectTimeout: const Duration(seconds: 20),
        receiveTimeout: const Duration(seconds: 45),
      ),
    );
  }

  /// Basis-URL zur WebSocket-URL umformen (http->ws, https->wss).
  static String asWebSocketUrl(String baseUrl) => baseUrl
      .replaceFirst('http://', 'ws://')
      .replaceFirst('https://', 'wss://');
}
