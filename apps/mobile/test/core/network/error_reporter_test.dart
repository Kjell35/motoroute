import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:motoroute_app/core/network/error_reporter.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _outboxKey = 'telemetry.outbox.v1';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    ErrorReporter.instance.debugReset();
  });

  Future<SharedPreferences> prefs() => SharedPreferences.getInstance();

  test('angenommener Bericht landet nicht in der Warteschlange', () async {
    final sent = <Map<String, Object?>>[];
    ErrorReporter.instance.debugConfigure(
      sender: (payload) async {
        sent.add(payload);
        return 202;
      },
      appVersion: '1.0.3',
    );
    await ErrorReporter.instance.init();
    ErrorReporter.instance.report(
      'navigation.session',
      StateError('kaputt'),
      httpStatus: 503,
    );
    await ErrorReporter.instance.debugIdle();

    expect(sent, hasLength(1));
    expect(sent.single['category'], 'navigation.session');
    expect(sent.single['appVersion'], '1.0.3');
    expect(sent.single['platform'], 'android');
    expect(sent.single['httpStatus'], 503);
    expect(sent.single['cause'], contains('kaputt'));
    expect(ErrorReporter.instance.diagnostics.accepted, 1);
    expect(ErrorReporter.instance.diagnostics.queued, 0);
    expect((await prefs()).getString(_outboxKey), isNull);
  });

  test('abgelehnter Bericht wird gemerkt und beim naechsten Start nachgeliefert',
      () async {
    ErrorReporter.instance.debugConfigure(
      sender: (payload) async => 400,
      appVersion: '1.0.3',
    );
    await ErrorReporter.instance.init();
    ErrorReporter.instance.report('auth.role', StateError('verboten'));
    await ErrorReporter.instance.debugIdle();

    expect(ErrorReporter.instance.diagnostics.failed, 1);
    expect(ErrorReporter.instance.diagnostics.lastFailureReason, 'HTTP 400');
    final raw = (await prefs()).getString(_outboxKey);
    expect(raw, isNotNull);
    expect(raw, contains('auth.role'));

    // Neue App-Sitzung: Warteschlange wird geladen und nachgeliefert.
    final replayed = <Map<String, Object?>>[];
    ErrorReporter.instance.debugReset();
    ErrorReporter.instance.debugConfigure(
      sender: (payload) async {
        replayed.add(payload);
        return 202;
      },
      appVersion: '1.0.4',
    );
    await ErrorReporter.instance.init();
    await ErrorReporter.instance.debugIdle();

    expect(replayed.map((p) => p['category']), contains('auth.role'));
    expect(ErrorReporter.instance.diagnostics.accepted, 1);
    expect(ErrorReporter.instance.diagnostics.queued, 0);
    expect((await prefs()).getString(_outboxKey), isNull);
  });

  test('Netzwerkfehler wird nicht verschluckt, sondern gemerkt', () async {
    ErrorReporter.instance.debugConfigure(
      sender: (payload) async => throw StateError('offline'),
      appVersion: '1.0.3',
    );
    await ErrorReporter.instance.init();
    ErrorReporter.instance.report('voice.tts', StateError('kein Netz'));
    await ErrorReporter.instance.debugIdle();

    expect(ErrorReporter.instance.diagnostics.failed, 1);
    expect(ErrorReporter.instance.diagnostics.lastFailureReason,
        contains('offline'));
    expect((await prefs()).getString(_outboxKey), contains('voice.tts'));
  });

  test('Warteschlange ist auf 20 Berichte begrenzt (aelteste fallen weg)',
      () async {
    ErrorReporter.instance.debugConfigure(
      sender: (payload) async => 503,
      appVersion: '1.0.3',
    );
    await ErrorReporter.instance.init();
    for (var i = 0; i < 25; i++) {
      ErrorReporter.instance.report('other.$i', StateError('fehler $i'));
    }
    await ErrorReporter.instance.debugIdle();

    final decoded =
        jsonDecode((await prefs()).getString(_outboxKey)!) as List<dynamic>;
    expect(decoded, hasLength(20));
    expect(ErrorReporter.instance.diagnostics.queued, 20);
    // Die ersten fünf sind zugunsten der neueren verworfen worden.
    expect(jsonEncode(decoded), isNot(contains('other.0')));
    expect(jsonEncode(decoded), contains('other.24'));
  });

  test('Cooldown pro Kategorie und Opt-out verhindern Doppelberichte',
      () async {
    final sent = <Map<String, Object?>>[];
    ErrorReporter.instance.debugConfigure(
      sender: (payload) async {
        sent.add(payload);
        return 202;
      },
      appVersion: '1.0.3',
    );
    await ErrorReporter.instance.init();
    ErrorReporter.instance.report('chat.load', StateError('a'));
    ErrorReporter.instance.report('chat.load', StateError('b'));
    await ErrorReporter.instance.debugIdle();
    expect(sent, hasLength(1));

    await ErrorReporter.instance.setEnabled(false);
    ErrorReporter.instance.report('chat.send', StateError('c'));
    await ErrorReporter.instance.debugIdle();
    expect(sent, hasLength(1));
  });

  test('leerer Cause wird ersetzt, damit das Backend nicht ablehnt', () async {
    final sent = <Map<String, Object?>>[];
    ErrorReporter.instance.debugConfigure(
      sender: (payload) async {
        sent.add(payload);
        return 202;
      },
      appVersion: '1.0.3',
    );
    await ErrorReporter.instance.init();
    ErrorReporter.instance.report('settings.privacy', '');
    await ErrorReporter.instance.debugIdle();

    expect(sent.single['cause'], 'unbekannter Fehler');
  });

  test('Zaehler ueberleben einen App-Neustart', () async {
    ErrorReporter.instance.debugConfigure(
      sender: (payload) async => 202,
      appVersion: '1.0.3',
    );
    await ErrorReporter.instance.init();
    ErrorReporter.instance.report('chat.load', StateError('erst'));
    await ErrorReporter.instance.debugIdle();
    expect(ErrorReporter.instance.diagnostics.accepted, 1);

    // Neustart: nur der Speicher wird geleert, die Persistenz bleibt.
    ErrorReporter.instance.debugReset();
    expect(ErrorReporter.instance.diagnostics.accepted, 0);
    ErrorReporter.instance.debugConfigure(
      sender: (payload) async => 400,
      appVersion: '1.0.4',
    );
    await ErrorReporter.instance.init();
    expect(ErrorReporter.instance.diagnostics.accepted, 1);
    expect(ErrorReporter.instance.diagnostics.attempted, 1);
    expect(ErrorReporter.instance.diagnostics.since, isNotNull);

    ErrorReporter.instance.report('chat.send', StateError('zweit'));
    await ErrorReporter.instance.debugIdle();
    expect(ErrorReporter.instance.diagnostics.attempted, 2);
    expect(ErrorReporter.instance.diagnostics.failed, 1);
    expect(ErrorReporter.instance.diagnostics.lastFailureReason, 'HTTP 400');
    expect((await prefs()).getString('telemetry.diagnostics.v1'), contains('"failed":1'));
  });

  test('Zuruecksetzen nullt die Zaehler und kann wartende Berichte verwerfen',
      () async {
    ErrorReporter.instance.debugConfigure(
      sender: (payload) async => 400,
      appVersion: '1.0.3',
    );
    await ErrorReporter.instance.init();
    ErrorReporter.instance.report('tour_diary.write', StateError('x'));
    await ErrorReporter.instance.debugIdle();
    expect(ErrorReporter.instance.diagnostics.failed, 1);
    expect(ErrorReporter.instance.diagnostics.queued, 1);

    // Ohne Verwerfen bleiben wartende Berichte erhalten.
    await ErrorReporter.instance.resetDiagnostics();
    final d = ErrorReporter.instance.diagnostics;
    expect(d.attempted, 0);
    expect(d.accepted, 0);
    expect(d.failed, 0);
    expect(d.lastFailureReason, isNull);
    expect(d.queued, 1);
    expect(d.since, isNotNull);

    // Mit Verwerfen ist die Warteschlange leer - auch gespeichert.
    await ErrorReporter.instance.resetDiagnostics(discardPending: true);
    expect(ErrorReporter.instance.diagnostics.queued, 0);
    expect((await prefs()).getString('telemetry.outbox.v1'), isNull);
    expect(
      (await prefs()).getString('telemetry.diagnostics.v1'),
      contains('"failed":0'),
    );

    // Der zurueckgesetzte Stand ueberlebt einen Neustart.
    ErrorReporter.instance.debugReset();
    ErrorReporter.instance.debugConfigure(
      sender: (payload) async => 202,
      appVersion: '1.0.4',
    );
    await ErrorReporter.instance.init();
    await ErrorReporter.instance.debugIdle();
    expect(ErrorReporter.instance.diagnostics.failed, 0);
    expect(ErrorReporter.instance.diagnostics.accepted, 0);
    expect(ErrorReporter.instance.diagnostics.queued, 0);
  });
}
