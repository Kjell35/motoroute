package de.motoroute.app

import android.os.Bundle
import de.motoroute.probe.CrashProbe
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    /**
     * Absichtlicher Absturz fuer den R8-Mapping-Beweis: nur im Probe-Build
     * (BuildConfig.CRASH_PROBE) und nur, wenn der Start das Extra setzt.
     * Im Normalbau ist die Bedingung konstant false.
     */
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (BuildConfig.CRASH_PROBE &&
            intent?.getBooleanExtra(EXTRA_CRASH_PROBE, false) == true
        ) {
            CrashProbe.trigger()
        }
    }

    /**
     * Gehört zu genau dieser Activity; onDestroy() schaltet nur diese Engine
     * ab, nicht die einer bereits neu erzeugten Activity.
     */
    private var ttsSession: TtsChannel.Session? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Nur für die einmalige Übernahme des Sitzungs-Tokens aus der alten
        // flutter_keychain-Ablage; ohne Handler wäre die Migration ein No-op.
        LegacyKeychainChannel.attach(
            this,
            flutterEngine.dartExecutor.binaryMessenger,
        )
        // Eigene Sprachansage statt flutter_tts (KGP-Blocker).
        ttsSession = TtsChannel.attach(
            this,
            flutterEngine.dartExecutor.binaryMessenger,
        )
    }

    private companion object {
        const val EXTRA_CRASH_PROBE = "crash_probe"
    }

    override fun onDestroy() {
        ttsSession?.shutdown()
        ttsSession = null
        super.onDestroy()
    }
}
