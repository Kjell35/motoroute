import 'package:dartz/dartz.dart';
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
}
