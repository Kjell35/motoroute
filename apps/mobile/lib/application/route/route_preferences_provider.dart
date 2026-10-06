import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/route_preferences.dart';

final NotifierProvider<RoutePreferencesController, RoutePreferences>
    routePreferencesProvider = NotifierProvider<RoutePreferencesController,
        RoutePreferences>(RoutePreferencesController.new);

class RoutePreferencesController extends Notifier<RoutePreferences> {
  @override
  RoutePreferences build() => const RoutePreferences();

  void setVehicle(VehicleType value) => state = state.copyWith(vehicle: value);
  void setRideStyle(RideStyle value) => state = state.copyWith(rideStyle: value);

  void toggleAvoidance(RouteAvoidance value) {
    final Set<RouteAvoidance> updated = {...state.avoidances};
    updated.contains(value) ? updated.remove(value) : updated.add(value);
    state = state.copyWith(avoidances: updated);
  }
}
