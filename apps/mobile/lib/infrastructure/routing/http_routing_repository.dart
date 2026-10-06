import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/config/env.dart';
import '../../domain/models/route_preferences.dart';
import '../../domain/models/route_quote.dart';
import '../../domain/models/waypoint.dart';
import '../../domain/repositories/routing_repository.dart';

class RoutingException implements Exception {
  const RoutingException(this.message);
  final String message;
}

class HttpRoutingRepository implements RoutingRepository {
  HttpRoutingRepository({http.Client? client}) : _client = client ?? http.Client();
  final http.Client _client;

  @override
  Future<RouteQuote> calculate(List<Waypoint> points, RoutePreferences preferences) async {
    final response = await _client
        .post(
          Uri.parse('${Env.apiBaseUrl}/api/v1/route'),
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode({
            'waypoints': points.map((point) => {'lat': point.latitude, 'lon': point.longitude}).toList(),
            'preferences': {
              'vehicle': preferences.vehicle.name,
              'ride_style': _styleValue(preferences.rideStyle),
              'avoid': preferences.avoidances.map((item) => item.name).toList(),
            },
          }),
        )
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      throw const RoutingException('Route konnte nicht berechnet werden.');
    }
    final Map<String, dynamic> payload = jsonDecode(response.body) as Map<String, dynamic>;
    final Map<String, dynamic> candidate = (payload['candidates'] as List<dynamic>).first as Map<String, dynamic>;
    return RouteQuote(
      distanceMeters: candidate['distance_m'] as int,
      durationSeconds: candidate['duration_s'] as int,
    );
  }

  String _styleValue(RideStyle style) => switch (style) {
        RideStyle.fast => 'fast',
        RideStyle.curvy => 'curvy',
        RideStyle.extraCurvy => 'extra_curvy',
        RideStyle.fastAndCurvy => 'fast_and_curvy',
      };
}
