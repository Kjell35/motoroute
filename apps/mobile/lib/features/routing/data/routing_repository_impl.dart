import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart';
import 'package:motoroute_app/core/constants/route_enums.dart';
import 'package:motoroute_app/core/error/failure.dart';
import '../domain/route_entities.dart';
import '../domain/routing_repository.dart';

/// Einzige Stelle, die weiß, wie die Backend-Endpunkte POST /api/v1/route
/// und POST /api/v1/roundtrips geformt sind (siehe apps/backend/app/api/routing.py).
/// Das Backend liefert `candidates[]` mit snake_case-Feldern und die Geometrie
/// als Polyline6; diese Klasse übersetzt das in die App-Domäne.
class RoutingRepositoryImpl implements RoutingRepository {
  final Dio _dio;

  RoutingRepositoryImpl(this._dio);

  @override
  Future<Either<Failure, NavigationRoute>> createRoute({
    required List<Waypoint> waypoints,
    required RoutePreference preference,
  }) {
    return _request(waypoints: waypoints, preference: preference);
  }

  @override
  Future<Either<Failure, NavigationRoute>> reroute({
    required List<Waypoint> waypoints,
    required RoutePreference preference,
  }) {
    // Das Backend hat keinen eigenen Neuberechnungs-Endpunkt; eine
    // Neuberechnung ist eine normale Routenanfrage mit den aktuellen Punkten.
    return _request(waypoints: waypoints, preference: preference);
  }

  @override
  Future<Either<Failure, NavigationRoute>> createRoundTrip({
    required Waypoint start,
    required double targetDistanceKm,
    required RouteStyle style,
    required VehicleType vehicleType,
    String? direction,
  }) async {
    final preference = RoutePreference(style: style, vehicleType: vehicleType);
    try {
      final response = await _dio.post(
        '/api/v1/roundtrips',
        data: {
          'start': _coordinateJson(start),
          'target_distance_km': targetDistanceKm,
          'direction': direction ?? 'RANDOM',
          'preferences': _preferencesJson(preference),
        },
      );
      return _toRoute(
        response.data,
        preference: preference,
        waypoints: [start],
        failureMessage: 'Rundtour konnte nicht erstellt werden',
      );
    } on DioException catch (e) {
      return Left(_dioFailure(e, 'Rundtour konnte nicht erstellt werden'));
    } catch (_) {
      return const Left(UnexpectedFailure());
    }
  }

  Future<Either<Failure, NavigationRoute>> _request({
    required List<Waypoint> waypoints,
    required RoutePreference preference,
  }) async {
    try {
      final response = await _dio.post(
        '/api/v1/route',
        data: {
          'waypoints': waypoints.map(_coordinateJson).toList(),
          'preferences': _preferencesJson(preference),
        },
      );
      return _toRoute(
        response.data,
        preference: preference,
        waypoints: waypoints,
        failureMessage: 'Route konnte nicht berechnet werden',
      );
    } on DioException catch (e) {
      return Left(_dioFailure(e, 'Route konnte nicht berechnet werden'));
    } catch (_) {
      return const Left(UnexpectedFailure());
    }
  }

  /// Nimmt den ersten Kandidaten der Backend-Antwort und mappt ihn auf
  /// [NavigationRoute]. Ohne Kandidaten gibt es keine Route -> Failure.
  Either<Failure, NavigationRoute> _toRoute(
    dynamic data, {
    required RoutePreference preference,
    required List<Waypoint> waypoints,
    required String failureMessage,
  }) {
    final candidates = (data as Map<String, dynamic>)['candidates'] as List? ?? const [];
    if (candidates.isEmpty) {
      return Left(RoutingFailure(failureMessage));
    }
    final candidate = candidates.first as Map<String, dynamic>;
    final polyline = candidate['geometry_polyline6'] as String?;
    if (polyline == null || polyline.isEmpty) {
      return Left(RoutingFailure(failureMessage));
    }
    return Right(
      NavigationRoute(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        waypoints: waypoints,
        preference: preference,
        geometry: decodePolyline6(polyline),
        distanceMeters: (candidate['distance_m'] as num).toDouble(),
        durationSeconds: (candidate['duration_s'] as num).toDouble(),
        segments: (candidate['segments'] as List? ?? const [])
            .map((s) => RouteSegment.fromJson(s as Map<String, dynamic>))
            .toList(),
      ),
    );
  }

  Failure _dioFailure(DioException e, String fallbackMessage) {
    if (e.type == DioExceptionType.connectionError ||
        e.type == DioExceptionType.connectionTimeout) {
      return const NetworkFailure();
    }
    // FastAPI legt Fehler unter `detail` ab: {"detail": {"code", "message"}}.
    final body = e.response?.data;
    final detail = body is Map ? body['detail'] : null;
    final serverMessage = detail is Map ? detail['message']?.toString() : null;
    return RoutingFailure(serverMessage ?? fallbackMessage);
  }
}

Map<String, dynamic> _coordinateJson(Waypoint w) => {'lat': w.lat, 'lon': w.lng};

Map<String, dynamic> _preferencesJson(RoutePreference p) => {
      'vehicle': _vehicleValue(p.vehicleType),
      'ride_style': _rideStyleValue(p.style),
      'avoid': p.avoid.map(_avoidValue).toList(),
    };

String _vehicleValue(VehicleType v) => switch (v) {
      VehicleType.motorcycle => 'motorcycle',
      VehicleType.car => 'car',
      VehicleType.bicycle => 'bicycle',
    };

String _rideStyleValue(RouteStyle s) => switch (s) {
      RouteStyle.fast => 'fast',
      RouteStyle.curvy => 'curvy',
      RouteStyle.extraCurvy => 'extra_curvy',
      RouteStyle.fastAndCurvy => 'fast_and_curvy',
      RouteStyle.unpaved => 'unpaved',
    };

String _avoidValue(AvoidOption a) => switch (a) {
      AvoidOption.highway => 'highway',
      AvoidOption.ferry => 'ferry',
      AvoidOption.toll => 'toll',
    };

/// Dekodiert einen Valhalla-Polyline6-String in `[lng, lat]`-Paare (Grad).
/// Gleiche Reihenfolge wie die bisherige Geometrie der App.
List<List<double>> decodePolyline6(String encoded) {
  final points = <List<double>>[];
  var index = 0;
  var lat = 0;
  var lng = 0;

  int nextByte() {
    if (index >= encoded.length) {
      throw const FormatException('Polyline6 endet unerwartet');
    }
    return encoded.codeUnitAt(index++) - 63;
  }

  while (index < encoded.length) {
    for (var axis = 0; axis < 2; axis++) {
      var shift = 0;
      var result = 0;
      int byte;
      do {
        byte = nextByte();
        result |= (byte & 0x1f) << shift;
        shift += 5;
      } while (byte >= 0x20);
      final delta = (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
      if (axis == 0) {
        lat += delta;
      } else {
        lng += delta;
      }
    }
    points.add([lng / 1e6, lat / 1e6]);
  }
  return points;
}
