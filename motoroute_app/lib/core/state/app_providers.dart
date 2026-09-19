import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:motoroute_app/core/constants/route_enums.dart';
import 'package:motoroute_app/core/utils/formatters.dart';
import 'package:motoroute_app/features/routing/domain/route_entities.dart';

/// Globale Sitzungs-Einstellungen. Persistierung (shared_preferences)
/// kommt mit dem Auth-/Profil-Feature - solange ist der In-Memory-State
/// bewusst genug, da Einstellungen ohnehin nur pro Session gelten.
final vehicleTypeProvider =
    StateProvider<VehicleType>((ref) => VehicleType.motorcycle);

final distanceUnitProvider =
    StateProvider<DistanceUnit>((ref) => DistanceUnit.kilometers);

/// Aktive POI-Kategorien auf der Karte (Screen 10): Ein Tap schaltet
/// sofort um - der State ist Quelle der Wahrheit für Layer UND Auswahl-Sheet.
final activePoiCategoriesProvider =
    StateProvider<Set<PoiCategory>>((ref) => {PoiCategory.fuel});

/// Ergebnis der zuletzt berechneten Route - wird zwischen
/// Fahrstil-Auswahl, Routenübersicht und aktiver Navigation geteilt.
final activeRouteProvider = StateProvider<ComputedRoute?>((ref) => null);

/// Wegpunkte der aktuellen Planung (Start -> Zwischenziele -> Ziel).
final waypointListProvider = StateProvider<List<Waypoint>>((ref) => const []);

enum PoiCategory {
  fuel,
  motoHotel,
  bikerMeetup,
  campsite,
  iceCream,
  speedCamera,
  // Biker-POI-Dienst-Kategorien (motoroute_poi_service, TomTom-Kuratierung):
  restaurant,
  pub,
  snack,
}

extension PoiCategoryApi on PoiCategory {
  String get apiValue => switch (this) {
        PoiCategory.fuel => 'FUEL',
        PoiCategory.motoHotel => 'MOTO_HOTEL',
        PoiCategory.bikerMeetup => 'BIKER_MEETUP',
        PoiCategory.campsite => 'CAMPSITE',
        PoiCategory.iceCream => 'ICE_CREAM',
        PoiCategory.speedCamera => 'SPEED_CAMERA',
        PoiCategory.restaurant => 'RESTAURANT',
        PoiCategory.pub => 'PUB',
        PoiCategory.snack => 'SNACK',
      };

  String get label => switch (this) {
        PoiCategory.fuel => 'Tankstellen',
        PoiCategory.motoHotel => 'Motorradhotels',
        PoiCategory.bikerMeetup => 'Biker-Treffs',
        PoiCategory.campsite => 'Campingplätze',
        PoiCategory.iceCream => 'Eisdielen',
        PoiCategory.speedCamera => 'Blitzer',
        PoiCategory.restaurant => 'Restaurants',
        PoiCategory.pub => 'Kneipen & Bars',
        PoiCategory.snack => 'Imbisse',
      };

  /// Kategorien des Biker-POI-Dienstes (Delta-Sync-Filter beim BFF).
  /// Diese Liste ist die Brücke zwischen dem TomTom-Kuratierungs-Dienst
  /// und dem OSM-Layer: beide laufen in denselben PoiCategory-Namespace.
  static const bikerServiceCategories = {
    PoiCategory.restaurant,
    PoiCategory.pub,
    PoiCategory.snack,
    PoiCategory.bikerMeetup,
    PoiCategory.motoHotel,
    PoiCategory.campsite,
  };

  IconData? get icon => switch (this) {
        PoiCategory.fuel => Icons.local_gas_station,
        PoiCategory.motoHotel => Icons.hotel,
        PoiCategory.bikerMeetup => Icons.local_bar,
        PoiCategory.campsite => Icons.forest,
        PoiCategory.iceCream => Icons.icecream,
        PoiCategory.speedCamera => Icons.camera_alt,
        PoiCategory.restaurant => Icons.restaurant,
        PoiCategory.pub => Icons.sports_bar,
        PoiCategory.snack => Icons.fastfood,
      };
}

/// Fertig berechnete Route inkl. der Präferenz, mit der sie angefragt
/// wurde. Der Teilnehmerfluss (Screens 6-8) arbeitet ausschließlich
/// mit diesem Objekt, nie mit rohen Backend-DTOs.
class ComputedRoute {
  final String id;
  final List<Waypoint> waypoints;
  final RoutePreference preference;
  final List<List<double>> geometry;
  final double distanceMeters;
  final double durationSeconds;
  final List<RouteSegment> segments;

  const ComputedRoute({
    required this.id,
    required this.waypoints,
    required this.preference,
    required this.geometry,
    required this.distanceMeters,
    required this.durationSeconds,
    required this.segments,
  });

  factory ComputedRoute.fromDomain(dynamic route) => ComputedRoute(
        id: route.id as String,
        waypoints: List<Waypoint>.from(route.waypoints as List),
        preference: route.preference as RoutePreference,
        geometry: List<List<double>>.from(route.geometry as List),
        distanceMeters: route.distanceMeters as double,
        durationSeconds: route.durationSeconds as double,
        segments: List<RouteSegment>.from(route.segments as List),
      );
}
