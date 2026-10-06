import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/route_preferences.dart';
import '../../domain/models/route_quote.dart';
import '../../domain/models/waypoint.dart';
import '../../domain/repositories/routing_repository.dart';
import '../../infrastructure/routing/http_routing_repository.dart';

final Provider<RoutingRepository> routingRepositoryProvider =
    Provider<RoutingRepository>((ref) => HttpRoutingRepository());

final NotifierProvider<RouteQuoteController, AsyncValue<RouteQuote?>> routeQuoteProvider =
    NotifierProvider<RouteQuoteController, AsyncValue<RouteQuote?>>(RouteQuoteController.new);

class RouteQuoteController extends Notifier<AsyncValue<RouteQuote?>> {
  @override
  AsyncValue<RouteQuote?> build() => const AsyncData(null);

  Future<void> calculate(List<Waypoint> waypoints, RoutePreferences preferences) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref.read(routingRepositoryProvider).calculate(waypoints, preferences),
    );
  }
}
