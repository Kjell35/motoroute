import 'package:motoroute_app/core/constants/route_enums.dart';

/// Domänen-Modelle, gespiegelt zu den Backend-Entitäten
/// (motoroute_api/src/modules/routing/entities/route.entity.ts) -
/// siehe Datenmodelle Phase 1/2 Teil E.

class Waypoint {
  final double lat;
  final double lng;
  final String? label;

  const Waypoint({required this.lat, required this.lng, this.label});

  Map<String, dynamic> toJson() => {
        'lat': lat,
        'lng': lng,
        if (label != null) 'label': label,
      };
}

class RoutePreference {
  final RouteStyle style;
  final VehicleType vehicleType;
  final Set<AvoidOption> avoid;

  const RoutePreference({
    required this.style,
    required this.vehicleType,
    this.avoid = const {},
  });

  Map<String, dynamic> toJson() => {
        'style': style.apiValue,
        'vehicleType': vehicleType.apiValue,
        'avoid': avoid.map((a) => a.apiValue).toList(),
      };
}

class RouteSegment {
  final String instruction;
  final double distanceMeters;
  final double durationSeconds;

  const RouteSegment({
    required this.instruction,
    required this.distanceMeters,
    required this.durationSeconds,
  });

  factory RouteSegment.fromJson(Map<String, dynamic> json) => RouteSegment(
        instruction: json['instruction'] as String,
        distanceMeters: (json['distanceMeters'] as num).toDouble(),
        durationSeconds: (json['durationSeconds'] as num).toDouble(),
      );
}

class NavigationRoute {
  final String id;
  final List<Waypoint> waypoints;
  final RoutePreference preference;
  final List<List<double>> geometry; // [lng, lat] Paare, wie vom Backend
  final double distanceMeters;
  final double durationSeconds;
  final List<RouteSegment> segments;

  const NavigationRoute({
    required this.id,
    required this.waypoints,
    required this.preference,
    required this.geometry,
    required this.distanceMeters,
    required this.durationSeconds,
    required this.segments,
  });

  factory NavigationRoute.fromJson(
    Map<String, dynamic> json, {
    required RoutePreference requestedPreference,
    required List<Waypoint> requestedWaypoints,
  }) {
    return NavigationRoute(
      id: json['id'] as String,
      waypoints: requestedWaypoints,
      preference: requestedPreference,
      geometry: (json['geometry'] as List)
          .map<List<double>>((p) => (p as List).map((v) => (v as num).toDouble()).toList())
          .toList(),
      distanceMeters: (json['distanceMeters'] as num).toDouble(),
      durationSeconds: (json['durationSeconds'] as num).toDouble(),
      segments: (json['segments'] as List)
          .map((s) => RouteSegment.fromJson(s as Map<String, dynamic>))
          .toList(),
    );
  }
}
