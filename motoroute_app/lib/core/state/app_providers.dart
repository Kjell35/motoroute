import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:motoroute_app/core/constants/route_enums.dart';
import 'package:motoroute_app/core/network/api_client.dart';
import 'package:motoroute_app/core/utils/formatters.dart';
import 'package:motoroute_app/features/routing/domain/route_entities.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Globale Einstellungen. Persistiert via shared_preferences (einmalig
/// in main() ueber [initSessionSettings] geladen); Veraenderungen im UI
/// schreiben sofort zurueck - sie ueberleben App-Starts und Updates.

const _kVehicleType = 'settings.vehicleType';
const _kDistanceUnit = 'settings.distanceUnit';
const _kPoiCategories = 'settings.poiCategories';

/// Persistierte Werte laden (in main() VOR runApp aufrufen).
Future<void> initSessionSettings() async {
  await ApiClient.init();
  final prefs = await SharedPreferences.getInstance();
  persistedVehicleType = VehicleType.values.firstWhere(
    (v) => v.name == prefs.getString(_kVehicleType),
    orElse: () => VehicleType.motorcycle,
  );
  persistedDistanceUnit = DistanceUnit.values.firstWhere(
    (u) => u.name == prefs.getString(_kDistanceUnit),
    orElse: () => DistanceUnit.kilometers,
  );
  final names = prefs.getStringList(_kPoiCategories);
  if (names != null) {
    persistedPoiCategories = names
        .map((n) => PoiCategory.values.firstWhere(
              (c) => c.name == n,
              orElse: () => PoiCategory.fuel,
            ))
        .toSet();
  }
}

/// Von initSessionSettings gesetzte Startwerte (Riverpod-Provider
/// sind top-level final - sie lesen diese Variablen beim ersten
/// Zugriff; deshalb MUSS init vor runApp passieren).
VehicleType persistedVehicleType = VehicleType.motorcycle;
DistanceUnit persistedDistanceUnit = DistanceUnit.kilometers;
Set<PoiCategory> persistedPoiCategories = {PoiCategory.fuel};

final vehicleTypeProvider =
    StateProvider<VehicleType>((ref) => persistedVehicleType);

final distanceUnitProvider =
    StateProvider<DistanceUnit>((ref) => persistedDistanceUnit);

/// Aktive POI-Kategorien auf der Karte (Screen 10): Ein Tap schaltet
/// sofort um - der State ist Quelle der Wahrheit für Layer UND Auswahl-Sheet.
/// Startwert kommt aus den Persistenz-Einstellungen.
final activePoiCategoriesProvider =
    StateProvider<Set<PoiCategory>>((ref) => persistedPoiCategories);

/// Persistenz-Schreiber: Fahrzeugtyp, Einheit und POI-Kategorien.
/// Die Screens rufen diese nach der State-Änderung auf (bewusst
/// explizit statt Listenable-Reflexion - so bleibt der Statefluss
/// lesbar und testbar).
Future<void> persistVehicleType(VehicleType value) async {
  (await SharedPreferences.getInstance()).setString(_kVehicleType, value.name);
}

Future<void> persistDistanceUnit(DistanceUnit value) async {
  (await SharedPreferences.getInstance()).setString(_kDistanceUnit, value.name);
}

Future<void> persistPoiCategories(Set<PoiCategory> value) async {
  (await SharedPreferences.getInstance())
      .setStringList(_kPoiCategories, value.map((c) => c.name).toList());
}

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
