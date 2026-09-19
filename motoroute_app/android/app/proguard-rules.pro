# R8-Regeln für MotoRoute (Release-Minify).
#
# Flutter-Code selbst braucht keine Regeln; hier stehen Ausnahmen für
# Plugins/Bibliotheken, die Reflection nutzen und sonst von R8
# beschnitten würden.

# Flutter-Embedding & Plugin-Registrant werden per Reflection geladen.
-keep class io.flutter.** { *; }
-keep class de.motoroute.app.** { *; }

# json_serializable: generierte FromJson/ToJson werden per Konvention
# referenziert - Namen müssen bleiben.
-keep class *$$JsonSerializable { *; }
-keepnames class * implements java.io.Serializable

# Play-Store-Kopplung bewusst ABWÄHLEN: MotoRoute ist bewusst unabhängig
# vom Play Store (Sideload-APK, siehe docs/INSTALL.md). Die Flutter-Klasse
# FlutterPlayStoreSplitApplication referenziert Google Play Core (Split-
# Install) - ohne Play Core im Classpath warnt R8 über fehlende Klassen.
# Diese werden NIE zur Laufzeit erreicht (kein Deferred-Components-Feature,
# kein Play-Store-Install), also sind sie sicher zu ignorieren.
-dontwarn com.google.android.play.core.**

# Google-optional-Bibliotheken (web_socket_channel & Co. ziehen teils
# okay-http/conscrypt-Hinweise) schaden nicht, wenn sie wegfallen:
-dontwarn org.conscrypt.**
-dontwarn org.bouncycastle.**
-dontwarn org.openjsse.**
