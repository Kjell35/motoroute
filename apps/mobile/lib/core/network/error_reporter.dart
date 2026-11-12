import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_client.dart';
import 'error_message.dart';

/// Sender für einen fertigen Bericht. Liefert den HTTP-Status und wirft bei
/// Netzwerkfehlern. In Tests austauschbar, damit kein Server nötig ist.
typedef TelemetrySender = Future<int> Function(Map<String, Object?> payload);

/// Zähler rund um das Reporting. Sie machen sichtbar, wenn Berichte NICHT
/// ankommen - vorher verschwand jeder Fehlschlag spurlos.
///
/// Die Zähler werden persistiert (`telemetry.diagnostics.v1`) und beim
/// App-Start wieder geladen: Erst dadurch zeigt die Diagnose langfristig,
/// wie viele Berichte wirklich ankommen, statt bei jedem Start bei null
/// zu beginnen. [queued] wird nicht gespeichert, sondern ergibt sich aus
/// der Warteschlange.
class TelemetryDiagnostics {
  int attempted = 0;
  int accepted = 0;
  int failed = 0;
  int queued = 0;
  DateTime? since;
  DateTime? lastAttemptAt;
  DateTime? lastAcceptedAt;
  DateTime? lastFailureAt;
  String? lastFailureReason;

  void reset() {
    attempted = 0;
    accepted = 0;
    failed = 0;
    queued = 0;
    since = null;
    lastAttemptAt = null;
    lastAcceptedAt = null;
    lastFailureAt = null;
    lastFailureReason = null;
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'attempted': attempted,
        'accepted': accepted,
        'failed': failed,
        'since': since?.millisecondsSinceEpoch,
        'lastAttemptAt': lastAttemptAt?.millisecondsSinceEpoch,
        'lastAcceptedAt': lastAcceptedAt?.millisecondsSinceEpoch,
        'lastFailureAt': lastFailureAt?.millisecondsSinceEpoch,
        'lastFailureReason': lastFailureReason,
      };

  /// Liest gespeicherte Zähler. Beschädigte oder fremde Daten ergeben null
  /// (dann startet die Zählung eben neu) - Reporting darf nie werfen.
  static TelemetryDiagnostics? decode(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final data = jsonDecode(raw);
      if (data is! Map<String, dynamic>) return null;
      return TelemetryDiagnostics()
        ..attempted = _asInt(data['attempted'])
        ..accepted = _asInt(data['accepted'])
        ..failed = _asInt(data['failed'])
        ..since = _asDate(data['since'])
        ..lastAttemptAt = _asDate(data['lastAttemptAt'])
        ..lastAcceptedAt = _asDate(data['lastAcceptedAt'])
        ..lastFailureAt = _asDate(data['lastFailureAt'])
        ..lastFailureReason = data['lastFailureReason'] is String
            ? data['lastFailureReason'] as String
            : null;
    } catch (_) {
      return null;
    }
  }

  static int _asInt(Object? value) => value is int ? value : 0;

  static DateTime? _asDate(Object? value) =>
      value is int ? DateTime.fromMillisecondsSinceEpoch(value) : null;

  @override
  String toString() =>
      'Telemetrie: $attempted versucht, $accepted angenommen, $failed '
      'fehlgeschlagen, $queued in Warteschlange'
      '${lastFailureReason == null ? '' : ' (zuletzt: $lastFailureReason)'}';
}

/// Anonymes Fehler-/Crash-Reporting (Fire-and-Forget).
///
/// Die App meldet fehlgeschlagene Aktionen an `POST /v1/telemetry/errors`,
/// damit der Support sieht, WELCHE Bereiche bei WIE VIELEN Nutzern haken -
/// ohne Screenshots. Hardcore-Regeln:
///
///   1. NIEMALS blocking: `report()` wirft nichts, wartet auf nichts.
///   2. Anonym: Es gehen keine IDs, E-Mails, Freitext-Logs oder
///      Positionsdaten. Der Server leitet aus dem Auth-Token (falls
///      vorhanden) nur einen tagesstabilen SHA-256-Hash ab - Rückschluss
///      auf Accounts ist serverseitig durch das Salz ausgeschlossen.
///   3. Gedrosselt: max. 30 Berichte pro App-Sitzung und 30 s Cooldown
///      pro Kategorie, damit eine Fehlerschleife nicht spammt.
///   4. Opt-out: Nutzer kann es in den Einstellungen (Community) abschalten.
///   5. VERLUSTFREI (soweit möglich): Ein Bericht, der nicht ankommt,
///      landet in einer kleinen persistenten Warteschlange und wird beim
///      nächsten Versuch bzw. beim nächsten App-Start nachgeliefert.
///      Ohne das war jeder Timeout ein endgültig verlorener Bericht -
///      gerade beim Kaltstart des Free-Tier-Servers (30-50 s) kam so
///      praktisch nichts an.
///   6. SICHTBAR: Nicht angekommene Berichte werden im Debug-Build
///      geloggt und in [diagnostics] gezählt (persistent über Neustarts),
///      statt still zu verschwinden.
class ErrorReporter {
  ErrorReporter._();
  static final ErrorReporter instance = ErrorReporter._();

  static const _kPrefKey = 'telemetry.enabled';
  static const _kOutboxKey = 'telemetry.outbox.v1';
  static const _kDiagnosticsKey = 'telemetry.diagnostics.v1';
  static const _maxPerSession = 30;
  static const _maxOutbox = 20;
  static const _maxFlushPerRun = 3;
  static const _categoryCooldown = Duration(seconds: 30);

  bool _enabled = true;
  int _sessionCount = 0;
  final Map<String, DateTime> _lastSent = {};
  final List<_PendingReport> _outbox = [];
  TelemetryDiagnostics _diagnostics = TelemetryDiagnostics();
  String _appVersion = '?';
  String? Function()? _tokenGetter;

  /// Test-Seam: ersetzt den echten HTTP-Aufruf.
  TelemetrySender? _sender;

  /// Serialisiert alle Sendungen. Damit sind Berichte in Tests deterministisch
  /// abwartbar und parallele Wellen können den Server nicht fluten.
  Future<void> _activity = Future<void>.value();

  /// Weckt die Diagnose-Anzeige, sobald sich am Versand etwas ändert.
  final ValueNotifier<int> _revision = ValueNotifier<int>(0);

  /// Momentaufnahme des Reporter-Zustands (für Diagnose/Tests).
  TelemetryDiagnostics get diagnostics => _diagnostics;

  bool get isEnabled => _enabled;

  /// Meldet jede Änderung am Versandstatus (für die Diagnose-Anzeige).
  ValueListenable<int> get changes => _revision;

  /// Opt-out, Warteschlange und Zähler laden (einmalig, z. B. in main()).
  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _enabled = prefs.getBool(_kPrefKey) ?? true;
      _outbox
        ..clear()
        ..addAll(_decodeOutbox(prefs.getString(_kOutboxKey)));
      final stored = TelemetryDiagnostics.decode(prefs.getString(_kDiagnosticsKey));
      if (stored != null) _diagnostics = stored;
    } catch (_) {
      _enabled = true;
    }
    _diagnostics.queued = _outbox.length;
    // Beginn der Zählung festhalten: die Diagnose zeigt "Seit <Datum>".
    _diagnostics.since ??= DateTime.now();
    _revision.value++;
    unawaited(_persistDiagnostics());

    try {
      final info = await PackageInfo.fromPlatform();
      if (info.version.isNotEmpty) _appVersion = info.version;
    } catch (_) {
      // Version bleibt '?' - der Server verlangt nur 1-20 Zeichen.
    }
    // Berichte aus früheren Sitzungen nachliefern.
    _activity = _activity.then((_) => _flush());
  }

  /// Im Einstellungs-Tile umgeschaltet.
  Future<void> setEnabled(bool value) async {
    _enabled = value;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kPrefKey, value);
    } catch (_) {}
    if (value) {
      _activity = _activity.then((_) => _flush());
    }
  }

  /// Auth-Token-Lieferant binden (main(): AuthController.accessToken).
  /// Mit Token kann der Server den anonymen Tages-Hash ableiten
  /// ("wie viele EINZELNE Nutzer betroffen"); ohne Token -> 'anon'.
  void bindToken(String? Function()? getter) => _tokenGetter = getter;

  /// Zentraler Einstieg. [category] ist der Feature-Bereich (z. B.
  /// 'chat.load'), [error] das abgefangene Objekt.
  void report(String category, Object? error, {int? httpStatus}) {
    if (!_enabled) return;
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
    // Das Backend verlangt 1-300 Zeichen - leere Causes würden abgelehnt.
    if (cause.trim().isEmpty) cause = 'unbekannter Fehler';

    final entry = _PendingReport(
      category: category,
      cause: cause,
      httpStatus: status,
    );
    _activity = _activity.then((_) => _send(entry));
  }

  /// Flutter-Framework-Fehler (Layout/Build-Exceptions) melden.
  void reportFlutterError(FlutterErrorDetails details) {
    report('crash', details.exception, httpStatus: null);
  }

  /// Setzt die Zähler zurück (z. B. nach einer Testphase), "Seit" beginnt
  /// neu. Mit [discardPending] werden auch die wartenden Berichte verworfen
  /// (endgültig - die Oberfläche fragt vorher nach). Ohne das Flag bleiben
  /// sie erhalten, weil sie noch nicht ausgeliefert sind. Der neue Stand
  /// wird sofort gespeichert, damit er den nächsten Start überlebt.
  Future<void> resetDiagnostics({bool discardPending = false}) async {
    if (discardPending) _outbox.clear();
    _diagnostics
      ..attempted = 0
      ..accepted = 0
      ..failed = 0
      ..lastAttemptAt = null
      ..lastAcceptedAt = null
      ..lastFailureAt = null
      ..lastFailureReason = null
      ..since = DateTime.now();
    _diagnostics.queued = _outbox.length;
    await _commit();
    await _persistOutbox();
  }

  Future<void> _send(_PendingReport entry) async {
    if (await _post(entry)) {
      // Das Netz ist offensichtlich da: liegen gebliebene Berichte nachliefern.
      await _flush();
    } else {
      await _enqueue(entry);
    }
  }

  Future<bool> _post(_PendingReport entry) async {
    final payload = <String, Object?>{
      'category': entry.category,
      'cause': entry.cause,
      if (entry.httpStatus != null) 'httpStatus': entry.httpStatus,
      'platform': _platformName(),
      'appVersion': _appVersion.isEmpty ? '?' : _appVersion,
    };
    _diagnostics.attempted++;
    _diagnostics.lastAttemptAt = DateTime.now();
    try {
      final status = await (_sender ?? _defaultSender)(payload);
      if (status >= 200 && status < 300) {
        _diagnostics.accepted++;
        _diagnostics.lastAcceptedAt = DateTime.now();
        await _commit();
        return true;
      }
      await _fail('HTTP $status');
      return false;
    } catch (e) {
      await _fail(e.toString());
      return false;
    }
  }

  /// Echter HTTP-Aufruf. Bewusst über [ApiClient.create()]: dessen
  /// Kaltstart-Wiederholung (3 Versuche, 60 s Budget) überbrückt den
  /// eingeschlafenen Free-Tier-Server - ein einzelner 10-s-Timeout war
  /// zu kurz und hat Berichte zuverlässig verschluckt.
  Future<int> _defaultSender(Map<String, Object?> payload) async {
    final headers = <String, String>{'Content-Type': 'application/json'};
    final token = _tokenGetter?.call();
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
    final response = await ApiClient.create().post<dynamic>(
      '${ApiClient.baseUrl}/v1/telemetry/errors',
      data: payload,
      options: Options(headers: headers),
    );
    return response.statusCode ?? 0;
  }

  Future<void> _enqueue(_PendingReport entry) async {
    _outbox.add(entry);
    while (_outbox.length > _maxOutbox) {
      _outbox.removeAt(0); // ältester Bericht zuerst aufgeben
    }
    _diagnostics.queued = _outbox.length;
    await _persistOutbox();
    await _commit();
  }

  /// Warteschlange nachliefern. Bewusst auf wenige Einträge pro Lauf
  /// begrenzt, damit ein Funkloch nicht minutenlang Retries stapelt.
  Future<void> _flush() async {
    if (_outbox.isEmpty || !_enabled) return;
    final batch = _outbox.take(_maxFlushPerRun).toList();
    for (final entry in batch) {
      if (await _post(entry)) {
        _outbox.remove(entry);
      }
    }
    _diagnostics.queued = _outbox.length;
    await _persistOutbox();
    await _commit();
  }

  /// Zähler sichern und die Diagnose-Anzeige wecken.
  Future<void> _commit() async {
    _diagnostics.since ??= DateTime.now();
    _revision.value++;
    await _persistDiagnostics();
  }

  Future<void> _persistDiagnostics() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kDiagnosticsKey, jsonEncode(_diagnostics.toJson()));
    } catch (_) {
      // Persistenz ist Komfort, kein Vertrag: nie werfen.
    }
  }

  Future<void> _persistOutbox() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_outbox.isEmpty) {
        await prefs.remove(_kOutboxKey);
        return;
      }
      await prefs.setString(
        _kOutboxKey,
        jsonEncode(_outbox.map((e) => e.toJson()).toList()),
      );
    } catch (_) {
      // Persistenz ist Komfort, kein Vertrag: nie werfen.
    }
  }

  List<_PendingReport> _decodeOutbox(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    try {
      final data = jsonDecode(raw);
      if (data is! List) return const [];
      return data
          .whereType<Map<String, dynamic>>()
          .map(_PendingReport.fromJson)
          .whereType<_PendingReport>()
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> _fail(String reason) async {
    _diagnostics.failed++;
    _diagnostics.lastFailureAt = DateTime.now();
    _diagnostics.lastFailureReason =
        reason.length > 200 ? reason.substring(0, 200) : reason;
    if (kDebugMode) {
      debugPrint('[Telemetrie] Bericht nicht angekommen: $reason');
    }
    await _commit();
  }

  String _platformName() => switch (defaultTargetPlatform) {
        TargetPlatform.android => 'android',
        TargetPlatform.iOS => 'ios',
        _ => 'web',
      };

  /// Nur für Tests: Sender/Version setzen.
  @visibleForTesting
  void debugConfigure({TelemetrySender? sender, String? appVersion}) {
    if (sender != null) _sender = sender;
    if (appVersion != null) _appVersion = appVersion;
  }

  /// Nur für Tests: Speicher-Zustand zurücksetzen. Die Persistenz bleibt
  /// absichtlich unangetastet - so lässt sich ein App-Neustart nachstellen.
  @visibleForTesting
  void debugReset() {
    _enabled = true;
    _sessionCount = 0;
    _lastSent.clear();
    _outbox.clear();
    _sender = null;
    _appVersion = '?';
    _activity = Future<void>.value();
    _diagnostics = TelemetryDiagnostics();
    _revision.value = 0;
  }

  /// Nur für Tests: wartet, bis alle offenen Sendungen abgeschlossen sind.
  @visibleForTesting
  Future<void> debugIdle() => _activity;
}

/// Ein Bericht, der noch nicht bestätigt angenommen wurde.
class _PendingReport {
  _PendingReport({
    required this.category,
    required this.cause,
    this.httpStatus,
  });

  final String category;
  final String cause;
  final int? httpStatus;

  Map<String, Object?> toJson() => {
        'c': category,
        'e': cause,
        if (httpStatus != null) 's': httpStatus,
      };

  static _PendingReport? fromJson(Map<String, dynamic> json) {
    final category = json['c'];
    final cause = json['e'];
    if (category is! String || category.isEmpty) return null;
    if (cause is! String || cause.isEmpty) return null;
    final status = json['s'];
    return _PendingReport(
      category: category,
      cause: cause,
      httpStatus: status is int ? status : null,
    );
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
