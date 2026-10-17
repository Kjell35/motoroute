plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Eigener applicationId (de.motoroute.app) statt des flutter-create-
// Defaults (de.motoroute.motoroute_app): WICHTIG für Updates - sobald
// die erste APK installiert ist, MUSS die ID für alle späteren Updates
// gleich bleiben, sonst lässt sich die neue APK nicht über die alte
// installieren (Datenverlust/Deinstallation). Die ID wird ab dem ersten
// Release nie wieder geändert.
val appId = "de.motoroute.app"

// versionCode/versionName kommen aus der pubspec.yaml (version: 0.1.0+1)
// - die Flutter-Gradle-Tools reichen sie als flutter.versionCode/
// flutter.versionName durch. EINE Quelle der Wahrheit für App- und
// Android-Versionierung.

// Release-Signierung über Umgebungsvariablen (in CI: GitHub Secrets).
// Keystore und Passwörter landen NIE im Repository; lokal kann jeder
// Build ohne Keystore laufen (Fallback: Debug-Signierung, nur für
// Entwicklung, nicht für Update-Installationen auf dem Handy).
// WICHTIG: Eigene, kollisionsfreie Namen - Variablen, die genauso heißen
// wie die SigningConfig-Eigenschaften (keyPassword, keyAlias), würden im
// create("release")-Block auf die (noch leere) Eigenschaft selbst auflösen.
val keystoreFilePath = System.getenv("MOTOROUTE_KEYSTORE_PATH")
val keystorePasswordValue = System.getenv("MOTOROUTE_KEYSTORE_PASSWORD")
val keyAliasValue = System.getenv("MOTOROUTE_KEY_ALIAS")
val keyPasswordValue = System.getenv("MOTOROUTE_KEY_PASSWORD")
val hasReleaseKeystore = !keystoreFilePath.isNullOrBlank() &&
        !keystorePasswordValue.isNullOrBlank() &&
        !keyAliasValue.isNullOrBlank() &&
        !keyPasswordValue.isNullOrBlank()

android {
    namespace = appId
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = appId
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseKeystore) {
            create("release") {
                storeFile = file(keystoreFilePath!!)
                storePassword = keystorePasswordValue
                keyAlias = keyAliasValue
                keyPassword = keyPasswordValue
            }
        }
    }

    buildTypes {
        release {
            // Signiert, wenn Keystore-Umgebungsvariablen gesetzt sind
            // (CI-Release); sonst Debug-Keys, damit `flutter run --release`
            // ohne Setup funktioniert. Diese Fallback-APK ist für Tests -
            // sie installiert NICHT über eine früher signierte Version
            // (Signaturwechsel = Deinstallation nötig), das ist bewusst
            // so und wird in docs/ANDROID_INSTALL.md erklärt.
            signingConfig = if (hasReleaseKeystore) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
            // Release-Optimierung: R8 shrink + Ressourcen-Minimierung.
            // Flutter-Default wäre isMinifyEnabled=false; kleiner APK
            // und schnellerer Start, Regeln schützen Flutter-Plugins.
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
        debug {
            // Debug-Builds tragen die Suffix-ID: Sie können PARALLEL zur
            // Release-/Debug-APK von GitHub installiert werden, ohne die
            // installierte Version zu ersetzen (kein Risiko für App-Daten).
            applicationIdSuffix = ".debug"
            versionNameSuffix = "-debug"
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
