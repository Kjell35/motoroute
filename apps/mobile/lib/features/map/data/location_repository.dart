import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:motoroute_app/features/settings/energy_saver.dart'
    show LocationAccuracyPreset, LocationTuning;

/// Injektionspunkt (Tests überschreiben diesen Provider mit einem Mock).
final locationRepositoryProvider = Provider<LocationRepository>((ref) {
  return LocationRepository();
});

/// Kapselt Geolocator komplett - Presentation-Code fragt nie direkt
/// bei geolocator nach, damit z. B. der Energiesparmodus (Phase 1/2
/// Abschnitt 12) an EINER Stelle die Abfrage-Genauigkeit/-Frequenz
/// drosseln kann, statt an jeder Call-Site im UI-Code.
class LocationRepository {
  /// Stream mit Tuning-Parametern - der Energiesparmodus bestimmt
  /// Genauigkeit (high/medium/low) und Distanz-Filter. Ein WECHSEL der
  /// Parameter erfordert einen Neuaufbau des Streams; der Navigation-
  /// Controller reabonniert, wenn der Modus wechselt.
  /// [backgroundNavigation] startet den Android-Foreground-Service, damit
  /// die Navigation bei ausgeschaltetem Display weiterläuft. Für reines
  /// Karten-Browsing bleibt er aus - kein Dauer-Notification ohne Fahrt.
  Stream<Position> watchPosition({
    LocationTuning? tuning,
    bool backgroundNavigation = false,
    String notificationTitle = 'MotoRoute navigiert',
    String notificationText = 'Standort wird für die Navigation genutzt.',
  }) {
    final accuracy = switch (tuning?.accuracy ?? LocationAccuracyPreset.high) {
      LocationAccuracyPreset.high => LocationAccuracy.high,
      LocationAccuracyPreset.medium => LocationAccuracy.medium,
      LocationAccuracyPreset.low => LocationAccuracy.low,
    };
    return Geolocator.getPositionStream(
      locationSettings: AndroidSettings(
        accuracy: accuracy,
        distanceFilter: tuning?.distanceFilterMeters ?? 3,
        // timeLimit als Sicherheitsnetz: liefert GPS keine Position
        // (z. B. Tunnel), fließt kein Update - der Screen zeigt dann
        // weiterhin den letzten Stand.
        timeLimit: const Duration(seconds: 30),
        // Nur während der Navigation: Android drosselt Standort-Updates im
        // Hintergrund, ohne Foreground-Service verstummt die Ansage, sobald
        // das Display ausgeht. geolocator bringt den Dienst selbst mit
        // (`foregroundServiceType="location"`), der Wakelock hält die CPU
        // wach, damit Fixes nicht gesammelt nachgeliefert werden.
        foregroundNotificationConfig: backgroundNavigation
            ? ForegroundNotificationConfig(
                notificationTitle: notificationTitle,
                notificationText: notificationText,
                notificationChannelName: 'Navigation',
                enableWakeLock: true,
                setOngoing: true,
              )
            : null,
      ),
    );
  }

  Future<bool> ensurePermission() async {
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    return permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse;
  }

  Future<Position> getCurrentPosition() {
    return Geolocator.getCurrentPosition();
  }
}
