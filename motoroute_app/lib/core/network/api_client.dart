import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Wird vom AuthController registriert: zentrale Refresh-Funktion, die
/// den Access-Token erneuert und den neuen Token zurueckgibt - oder
/// null, wenn die Sitzung nicht mehr rettbar ist.
typedef TokenRefresher = Future<String?> Function();

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

  /// Zentraler Token-Refresher (vom AuthController in main() gebunden).
  static TokenRefresher? _tokenRefresher;

  /// Registriert den Refresh-Callback (einmalig beim Start).
  static void bindAuth({required TokenRefresher refresher}) {
    _tokenRefresher = refresher;
  }

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

  /// Dio-Client mit der effektiven Basis-URL und KALTSTART-Toleranz.
  ///
  /// Render-Free-Tier: Die Instanz schläft nach ~15 min Leerlauf ein,
  /// der erste Request wartet 30-60 s (bzw. scheitert an Connect-Timeout).
  /// Der Interceptor wiederholt deshalb VERBINDUNGS-Fehler automatisch
  /// (bis zu 3 Versuche, mit Backoff 2 s/4 s) - Timeouts beim Aufwecken
  /// werden so unsichtbar gefressen, statt "Verbindung prüfen" zu zeigen.
  /// 4xx/5xx werden NICHT wiederholt (echte Serverantworten).
  static Dio create() {
    final dio = Dio(
      BaseOptions(
        baseUrl: baseUrl,
        connectTimeout: const Duration(seconds: 25),
        receiveTimeout: const Duration(seconds: 45),
      ),
    );
    dio.interceptors.add(_TokenRefreshInterceptor());
    dio.interceptors.add(_ColdStartRetryInterceptor(dio));
    return dio;
  }

  /// Basis-URL zur WebSocket-URL umformen (http->ws, https->wss).
  static String asWebSocketUrl(String baseUrl) => baseUrl
      .replaceFirst('http://', 'ws://')
      .replaceFirst('https://', 'wss://');
}

/// Zentraler 401-Handler: Bei einer 401 fuehrt EIN Refresher den
/// Refresh-Call aus (pro App serialisiert, damit nicht 5 Screens
/// gleichzeitig 5 Refreshes feuern) und der Original-Request wird mit
/// dem frischen Token wiederholt. Scheitert der Refresh, wird der
/// Fehler normal durchgereicht - die Screens zeigen dann ihren
/// freundlichen Nicht-eingeloggt-Zustand.
class _TokenRefreshInterceptor extends Interceptor {
  static Future<String?>? _inFlight;

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    if (err.response?.statusCode != 401) {
      handler.next(err);
      return;
    }
    final refresher = ApiClient._tokenRefresher;
    if (refresher == null) {
      handler.next(err);
      return;
    }

    // Login/Refresh-Requests selbst NIE refreshen (Endlosschleife).
    final path = err.requestOptions.path;
    if (path.contains('/auth/login') ||
        path.contains('/auth/refresh') ||
        path.contains('/auth/register')) {
      handler.next(err);
      return;
    }

    // Serielles Refreshen: Nur der erste 401 loest den Call aus.
    _inFlight ??= refresher().whenComplete(() => _inFlight = null);
    final newToken = await _inFlight;
    if (newToken == null || newToken.isEmpty) {
      handler.next(err);
      return;
    }

    // Original-Request mit frischem Token wiederholen.
    final options = err.requestOptions;
    options.headers['Authorization'] = 'Bearer $newToken';
    try {
      final dio = Dio(BaseOptions(
        baseUrl: options.baseUrl,
        connectTimeout: const Duration(seconds: 25),
        receiveTimeout: const Duration(seconds: 45),
      ));
      final response = await dio.fetch<dynamic>(options);
      handler.resolve(response);
    } on DioException catch (e) {
      handler.next(e);
    }
  }
}

/// Wiederholt VERBINDUNGS-Fehler (Kaltstart des Render-Free-Tiers).
/// Bewusst nur Netzwerk-Layer-Fehler: connectionTimeout/connectionError/
/// receiveTimeout. Ein 404/500 ist eine echte Antwort und wird nicht
/// wiederholt. Maximal 3 Versuche mit wachsendem Abstand (2 s, 4 s) -
/// ein 60-s-Kaltstart passt damit in Versuch 1+2 (25 s Timeout + Pause
/// + 25 s) oder Versuch 3.
class _ColdStartRetryInterceptor extends Interceptor {
  _ColdStartRetryInterceptor(this._dio);
  final Dio _dio;

  static const _maxAttempts = 3;

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    final isConnectionIssue = err.type == DioExceptionType.connectionTimeout ||
        err.type == DioExceptionType.connectionError ||
        err.type == DioExceptionType.receiveTimeout;

    final attempts = (err.requestOptions.extra['__retryCount'] as int?) ?? 0;
    if (!isConnectionIssue || attempts >= _maxAttempts - 1) {
      handler.next(err);
      return;
    }

    final delay = Duration(seconds: 2 * (attempts + 1));
    await Future<void>.delayed(delay);

    final options = err.requestOptions;
    options.extra['__retryCount'] = attempts + 1;
    try {
      final response = await _dio.fetch<void>(options);
      handler.resolve(response);
    } on DioException catch (e) {
      handler.next(e);
    }
  }
}
