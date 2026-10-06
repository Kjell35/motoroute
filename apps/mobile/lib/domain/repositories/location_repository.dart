import '../value_objects/app_location.dart';

/// Domain-Port (docs/02-architecture.md §2): Zugriff auf Positions-Stream.
/// Infrastruktur implementiert diesen Port (geolocator-Adapter).
abstract interface class LocationRepository {
  /// Liefert einen Broadcast-fähigen Positions-Stream.
  /// Implementierung sollte Energy-Settings beachten (docs/08-energy-saving.md).
  Stream<AppLocation> positionStream();

  /// Letzter bekannter Fix (z. B. für Kamera-Init), oder null.
  Future<AppLocation?> lastKnown();

  /// Ist die Location-Berechtigung erteilt?
  Future<bool> isGranted();

  /// Fordert While-In-Use-Berechtigung an (Pre-Prompt liegt in der UI).
  Future<bool> requestPermission();

  /// Ist der Standort-Dienst (GPS) systemweit aktiviert?
  Future<bool> isServiceEnabled();

  /// Fordert zum Aktivieren der Standortdienste auf.
  Future<bool> openLocationSettings();

  /// Kurze Beschreibung für UI-Status (ohne OS-Details).
  Future<LocationGrant> resolveGrant();
}

enum LocationGrant { granted, denied, deniedForever, serviceDisabled, undetermined }
