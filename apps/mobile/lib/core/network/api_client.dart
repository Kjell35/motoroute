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
///   3. Default: die produktive MotoRoute-API (installierbar auf echten Geräten)
///
/// Die WebSocket-URL des Chats/Ride-Radars leitet sich aus derselben
/// Basis ab (baseUrl + asWebSocketUrl) - ein Regler für alles.
class ApiClient {
  ApiClient._();

  static const _envBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://motoroute-api-8fi9.onrender.com',
  );

  static const _overrideKey = 'settings.apiBaseUrl';
  static const _maxAttempts = 3;
  static const _maxRequestDuration = Duration(seconds: 60);
  static const _retryDelay = Duration(seconds: 2);

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
    // MIGRATION: Früher konnte man die Server-URL in den Einstellungen
    // überschreiben. Ein einmal falsch/einmal lokal gespeicherter Wert
    // hat dann die gebackene Produktions-URL ÜBERSCHRIEBEN -> "Keine
    // Internetverbindung" überall, obwohl der Server läuft. Der Override
    // ist tot: gespeicherte Werte werden gelöscht, die gebackene URL
    // (_envBaseUrl) gilt immer.
    final legacy = prefs.getString(_overrideKey);
    if (legacy != null) {
      await prefs.remove(_overrideKey);
    }
    _cachedOverride = null;
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

  /// Dio-Client mit einer gemeinsamen Obergrenze für kalte/gestörte APIs.
  /// Verbindungsfehler und 502/503/504 werden insgesamt höchstens dreimal
  /// versucht; 401/andere 4xx/5xx sind echte Antworten und werden nicht
  /// wiederholt. Auch ein langsamer Free-Tier-Kaltstart bleibt nach max. 60 s
  /// erkennbar, statt beliebig lange alle Screens im Ladezustand festzuhalten.
  static Dio create() {
    final dio = Dio(
      BaseOptions(
        baseUrl: baseUrl,
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 20),
      ),
    );
    dio.interceptors.add(_RequestDeadlineInterceptor());
    dio.interceptors.add(_TokenRefreshInterceptor());
    dio.interceptors.add(_ColdStartRetryInterceptor(
      dio,
      maxAttempts: _maxAttempts,
      maxRequestDuration: _maxRequestDuration,
      retryDelay: _retryDelay,
    ));
    return dio;
  }

  /// Basis-URL zur WebSocket-URL umformen (http->ws, https->wss) und den
  /// Pfad des Chat-Gateways anhängen (Realtime-Fix): Das NestJS-Gateway
  /// lauscht auf /v1/chat/ws - ein Upgrade an der Root-URL wird vom
  /// Server nie beantwortet (Proxy: 502) und der Chat säße ohne
  /// Live-Nachrichten im REST-Polling.
  static String asWebSocketUrl(String baseUrl) {
    final ws = baseUrl
        .replaceFirst('http://', 'ws://')
        .replaceFirst('https://', 'wss://');
    final withoutTrailingSlash =
        ws.endsWith('/') ? ws.substring(0, ws.length - 1) : ws;
    return '$withoutTrailingSlash/v1/chat/ws';
  }
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
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 20),
      ));
      final response = await dio.fetch<dynamic>(options);
      handler.resolve(response);
    } on DioException catch (e) {
      handler.next(e);
    }
  }
}

/// Wiederholt vorübergehende Verbindungsfehler und 502/503/504 mit
/// begrenzter Gesamtzeit. So bleibt Render-Kaltstart tolerant, ohne dass
/// Chat- und Datenansichten endlos laden.
Duration _minDuration(Duration a, Duration b) => a <= b ? a : b;

/// Apply a single wall-clock budget across retries. Dio's connect/receive
/// timeouts individually do not bound total time spent across retries.
class _RequestDeadlineInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    options.extra['__requestStartedAt'] ??=
        DateTime.now().millisecondsSinceEpoch;
    handler.next(options);
  }
}

class _ColdStartRetryInterceptor extends Interceptor {
  _ColdStartRetryInterceptor(
    this._dio, {
    required int maxAttempts,
    required Duration maxRequestDuration,
    required Duration retryDelay,
  })  : _maxAttempts = maxAttempts,
        _maxRequestDuration = maxRequestDuration,
        _retryDelay = retryDelay;

  final Dio _dio;
  final int _maxAttempts;
  final Duration _maxRequestDuration;
  final Duration _retryDelay;

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    final isConnectionIssue = err.type == DioExceptionType.connectionTimeout ||
        err.type == DioExceptionType.connectionError ||
        err.type == DioExceptionType.receiveTimeout;

    // 502/503/504: Der Deploy/Neustart ist im Gange - genauso wie ein
    // Kaltstart behandeln (kurz warten, erneut versuchen).
    final status = err.response?.statusCode;
    final isDeployWindow = status == 502 || status == 503 || status == 504;

    final attempts = (err.requestOptions.extra['__retryCount'] as int?) ?? 0;
    final startedAt = err.requestOptions.extra['__requestStartedAt'] as int? ??
        DateTime.now().millisecondsSinceEpoch;
    final elapsed = DateTime.now().millisecondsSinceEpoch - startedAt;
    final delay = Duration(milliseconds: _retryDelay.inMilliseconds * attempts);
    if ((!isConnectionIssue && !isDeployWindow) ||
        attempts >= _maxAttempts - 1 ||
        elapsed + delay.inMilliseconds >= _maxRequestDuration.inMilliseconds) {
      handler.next(err);
      return;
    }

    await Future<void>.delayed(delay);

    final options = err.requestOptions;
    options.extra['__retryCount'] = attempts + 1;
    options.extra['__requestStartedAt'] = startedAt;
    final remaining = _maxRequestDuration -
        Duration(
            milliseconds: DateTime.now().millisecondsSinceEpoch - startedAt);
    if (remaining <= Duration.zero) {
      handler.next(err);
      return;
    }
    options.connectTimeout =
        _minDuration(const Duration(seconds: 15), remaining);
    options.receiveTimeout =
        _minDuration(const Duration(seconds: 20), remaining);
    try {
      final response = await _dio.fetch<void>(options);
      handler.resolve(response);
    } on DioException catch (e) {
      handler.next(e);
    }
  }
}
