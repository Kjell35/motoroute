import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart';
import 'package:motoroute_app/core/error/failure.dart';
import '../domain/route_entities.dart';
import '../domain/routing_repository.dart';

/// Einzige Stelle, die weiß, wie die Backend-Endpunkte
/// POST /v1/routes und POST /v1/routes/reroute geformt sind (siehe
/// motoroute_api/src/modules/routing/routing.controller.ts). Bewusst
/// symmetrisch zum GraphHopperClient im Backend: dort kapselt eine
/// Klasse GraphHopper, hier kapselt eine Klasse das eigene Backend.
class RoutingRepositoryImpl implements RoutingRepository {
  final Dio _dio;

  RoutingRepositoryImpl(this._dio);

  @override
  Future<Either<Failure, NavigationRoute>> createRoute({
    required List<Waypoint> waypoints,
    required RoutePreference preference,
  }) {
    return _request('/v1/routes', waypoints: waypoints, preference: preference);
  }

  @override
  Future<Either<Failure, NavigationRoute>> reroute({
    required List<Waypoint> waypoints,
    required RoutePreference preference,
  }) {
    // Siehe Kommentar in routing.controller.ts (Backend): reroute nimmt
    // aktuell noch volle Wegpunkte statt einer Routen-ID entgegen, bis
    // Routen-Persistenz existiert (Sprint 9). App-seitig ist das
    // bewusst hinter diesem Repository verborgen, damit sich das später
    // ändern kann, ohne dass Presentation-Code angefasst werden muss.
    return _request('/v1/routes/reroute', waypoints: waypoints, preference: preference);
  }

  Future<Either<Failure, NavigationRoute>> _request(
    String path, {
    required List<Waypoint> waypoints,
    required RoutePreference preference,
  }) async {
    try {
      final response = await _dio.post(
        path,
        data: {
          'waypoints': waypoints.map((w) => w.toJson()).toList(),
          'preference': preference.toJson(),
        },
      );

      final route = NavigationRoute.fromJson(
        response.data as Map<String, dynamic>,
        requestedPreference: preference,
        requestedWaypoints: waypoints,
      );
      return Right(route);
    } on DioException catch (e) {
      if (e.type == DioExceptionType.connectionError ||
          e.type == DioExceptionType.connectionTimeout) {
        return const Left(NetworkFailure());
      }
      final serverMessage = e.response?.data is Map
          ? (e.response?.data['message']?.toString())
          : null;
      return Left(RoutingFailure(serverMessage ?? 'Route konnte nicht berechnet werden'));
    } catch (_) {
      return const Left(UnexpectedFailure());
    }
  }
}
