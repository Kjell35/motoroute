package de.motoroute.app

import android.content.Context
import android.os.Bundle
import android.speech.tts.TextToSpeech
import android.util.Log
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.util.Locale

/**
 * Sprachansage über Androids eigene TextToSpeech-Engine.
 *
 * Ersetzt das Plugin flutter_tts, das das Kotlin Gradle Plugin anwendet und
 * damit `android.builtInKotlin=true` blockiert. Mehr als setLanguage, speak
 * und stop braucht die Navigation nicht.
 *
 * Fällt die Engine aus (kein Sprachpaket, Engine fehlt), antwortet der Kanal
 * mit `false` bzw. einem Fehler - die Dart-Seite meldet das als `voice.tts`
 * und schweigt weiter. TTS darf die Navigation nie abbrechen.
 */
object TtsChannel {
    private const val CHANNEL = "motoroute/tts"
    private const val TAG = "MotorouteTts"

    /// 0.0-1.0; 0.5 entspricht dem bisherigen Tempo der App.
    private const val SPEECH_RATE = 0.5f

    private var engine: Engine? = null

    fun attach(context: Context, messenger: BinaryMessenger) {
        val current = Engine(context.applicationContext)
        engine = current
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "setLanguage" -> current.withEngine(result) { tts ->
                    val language = call.argument<String>("language")
                    if (language == null) {
                        result.error(TAG, "language fehlt", null)
                        return@withEngine
                    }
                    val status = tts.setLanguage(Locale.forLanguageTag(language))
                    tts.setSpeechRate(SPEECH_RATE)
                    tts.setPitch(1.0f)
                    val supported = status != TextToSpeech.LANG_MISSING_DATA &&
                        status != TextToSpeech.LANG_NOT_SUPPORTED
                    if (!supported) {
                        Log.w(TAG, "Sprache nicht verfügbar: $language")
                    }
                    result.success(supported)
                }
                "speak" -> current.withEngine(result) { tts ->
                    val text = call.argument<String>("text")
                    if (text.isNullOrBlank()) {
                        result.success(false)
                        return@withEngine
                    }
                    // QUEUE_FLUSH: eine neue Ansage ersetzt die laufende,
                    // statt sich zu stapeln (Fahrhinweise sind zeitkritisch).
                    // TextToSpeech kennt kein setVolume(); die Lautstärke
                    // gehört zu jedem Ausspruch.
                    val params = Bundle().apply {
                        putFloat(TextToSpeech.Engine.KEY_PARAM_VOLUME, 1.0f)
                    }
                    val code = tts.speak(text, TextToSpeech.QUEUE_FLUSH, params, "motoroute")
                    result.success(code == TextToSpeech.SUCCESS)
                }
                "stop" -> current.withEngine(result) { tts ->
                    tts.stop()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    /// Beim Verlassen der Activity die Engine freigeben; ein späteres attach()
    /// baut eine neue auf.
    fun shutdown() {
        engine?.shutdown()
        engine = null
    }

    /**
     * Hält die TextToSpeech-Engine und puffert Aufrufe, bis die asynchrone
     * Initialisierung durch ist. Alle Methoden laufen auf dem Main-Thread:
     * TextToSpeech meldet die Initialisierung auf dem Looper des Threads
     * zurück, auf dem sie erzeugt wurde.
     */
    private class Engine(private val appContext: Context) {
        private var tts: TextToSpeech? = null
        private var failed = false
        private val waiting = ArrayDeque<Pair<MethodChannel.Result, (TextToSpeech) -> Unit>>()

        fun withEngine(result: MethodChannel.Result, action: (TextToSpeech) -> Unit) {
            val ready = tts
            if (ready != null) {
                action(ready)
                return
            }
            if (failed) {
                result.error(TAG, "TextToSpeech nicht verfügbar", null)
                return
            }
            waiting.addLast(result to action)
            // Nur der erste Aufruf stößt die Initialisierung an; alle weiteren
            // warten in der Schlange.
            if (waiting.size > 1) return
            val created = TextToSpeech(appContext) { status -> onInitialized(status) }
            // Der Callback kommt über den Looper, also nach dieser Zuweisung.
            tts = created
        }

        private fun onInitialized(status: Int) {
            val created = tts
            val queued = waiting.toList()
            waiting.clear()
            if (status != TextToSpeech.SUCCESS || created == null) {
                Log.w(TAG, "Initialisierung fehlgeschlagen (Status $status)")
                failed = true
                tts = null
                queued.forEach { (result, _) ->
                    result.error(TAG, "TextToSpeech nicht verfügbar", null)
                }
                return
            }
            queued.forEach { (_, action) -> action(created) }
        }

        fun shutdown() {
            waiting.clear()
            tts?.stop()
            tts?.shutdown()
            tts = null
        }
    }
}
