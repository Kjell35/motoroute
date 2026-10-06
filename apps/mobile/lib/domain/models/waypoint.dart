import 'place.dart';

/// Ein Halt einer geplanten Route. Die Reihenfolge ist Teil des Modells.
class Waypoint {
  const Waypoint({
    required this.id,
    required this.label,
    required this.latitude,
    required this.longitude,
    this.detail,
  });

  final String id;
  final String label;
  final String? detail;
  final double latitude;
  final double longitude;

  factory Waypoint.fromPlace(Place place) => Waypoint(
        id: place.id,
        label: place.label,
        detail: place.detail,
        latitude: place.latitude,
        longitude: place.longitude,
      );
}
