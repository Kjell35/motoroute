package de.motoroute.app

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Base64
import android.util.Log
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.nio.charset.Charset
import java.security.KeyStore
import java.util.concurrent.Executors
import javax.crypto.Cipher
import javax.crypto.spec.IvParameterSpec

/**
 * Liest und entfernt Werte aus der Ablage des früheren Plugins flutter_keychain
 * (BSD-3-Clause, Copyright 2018 Jeroen Trappers).
 *
 * Das Plugin ist nicht mehr eingebunden, weil es das Kotlin Gradle Plugin
 * anwendet und damit einer Umstellung auf built-in Kotlin im Weg steht. Für die
 * einmalige Migration der gespeicherten Sitzung braucht die App aber weiterhin
 * Zugriff auf genau diesen Speicher: eine SharedPreferences-Datei
 * "FlutterKeychain" mit AES/CBC-verschlüsselten Werten, deren AES-Schlüssel per
 * RSA aus dem AndroidKeyStore verpackt ist (Alias "<packageName>.FlutterKeychain").
 *
 * Gelesen wird ausschließlich - geschrieben nur, um den alten Eintrag nach
 * erfolgreicher Übernahme zu entfernen.
 */
object LegacyKeychainChannel {
    private const val CHANNEL = "motoroute/legacy_keychain"
    private const val PREFS_NAME = "FlutterKeychain"
    private const val WRAPPED_AES_KEY_ITEM = "W0n5hlJtrAH0K8mIreDGxtG"
    private const val KEY_ALIAS_SUFFIX = ".FlutterKeychain"
    private const val IV_SIZE = 16
    private const val TAG = "LegacyKeychain"

    private val worker = Executors.newSingleThreadExecutor()
    private val mainThread = Handler(Looper.getMainLooper())

    fun attach(context: Context, messenger: BinaryMessenger) {
        val appContext = context.applicationContext
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            val key = call.argument<String>("key")
            if (key == null) {
                result.error(TAG, "key fehlt", null)
                return@setMethodCallHandler
            }
            worker.execute {
                when (call.method) {
                    "get" -> {
                        val value = runCatching { read(appContext, key) }
                            .onFailure { Log.w(TAG, "Lesen fehlgeschlagen", it) }
                            .getOrNull()
                        mainThread.post { result.success(value) }
                    }
                    "remove" -> {
                        runCatching { remove(appContext, key) }
                            .onFailure { Log.w(TAG, "Entfernen fehlgeschlagen", it) }
                        mainThread.post { result.success(null) }
                    }
                    else -> mainThread.post { result.notImplemented() }
                }
            }
        }
    }

    private fun read(context: Context, key: String): String? {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val encrypted = prefs.getString(key, null) ?: return null
        val wrappedKey = prefs.getString(WRAPPED_AES_KEY_ITEM, null) ?: return null

        val combined = Base64.decode(encrypted, Base64.DEFAULT)
        if (combined.size <= IV_SIZE) return null
        val iv = combined.copyOfRange(0, IV_SIZE)
        val payload = combined.copyOfRange(IV_SIZE, combined.size)

        val keyStore = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        val privateKey = keyStore.getKey(context.packageName + KEY_ALIAS_SUFFIX, null)
            ?: return null

        val rsa = Cipher.getInstance("RSA/ECB/PKCS1Padding")
        rsa.init(Cipher.UNWRAP_MODE, privateKey)
        val aesKey = rsa.unwrap(
            Base64.decode(wrappedKey, Base64.DEFAULT),
            "AES",
            Cipher.SECRET_KEY,
        )

        val aes = Cipher.getInstance("AES/CBC/PKCS7Padding")
        aes.init(Cipher.DECRYPT_MODE, aesKey, IvParameterSpec(iv))
        return String(aes.doFinal(payload), Charset.forName("UTF-8"))
    }

    private fun remove(context: Context, key: String) {
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .remove(key)
            .commit()
    }
}
