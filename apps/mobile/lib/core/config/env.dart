import 'package:flutter/foundation.dart' show kDebugMode;

/// Environment-Konfiguration via `--dart-define` – kein Key im Code.
///
/// Beispiel (lokal):
/// ```
/// flutter run \
///   --dart-define=MOTOROUTE_API_BASE_URL=http://10.0.2.2:8000 \
///   --dart-define=MOTOROUTE_MAP_STYLE=midnight-asphalt
/// ```
class Env {
  const Env._();

  /// Basis-URL des MotoRoute-Backends.
  /// Default: lokale Entwicklung (Android-Emulator erreicht Host via 10.0.2.2).
  static const String apiBaseUrl = String.fromEnvironment(
    'MOTOROUTE_API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8000',
  );

  /// Kartenstil-Asset ohne Pfad/Endung.
  static const String mapStyle = String.fromEnvironment(
    'MOTOROUTE_MAP_STYLE',
    defaultValue: 'midnight-asphalt',
  );

  /// Wird beim Start validiert (fail fast, siehe docs/10-dev-process.md).
  static void validate() {
    // Aktuell gibt es keine Pflicht-Keys (Zero-Budget-Stack, siehe docs/11-costs.md).
    // Sobald Pflichtwerte dazukommen (z. B. Client-Token), hier hart prüfen:
    // assert(apiBaseUrl.startsWith('https://') || kDebugMode, ...);
  }
}
