plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release-Signierung über Umgebungsvariablen (in CI: GitHub Secrets).
// Keystore und Passwörter landen NIE im Repository; ohne gesetzte Variablen
// fällt der Build auf Debug-Signierung zurück (nur für Tests - eine so
// signierte APK lässt sich nicht über eine mit Upload-Key installieren).
val keystoreFilePath = System.getenv("MOTOROUTE_KEYSTORE_PATH")
val keystorePasswordValue = System.getenv("MOTOROUTE_KEYSTORE_PASSWORD")
val keyAliasValue = System.getenv("MOTOROUTE_KEY_ALIAS")
val keyPasswordValue = System.getenv("MOTOROUTE_KEY_PASSWORD")
val keystoreFile = keystoreFilePath?.takeIf { it.isNotBlank() }?.let { file(it) }
// Ein gesetzter, aber falscher Pfad darf NICHT still auf Debug-Signierung
// zurückfallen: sonst verteilt die CI unbemerkt APKs, die sich nicht über
// eine signierte Version installieren lassen.
if (keystoreFile != null && !keystoreFile.exists()) {
    throw GradleException("MOTOROUTE_KEYSTORE_PATH zeigt auf keine Datei: $keystoreFile")
}
val hasReleaseKeystore = keystoreFile != null &&
        !keystorePasswordValue.isNullOrBlank() &&
        !keyAliasValue.isNullOrBlank() &&
        !keyPasswordValue.isNullOrBlank()

android {
    namespace = "de.motoroute.motoroute_next"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // Separate application ID keeps the rebuild installable beside the current app.
        applicationId = "de.motoroute.app.next"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseKeystore) {
            create("release") {
                storeFile = keystoreFile
                storePassword = keystorePasswordValue
                keyAlias = keyAliasValue
                keyPassword = keyPasswordValue
            }
        }
    }

    buildTypes {
        release {
            // Echter Upload-Key, sobald die Umgebungsvariablen gesetzt sind;
            // sonst Debug-Signierung, damit lokale Release-Builds ohne
            // Keystore laufen (nicht für Verteilung/Updates geeignet).
            signingConfig = if (hasReleaseKeystore) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
