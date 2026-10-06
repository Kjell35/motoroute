import '../models/route_preferences.dart';
import '../models/route_quote.dart';
import '../models/waypoint.dart';

abstract interface class RoutingRepository {
  Future<RouteQuote> calculate(List<Waypoint> waypoints, RoutePreferences preferences);
}
