import 'package:flutter_test/flutter_test.dart';
import 'package:motoroute_app/features/navigation_session/voice_announcer.dart';

/// Fake-Engine: zeichnet alle Calls auf, ohne einen Plattform-Kanal
/// anzufassen - die Trigger-Logik des Announcers ist so voll testbar.
class _FakeTts implements TtsEngine {
  final List<String> spoken = [];
  final List<String> languages = [];
  bool stopped = false;

  @override
  Future<void> setLanguage(String tag) async => languages.add(tag);

  @override
  Future<void> speak(String text) async => spoken.add(text);

  @override
  Future<void> stop() async => stopped = true;
}

VoiceAnnouncer _announcer(_FakeTts tts, {int minIntervalMs = 0, bool german = true}) =>
    VoiceAnnouncer(
      engine: tts,
      german: german,
      minIntervalMs: minIntervalMs,
    );

void main() {
  group('VoiceAnnouncer Manöver-Ansagen', () {
    test('Frühansage ab 400 m mit 50-m-Aufrundung ("In 350 Metern ...")', () async {
      final tts = _FakeTts();
      final voice = _announcer(tts);

      // 312 m -> aufgerundet 350 m; > 400 m wird nicht gesprochen.
      await voice.onTurn(instruction: 'Links abbiegen auf die B25', distanceMeters: 500);
      expect(tts.spoken, isEmpty);

      await voice.onTurn(instruction: 'Links abbiegen auf die B25', distanceMeters: 312);
      expect(tts.spoken, ['In 350 Metern Links abbiegen auf die B25']);
      expect(tts.languages, ['de-DE']);
    });

    test('Dedupe: gleiches Manöver + gleiche Stufe nur EINMAL je Fahrt', () async {
      final tts = _FakeTts();
      final voice = _announcer(tts);

      await voice.onTurn(instruction: 'Rechts abbiegen', distanceMeters: 300);
      await voice.onTurn(instruction: 'Rechts abbiegen', distanceMeters: 290);
      await voice.onTurn(instruction: 'Rechts abbiegen', distanceMeters: 280);

      expect(tts.spoken, hasLength(1));
    });

    test('Stufenwechsel soon -> now spricht erneut ("Jetzt ...")', () async {
      final tts = _FakeTts();
      final voice = _announcer(tts);

      await voice.onTurn(instruction: 'Rechts abbiegen', distanceMeters: 350);
      await voice.onTurn(instruction: 'Rechts abbiegen', distanceMeters: 50);

      expect(tts.spoken, ['In 350 Metern Rechts abbiegen', 'Jetzt Rechts abbiegen']);
    });

    test('Grenzfälle: genau 400 m wird gesprochen, genau 80 m ist "now"', () async {
      final tts = _FakeTts();
      final voice = _announcer(tts);

      await voice.onTurn(instruction: 'Leicht links', distanceMeters: 400);
      expect(tts.spoken, ['In 400 Metern Leicht links']);

      await voice.onTurn(instruction: 'Leicht rechts', distanceMeters: 80);
      expect(tts.spoken.last, 'Jetzt Leicht rechts');
    });

    test('Leere Anweisung wird nie gesprochen', () async {
      final tts = _FakeTts();
      final voice = _announcer(tts);

      await voice.onTurn(instruction: '', distanceMeters: 100);
      expect(tts.spoken, isEmpty);
    });

    test('Mindestabstand (2500 ms) dämpft Kaskaden: zweite Ansage sofort danach bleibt stumm', () async {
      final tts = _FakeTts();
      // Default-Intervall 2500 ms: zwei Aufrufe direkt nacheinander
      // liegen garantiert darunter -> das zweite (ANDERE) Manöver wird
      // unterdrückt, obwohl Dedupe hier nicht greifen würde.
      final voice = _announcer(tts, minIntervalMs: 2500);

      await voice.onTurn(instruction: 'Links abbiegen', distanceMeters: 350);
      await voice.onTurn(instruction: 'Rechts abbiegen', distanceMeters: 350);

      expect(tts.spoken, hasLength(1));
      expect(tts.spoken.single, contains('Links abbiegen'));
    });
  });

  group('VoiceAnnouncer Ziel-Ansagen', () {
    test('300-m-Vorwarnung mit Aufrundung, einmalig', () async {
      final tts = _FakeTts();
      final voice = _announcer(tts);

      await voice.onDestination(remainingMeters: 280);
      expect(tts.spoken, ['In 300 Metern erreichen Sie Ihr Ziel']);

      await voice.onDestination(remainingMeters: 250);
      expect(tts.spoken, hasLength(1)); // Dedupe
    });

    test('Ankunft (<= 25 m) einmalig und mit Vorrang vor der Vorwarnung', () async {
      final tts = _FakeTts();
      final voice = _announcer(tts);

      await voice.onDestination(remainingMeters: 20);
      expect(tts.spoken, ['Sie haben Ihr Ziel erreicht']);

      await voice.onDestination(remainingMeters: 10);
      expect(tts.spoken, hasLength(1)); // _arrivedAnnounced

      // Vorwarnung nach Ankunft nicht nachschieben.
      await voice.onDestination(remainingMeters: 200);
      expect(tts.spoken, hasLength(1));
    });

    test('Vorwarnung unterhalb 300 m, nichts über 300 m', () async {
      final tts = _FakeTts();
      final voice = _announcer(tts);

      await voice.onDestination(remainingMeters: 301);
      expect(tts.spoken, isEmpty);

      await voice.onDestination(remainingMeters: 30);
      expect(tts.spoken, ['In 50 Metern erreichen Sie Ihr Ziel']);
    });
  });

  group('VoiceAnnouncer Umschalter und Aufräumen', () {
    test('disabled: gar keine Ansagen', () async {
      final tts = _FakeTts();
      final voice = _announcer(tts)..enabled = false;

      await voice.onTurn(instruction: 'Links abbiegen', distanceMeters: 300);
      await voice.onDestination(remainingMeters: 200);
      await voice.onReroute(reason: 'Sperrung');

      expect(tts.spoken, isEmpty);
    });

    test('onReroute: stoppt laufende Ansage, leert Dedupe, spricht Grund', () async {
      final tts = _FakeTts();
      final voice = _announcer(tts);

      await voice.onTurn(instruction: 'Links abbiegen', distanceMeters: 300);
      expect(tts.spoken, hasLength(1));

      await voice.onReroute(reason: 'Sperrung auf der Route');
      expect(tts.stopped, isTrue);
      expect(tts.spoken.last, 'Route wird neu berechnet. Sperrung auf der Route.');

      // Dedupe geleert: dasselbe Manöver wird auf der neuen Route erneut
      // angesagt.
      await voice.onTurn(instruction: 'Links abbiegen', distanceMeters: 300);
      expect(
        tts.spoken,
        containsAllInOrder([
          'Route wird neu berechnet. Sperrung auf der Route.',
          'In 300 Metern Links abbiegen',
        ]),
      );
    });

    test('onReroute ohne Grund: nur Basissatz', () async {
      final tts = _FakeTts();
      final voice = _announcer(tts);

      await voice.onReroute();
      expect(tts.spoken, ['Route wird neu berechnet']);
    });

    test('onReroute leert auch die Ziel-Ansage-Historie (neue Route kann wieder 300 m haben)', () async {
      final tts = _FakeTts();
      final voice = _announcer(tts);

      await voice.onDestination(remainingMeters: 280);
      await voice.onReroute(reason: 'Stau');
      await voice.onDestination(remainingMeters: 280);

      final destAnnouncements =
          tts.spoken.where((s) => s.contains('erreichen Sie Ihr Ziel')).toList();
      expect(destAnnouncements, hasLength(2));
    });

    test('stop(): räumt alles auf (Engine-Stop, Dedupe-Reset)', () async {
      final tts = _FakeTts();
      final voice = _announcer(tts);

      await voice.onTurn(instruction: 'Links abbiegen', distanceMeters: 300);
      await voice.stop();

      expect(tts.stopped, isTrue);
      // Nach stop() (neue Navigation) wird wieder angesagt.
      await voice.onTurn(instruction: 'Links abbiegen', distanceMeters: 300);
      expect(tts.spoken.where((s) => s.contains('Links abbiegen')), hasLength(2));
    });
  });

  group('VoiceAnnouncer Sprache', () {
    test('EN-Nutzer: englische Satz-Rahmen + en-US', () async {
      final tts = _FakeTts();
      final voice = _announcer(tts, german: false);

      await voice.onTurn(instruction: 'Links abbiegen auf die B25', distanceMeters: 312);
      await voice.onDestination(remainingMeters: 280);
      await voice.onReroute();

      expect(tts.languages, ['en-US', 'en-US', 'en-US']);
      expect(tts.spoken, [
        'In 350 meters Links abbiegen auf die B25', // Straße bleibt deutsch (Backend-Text)
        'You will reach your destination in 300 meters',
        'Recalculating route',
      ]);
    });
  });
}
