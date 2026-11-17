import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motoroute_app/core/network/error_reporter.dart';
import 'package:motoroute_app/features/navigation_session/voice_announcer.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Prüft den Adapter gegen den Plattform-Kanal, den `TtsChannel.kt` bedient:
/// Methodennamen, Argumente und das Verhalten, wenn die Engine nicht kann.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final engine = ChannelTtsEngine();
  late List<MethodCall> calls;
  late Future<Object?> Function(MethodCall call)? responder;

  void installHandler() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(ChannelTtsEngine.channel, (call) async {
      calls.add(call);
      return responder?.call(call);
    });
  }

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    ErrorReporter.instance.debugReset();
    ErrorReporter.instance.debugConfigure(sender: (payload) async => 202);
    calls = <MethodCall>[];
    responder = null;
    installHandler();
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(ChannelTtsEngine.channel, null);
  });

  test('setLanguage schickt den Sprach-Tag an den Kanal', () async {
    responder = (call) async => true;

    await engine.setLanguage('de-DE');

    expect(calls.single.method, 'setLanguage');
    expect(calls.single.arguments, {'language': 'de-DE'});
  });

  test('speak schickt den Text und meldet nichts bei Erfolg', () async {
    responder = (call) async => true;

    await engine.speak('In 400 Metern links abbiegen');

    expect(calls.single.method, 'speak');
    expect(calls.single.arguments, {'text': 'In 400 Metern links abbiegen'});
    expect(ErrorReporter.instance.diagnostics.attempted, 0);
  });

  test('stop ruft den Kanal ohne Argumente', () async {
    responder = (call) async => true;

    await engine.stop();

    expect(calls.single.method, 'stop');
    expect(calls.single.arguments, isNull);
  });

  test('abgelehnter speak-Aufruf wird gemeldet, aber nicht geworfen', () async {
    responder = (call) async => false;

    await engine.speak('Jetzt rechts abbiegen');
    await ErrorReporter.instance.debugIdle();

    expect(ErrorReporter.instance.diagnostics.attempted, 1);
    expect(ErrorReporter.instance.diagnostics.accepted, 1);
  });

  test('fehlender Kanal (iOS) bricht die Ansage nicht ab', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(ChannelTtsEngine.channel, null);

    await engine.setLanguage('en-US');
    await engine.speak('Now turn left');
    await engine.stop();
    await ErrorReporter.instance.debugIdle();

    // Der Fehler landet im Reporting statt in einem Absturz.
    expect(ErrorReporter.instance.diagnostics.attempted, 1);
  });
}
