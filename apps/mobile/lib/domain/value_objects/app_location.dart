import 'dart:math' as math;

/// Domain-Value-Object: GPS-Position mit optionaler Richtung/Geschwindigkeit.
/// Framework-frei (kein Flutter-Import) – Unit-Tests ohne Emulator möglich.
class AppLocation {
  const AppLocation({
    required this.latitude,
    required this.longitude,
    this.headingDegrees,
    this.speedMps,
    this.timestamp,
  });

  /// WGS84-Breite in Grad.
  final double latitude;

  /// WGS84-Länge in Grad.
  final double longitude;

  /// Bewegungsrichtung in Grad [0, 360) – null, wenn unbekannt/stehend.
  final double? headingDegrees;

  /// Geschwindigkeit in m/s – null, wenn unbekannt.
  final double? speedMps;

  final DateTime? timestamp;

  /// Distanz² (lokale flache Projektion, Meter) – für Schwellwerte ohne Wurzel.
  double squaredPlanarDistanceMeters(AppLocation other) {
    const double mPerDegLat = 111320.0;
    final double mPerDegLon =
        111320.0 * math.cos(latitude * math.pi / 180.0);
    final double dx = (longitude - other.longitude) * mPerDegLon;
    final double dy = (latitude - other.latitude) * mPerDegLat;
    return dx * dx + dy * dy;
  }

  /// Haversine-Distanz in Metern.
  double distanceToMeters(AppLocation other) {
    const double r = 6371000.0;
    double rad(double d) => d * math.pi / 180.0;
    final double dLat = rad(other.latitude - latitude);
    final double dLon = rad(other.longitude - longitude);
    final double a = math.pow(math.sin(dLat / 2), 2) +
        math.cos(rad(latitude)) *
            math.cos(rad(other.latitude)) *
            math.pow(math.sin(dLon / 2), 2);
    final double c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return r * c;
  }

  AppLocation copyWith({
    double? latitude,
    double? longitude,
    double? headingDegrees,
    double? speedMps,
  }) {
    return AppLocation(
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      headingDegrees: headingDegrees ?? this.headingDegrees,
      speedMps: speedMps ?? this.speedMps,
      timestamp: timestamp,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is AppLocation &&
      other.latitude == latitude &&
      other.longitude == longitude;

  @override
  int get hashCode => Object.hash(latitude, longitude);
}
