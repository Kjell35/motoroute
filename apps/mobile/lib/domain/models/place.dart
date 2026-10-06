/// Ein normalisiertes Geocoding-Ergebnis der MotoRoute-API.
class Place {
  const Place({
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

  factory Place.fromJson(Map<String, dynamic> json) => Place(
        id: json['id'] as String,
        label: json['label'] as String,
        detail: json['detail'] as String?,
        latitude: (json['lat'] as num).toDouble(),
        longitude: (json['lon'] as num).toDouble(),
      );
}
