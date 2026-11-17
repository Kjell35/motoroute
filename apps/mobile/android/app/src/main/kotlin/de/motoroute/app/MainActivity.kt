package de.motoroute.app

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
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

    override fun onDestroy() {
        ttsSession?.shutdown()
        ttsSession = null
        super.onDestroy()
    }
}
