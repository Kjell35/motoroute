import 'package:geolocator/geolocator.dart';
import 'package:motoroute_app/features/settings/energy_saver.dart'
    show LocationAccuracyPreset, LocationTuning;

/// Kapselt Geolocator komplett - Presentation-Code fragt nie direkt
/// bei geolocator nach, damit z. B. der Energiesparmodus (Phase 1/2
/// Abschnitt 12) an EINER Stelle die Abfrage-Genauigkeit/-Frequenz
/// drosseln kann, statt an jeder Call-Site im UI-Code.
class LocationRepository {
  /// Stream mit Tuning-Parametern - der Energiesparmodus bestimmt
  /// Genauigkeit (high/medium/low) und Distanz-Filter. Ein WECHSEL der
  /// Parameter erfordert einen Neuaufbau des Streams; der Navigation-
  /// Controller reabonniert, wenn der Modus wechselt.
  Stream<Position> watchPosition({LocationTuning? tuning}) {
    final accuracy = switch (tuning?.accuracy ?? LocationAccuracyPreset.high) {
      LocationAccuracyPreset.high => LocationAccuracy.high,
      LocationAccuracyPreset.medium => LocationAccuracy.medium,
      LocationAccuracyPreset.low => LocationAccuracy.low,
    };
    return Geolocator.getPositionStream(
      locationSettings: LocationSettings(
        accuracy: accuracy,
        distanceFilter: tuning?.distanceFilterMeters ?? 3,
        // timeLimit als Sicherheitsnetz: liefert GPS keine Position
        // (z. B. Tunnel), fließt kein Update - der Screen zeigt dann
        // weiterhin den letzten Stand.
        timeLimit: const Duration(seconds: 30),
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
