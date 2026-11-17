package de.motoroute.app

import android.content.Context
import android.speech.tts.TextToSpeech
import android.util.Log
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
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
 *
 * Jede [Session] besitzt ihren eigenen Kanal und ihre eigene Engine. Deshalb
 * braucht es keine globale Ablage: shutdown() einer alten Activity spricht nur
 * ihren eigenen Messenger an und kann eine neuere Engine nicht abschalten.
 */
object TtsChannel {
    private const val CHANNEL = "motoroute/tts"
    private const val TAG = "MotorouteTts"

    /// 0.0-1.0; 0.5 entspricht dem bisherigen Tempo der App.
    private const val SPEECH_RATE = 0.5f

    /// Hängt eine Engine an diesen Messenger. Die zurückgegebene Session hält
    /// der Aufrufer (MainActivity) fest und schaltet sie beim Zerstören ab.
    fun attach(context: Context, messenger: BinaryMessenger): Session =
        Session(context.applicationContext, messenger)

    class Session internal constructor(context: Context, messenger: BinaryMessenger) {
        private val engine = Engine(context)
        private val channel = MethodChannel(messenger, CHANNEL)

        init {
            channel.setMethodCallHandler { call, result ->
                handle(call, result, engine)
            }
        }

        /** Nur die eigene Engine; fremde Sessions bleiben unberührt. */
        fun shutdown() {
            channel.setMethodCallHandler(null)
            engine.shutdown()
        }
    }

    private fun handle(
        call: MethodCall,
        result: MethodChannel.Result,
        engine: Engine,
    ) {
        when (call.method) {
            "setLanguage" -> engine.withEngine(result) { tts ->
                val language = call.argument<String>("language")
                if (language == null) {
                    result.error(TAG, "language fehlt", null)
                    return@withEngine
                }
                val status = tts.setLanguage(Locale.forLanguageTag(language))
                tts.setSpeechRate(SPEECH_RATE)
                val supported = status != TextToSpeech.LANG_MISSING_DATA &&
                    status != TextToSpeech.LANG_NOT_SUPPORTED
                if (!supported) {
                    Log.w(TAG, "Sprache nicht verfügbar: $language")
                }
                result.success(supported)
            }
            "speak" -> engine.withEngine(result) { tts ->
                val text = call.argument<String>("text")
                if (text.isNullOrBlank()) {
                    result.success(false)
                    return@withEngine
                }
                // QUEUE_FLUSH: eine neue Ansage ersetzt die laufende, statt
                // sich zu stapeln (Fahrhinweise sind zeitkritisch). Lautstärke
                // und Tonhöhe bleiben auf der Vorgabe (1.0).
                val code = tts.speak(text, TextToSpeech.QUEUE_FLUSH, null, "motoroute")
                result.success(code == TextToSpeech.SUCCESS)
            }
            "stop" -> engine.withEngine(result) { tts ->
                tts.stop()
                result.success(true)
            }
            else -> result.notImplemented()
        }
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
        private var released = false
        private val waiting = ArrayDeque<Pair<MethodChannel.Result, (TextToSpeech) -> Unit>>()

        fun withEngine(result: MethodChannel.Result, action: (TextToSpeech) -> Unit) {
            if (released) {
                result.error(TAG, "TextToSpeech wurde freigegeben", null)
                return
            }
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
            if (released) {
                // Aktivität ist beim Warten verschwunden: Engine sofort
                // abräumen, statt sie ohne Besitzer weiterlaufen zu lassen.
                runCatching { created?.shutdown() }
                tts = null
                queued.forEach { (result, _) ->
                    runCatching {
                        result.error(TAG, "TextToSpeech wurde freigegeben", null)
                    }
                }
                return
            }
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

        /**
         * Mehrfach aufrufbar. Wartende Aufrufe werden beantwortet, statt hängen
         * zu bleiben; stop()/shutdown() einer halb initialisierten Engine kann
         * werfen und darf beim Activity-Abbau nicht die App mitnehmen.
         */
        fun shutdown() {
            released = true
            val queued = waiting.toList()
            waiting.clear()
            queued.forEach { (result, _) ->
                runCatching { result.error(TAG, "TextToSpeech wurde freigegeben", null) }
            }
            runCatching { tts?.stop() }
            runCatching { tts?.shutdown() }
            tts = null
        }
    }
}
