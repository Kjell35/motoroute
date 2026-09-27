import 'dart:async';
import 'dart:ui';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_client.dart';
import 'error_message.dart';

/// Anonymes Fehler-/Crash-Reporting (Fire-and-Forget).
///
/// Die App meldet fehlgeschlagene Aktionen an `POST /v1/telemetry/errors`,
/// damit der Support sieht, WELCHE Bereiche bei WIE VIELEN Nutzern haken -
/// ohne Screenshots. Hardcore-Regeln:
///
///   1. NIEMALS blocking: `report()` wirft nichts, wartet auf nichts,
///      scheitert still (auch offline, auch bei 4xx/5xx).
///   2. Anonym: Es gehen keine IDs, E-Mails, Freitext-Logs oder
///      Positionsdaten. Der Server leitet aus dem Auth-Token (falls
///      vorhanden) nur einen tagesstabilen SHA-256-Hash ab - Rückschluss
///      auf Accounts ist serverseitig durch das Salz ausgeschlossen.
///   3. Gedrosselt: max. 30 Berichte pro App-Sitzung und 30 sCooldown
///      pro Kategorie, damit eine Fehlerschleife nicht spammt.
///   4. Opt-out: Nutzer kann es in den Einstellungen (Community) abschalten.
class ErrorReporter {
  ErrorReporter._();
  static final ErrorReporter instance = ErrorReporter._();

  static const _kPrefKey = 'telemetry.enabled';
  static const _maxPerSession = 30;
  static const _categoryCooldown = Duration(seconds: 30);

  bool _enabled = true;
  bool _initialized = false;
  int _sessionCount = 0;
  final Map<String, DateTime> _lastSent = {};
  String _appVersion = '?';
  String? Function()? _tokenGetter;

  /// Opt-out-Persistenz laden (einmalig, z. B. in main()).
  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _enabled = prefs.getBool(_kPrefKey) ?? true;
    } catch (_) {
      _enabled = true;
    }
    _initialized = true;
    PackageInfo.fromPlatform().then<void>((info) {
      _appVersion = info.version;
    }).catchError((_) {});
  }

  /// Im Einstellungs-Tile umgeschaltet.
  Future<void> setEnabled(bool value) async {
    _enabled = value;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kPrefKey, value);
    } catch (_) {}
  }

  bool get isEnabled => _enabled;

  /// Auth-Token-Lieferant binden (main(): AuthController.accessToken).
  /// Mit Token kann der Server den anonymen Tages-Hash ableiten
  /// ("wie viele EINZELNE Nutzer betroffen"); ohne Token -> 'anon'.
  void bindToken(String? Function()? getter) => _tokenGetter = getter;

  /// Zentraler Einstieg. [category] ist der Feature-Bereich (z. B.
  /// 'chat.load'), [error] das abgefangene Objekt.
  void report(String category, Object? error, {int? httpStatus}) {
    if (!_enabled) return;
    if (!_initialized) _initialized = true; // nie blockieren
    if (_sessionCount >= _maxPerSession) return;
    final now = DateTime.now();
    final last = _lastSent[category];
    if (last != null && now.difference(last) < _categoryCooldown) return;

    _lastSent[category] = now;
    _sessionCount++;

    String cause;
    int? status = httpStatus;
    if (error is DioException) {
      cause = technicalCause(error);
      status ??= error.response?.statusCode;
    } else if (error != null) {
      cause = error.toString();
      if (cause.length > 300) cause = cause.substring(0, 300);
    } else {
      cause = 'unbekannter Fehler';
    }

    _post(category: category, cause: cause, httpStatus: status);
  }

  /// Flutter-Framework-Fehler (Layout/Build-Exceptions) melden.
  void reportFlutterError(FlutterErrorDetails details) {
    report('crash', details.exception, httpStatus: null);
  }

  Future<void> _post({
    required String category,
    required String cause,
    required int? httpStatus,
  }) async {
    try {
      final platform = switch (defaultTargetPlatform) {
        TargetPlatform.android => 'android',
        TargetPlatform.iOS => 'ios',
        _ => 'web',
      };
      final headers = <String, String>{'Content-Type': 'application/json'};
      final token = _tokenGetter?.call();
      if (token != null && token.isNotEmpty) {
        headers['Authorization'] = 'Bearer $token';
      }
      await Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 10),
      )).post(
        '${ApiClient.baseUrl}/v1/telemetry/errors',
        data: {
          'category': category,
          'cause': cause,
          if (httpStatus != null) 'httpStatus': httpStatus,
          'platform': platform,
          'appVersion': _appVersion,
        },
        options: Options(headers: headers, sendTimeout: const Duration(seconds: 10)),
      );
    } catch (_) {
      // Absichtlich still: Reporting darf nie auffallen.
    }
  }
}

/// Opt-out-Provider (Einstellungen > Community). Startet mit true;
/// die Persistenz lädt der ErrorReporter selbst in init().
final telemetryEnabledProvider = StateProvider<bool>((ref) => true);

/// Globale Crash-/Fehler-Haken installieren (einmalig in main()).
/// Ungefangene Flutter- und Dart-Fehler werden anonym gemeldet und dann
/// NORMAL weiterbehandelt (Logging/DevTools bleibt unveraendert).
void installErrorReportingHooks() {
  FlutterError.onError = (details) {
    ErrorReporter.instance.reportFlutterError(details);
    FlutterError.presentError(details);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    ErrorReporter.instance.report('crash', error);
    return false; // App NICHT schlucken - Standardverhalten bleibt.
  };
}
