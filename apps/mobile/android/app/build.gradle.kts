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
val keystoreValues = listOf(keystoreFilePath, keystorePasswordValue, keyAliasValue, keyPasswordValue)
val keystoreParts = keystoreValues.count { !it.isNullOrBlank() }
// Eine halb gesetzte Signierung darf NICHT still auf Debug-Keys zurückfallen:
// sonst entstehen unbemerkt APKs, die sich nicht über eine signierte Version
// installieren lassen.
if (keystoreParts != 0 && keystoreParts != keystoreValues.size) {
    throw GradleException(
        "Release-Signierung ist unvollständig: MOTOROUTE_KEYSTORE_PATH, " +
            "MOTOROUTE_KEYSTORE_PASSWORD, MOTOROUTE_KEY_ALIAS und " +
            "MOTOROUTE_KEY_PASSWORD müssen alle gesetzt sein - oder keiner.",
    )
}
val keystoreFile = keystoreFilePath?.takeIf { it.isNotBlank() }?.let { file(it) }
if (keystoreFile != null && !keystoreFile.exists()) {
    throw GradleException("MOTOROUTE_KEYSTORE_PATH zeigt auf keine Datei: $keystoreFile")
}
val hasReleaseKeystore = keystoreParts == keystoreValues.size

android {
    namespace = appId
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    // BuildConfig traegt das Probe-Flag (siehe CRASH_PROBE unten).
    buildFeatures {
        buildConfig = true
    }

    defaultConfig {
        applicationId = appId
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        // Nur fuer den R8-Mapping-Beweis: crashProbe=true in
        // android/gradle.properties (oder -PcrashProbe=true) baut eine Sonde
        // ein, die auf ein Intent-Extra hin abstuerzt. Im Normalbau steht hier
        // false, und R8 entfernt den Zweig samt CrashProbe als toten Code.
        buildConfigField(
            "boolean",
            "CRASH_PROBE",
            ((project.findProperty("crashProbe") as String?)?.toBoolean() ?: false).toString(),
        )
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
            // Signiert, wenn Keystore-Umgebungsvariablen gesetzt sind
            // (CI-Release, siehe .github/workflows/android-release.yml);
            // sonst Debug-Keys, damit `flutter run --release` ohne Setup
            // funktioniert. Die Fallback-APK ist nur für lokale Tests -
            // sie lässt sich NICHT über eine Release-APK installieren
            // (anderer Signaturschlüssel = Deinstallation nötig).
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
            // Probe-Regeln nur im Probe-Build: im Normalbau bleibt die
            // Sonde toter Code und wird entfernt.
            if ((project.findProperty("crashProbe") as String?)?.toBoolean() == true) {
                proguardFile("probe-rules.pro")
            }
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
