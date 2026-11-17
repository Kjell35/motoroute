package de.motoroute.app

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Nur für die einmalige Übernahme des Sitzungs-Tokens aus der alten
        // flutter_keychain-Ablage; ohne Handler wäre die Migration ein No-op.
        LegacyKeychainChannel.attach(
            this,
            flutterEngine.dartExecutor.binaryMessenger,
        )
        // Eigene Sprachansage statt flutter_tts (KGP-Blocker).
        TtsChannel.attach(this, flutterEngine.dartExecutor.binaryMessenger)
    }

    override fun onDestroy() {
        TtsChannel.shutdown()
        super.onDestroy()
    }
}
