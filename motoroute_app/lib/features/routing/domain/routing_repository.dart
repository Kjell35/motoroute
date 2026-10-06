import 'package:dartz/dartz.dart';
import 'package:motoroute_app/core/constants/route_enums.dart';
import 'package:motoroute_app/core/error/failure.dart';
import 'route_entities.dart';

/// Abstraktes Repository - Presentation-Schicht (Riverpod-Controller)
/// hängt nur hiervon ab, nie von der konkreten Dio-Implementierung.
/// Ermöglicht triviales Mocking in Tests (siehe
/// routing_repository_test.dart, sobald Controller-Tests dazukommen).
abstract class RoutingRepository {
  Future<Either<Failure, NavigationRoute>> createRoute({
    required List<Waypoint> waypoints,
    required RoutePreference preference,
  });

  Future<Either<Failure, NavigationRoute>> reroute({
    required List<Waypoint> waypoints,
    required RoutePreference preference,
  });

  /// Geschlossene Rundtour ab [start] mit Ziel-Laenge und Stil generieren
  /// (POST /v1/roundtrips). Richtung optional (Nord/Ost/Sued/West, sonst
  /// zufaellig serverseitig).
  Future<Either<Failure, NavigationRoute>> createRoundTrip({
    required Waypoint start,
    required double targetDistanceKm,
    required RouteStyle style,
    required VehicleType vehicleType,
    String? direction,
  });
}
