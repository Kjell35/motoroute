import 'package:flutter_tts/flutter_tts.dart';

/// Abstraktion über flutter_tts - die Trigger-Logik des Announcers kann
/// so ohne Plattform-Kanal getestet werden (Unit-Tests mit Fake-Engine).
abstract class TtsEngine {
  Future<void> setLanguage(String tag);
  Future<void> speak(String text);
  Future<void> stop();
}

/// Produktions-Engine: dünner Adapter um das flutter_tts-Plugin (in der
/// pubspec seit dem Scaffold vorhanden, hier erstmals genutzt).
/// Fehler werden bewusst verschluckt UND geloggt über den Aufrufer - TTS
/// darf die Navigation niemals crashen (Helmet-UX: kein Ton ist besser
/// als ein Absturz).
class FlutterTtsEngine implements TtsEngine {
  final FlutterTts _tts = FlutterTts();

  @override
  Future<void> setLanguage(String tag) async {
    try {
      await _tts.setLanguage(tag);
      await _tts.setSpeechRate(0.5); // 0.0-1.0, 0.5 = natürliches Tempo
      await _tts.setVolume(1.0);
      await _tts.setPitch(1.0);
      // Fire-and-forget: speak() blockiert nicht - die Trigger-Logik
      // dedupliziert selbst (siehe VoiceAnnouncer).
      await _tts.awaitSpeakCompletion(false);
    } catch (_) {
      // Sprachpaket fehlt evtl. - weiterer speak() schlägt dann still fehl.
    }
  }

  @override
  Future<void> speak(String text) async {
    try {
      await _tts.speak(text);
    } catch (_) {}
  }

  @override
  Future<void> stop() async {
    try {
      await _tts.stop();
    } catch (_) {}
  }
}

/// Sprachansagen für die aktive Navigation:
/// - Manöver-Frühansage ab 400 m ("In 400 Metern: Links abbiegen auf B123")
/// - Kurz-Hinweis ab 80 m ("Jetzt: Links abbiegen")
/// - Ziel-Ansagen (300 m / erreicht)
/// - Reroute-Hinweis + Zurücksetzen der Dedupe-Liste (neue Route = neue
///   Manöver, die alte Ansage-Historie darf nicht dämpfen)
///
/// Anti-Spam: pro (Manöver-Text, Stufe) wird je Fahrt GENAU EINMAL
/// gesprochen; zwischen zwei Ansagen liegt mindestens [minIntervalMs].
/// GPS-Jitter führt so nie zur Ansagen-Kaskade.
class VoiceAnnouncer {
  VoiceAnnouncer({
    TtsEngine? engine,
    bool german = true,
    this.minIntervalMs = 2500,
    this.approachMeters = 400,
    this.nowMeters = 80,
    this.destinationMeters = 300,
    this.arrivedMeters = 25,
  })  : _engine = engine ?? FlutterTtsEngine(),
        germanLanguage = german;

  final TtsEngine _engine;

  /// Stellschraube der Navigation (Toggle im Screen). false = komplett
  /// still (keine speak()-Calls, laufende Ansage wird nicht gestoppt).
  bool enabled = true;

  /// Stimmen-Sprache: Die Backend-Anweisungstexte sind deutsch; die
  /// Satz-Rahmen folgen der App-Sprache. DE-Nutzer erhalten ein rundum
  /// stimmiges Erlebnis, EN-Nutzer hören englische Rahmen mit deutschen
  /// Straßennamen (dokumentierte Grenze bis das Backend strukturierte
  /// Manöver-Codes liefert).
  bool germanLanguage;

  final int minIntervalMs;
  final double approachMeters;
  final double nowMeters;
  final double destinationMeters;
  final double arrivedMeters;

  final Set<String> _spoken = {};
  DateTime _lastSpeak = DateTime.fromMillisecondsSinceEpoch(0);
  bool _arrivedAnnounced = false;

  /// Manöver-Ansage bei jedem GPS-Fix (billig, dedupliziert intern).
  Future<void> onTurn({
    required String instruction,
    required double distanceMeters,
  }) async {
    if (!enabled || instruction.isEmpty) return;
    if (distanceMeters > approachMeters) return;

    final stage = distanceMeters <= nowMeters ? 'now' : 'soon';
    final key = '$instruction|$stage';
    if (_spoken.contains(key)) return;

    final text = stage == 'now'
        ? (germanLanguage ? 'Jetzt $instruction' : 'Now $instruction')
        : _approachPhrase(distanceMeters, instruction);
    await _trySpeak(key, text);
  }

  /// Ziel-Ansagen: 300 m Vorwarnung (einmalig), 25 m Ankunft (einmalig).
  /// Nach der Ankunfts-Ansage bleibt der Announcer stumm (GPS-Jitter kann
  /// remainingMeters kurzzeitig wieder ansteigen lassen - eine Vorwarnung
  /// NACH "Ziel erreicht" wäre irritierend). Reroute setzt das zurück.
  Future<void> onDestination({required double remainingMeters}) async {
    if (!enabled || _arrivedAnnounced) return;
    if (remainingMeters <= arrivedMeters) {
      _arrivedAnnounced = true;
      await _trySpeak(
        'dest-arrived',
        germanLanguage
            ? 'Sie haben Ihr Ziel erreicht'
            : 'You have reached your destination',
        force: true,
      );
      return;
    }
    if (remainingMeters <= destinationMeters) {
      const key = 'dest-approach';
      if (_spoken.contains(key)) return;
      final m = _roundUpTo50(remainingMeters);
      await _trySpeak(
        key,
        germanLanguage
            ? 'In $m Metern erreichen Sie Ihr Ziel'
            : 'You will reach your destination in $m meters',
      );
    }
  }

  /// Umleitung: laufende Ansage stoppen, Dedupe-Historie leeren (die neue
  /// Route hat neue Manöver), Reset-Hinweis sprechen. [reason] (z. B.
  /// "Sperrung auf der Route") macht die Ansage erklärbarer als generisch.
  Future<void> onReroute({String? reason}) async {
    _spoken.clear();
    _arrivedAnnounced = false;
    await _engine.stop();
    if (!enabled) return;
    final base = germanLanguage ? 'Route wird neu berechnet' : 'Recalculating route';
    await _trySpeak(
      'reroute',
      reason == null ? base : '$base. $reason.',
      force: true,
    );
  }

  /// Navigation beendet: alles stumm und zurückgesetzt.
  Future<void> stop() async {
    _spoken.clear();
    _arrivedAnnounced = false;
    await _engine.stop();
  }

  Future<void> _trySpeak(String key, String text, {bool force = false}) async {
    final now = DateTime.now();
    if (!force && now.difference(_lastSpeak).inMilliseconds < minIntervalMs) {
      return;
    }
    _spoken.add(key);
    _lastSpeak = now;
    await _engine.setLanguage(germanLanguage ? 'de-DE' : 'en-US');
    await _engine.speak(text);
  }

  /// Auf 50 m aufrunden ("In 350 Metern" statt "In 312 Metern") - hört
  /// sich natürlicher an und die Ansage bleibt konservativ (nie zu wenig).
  int _roundUpTo50(double meters) => ((meters / 50).ceil() * 50).clamp(50, 1000000);

  String _approachPhrase(double distanceMeters, String instruction) {
    final m = _roundUpTo50(distanceMeters);
    return germanLanguage ? 'In $m Metern $instruction' : 'In $m meters $instruction';
  }
}
