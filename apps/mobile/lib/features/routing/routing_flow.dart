import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:motoroute_app/core/error/failure.dart';
import 'package:motoroute_app/core/state/app_providers.dart';
import 'package:motoroute_app/features/routing/data/routing_providers.dart';
import 'package:motoroute_app/features/routing/domain/route_entities.dart';
import 'package:motoroute_app/features/routing/domain/routing_repository.dart';

/// State des Routen-Berechnungs-Flows (Screen 6 -> 7). Die Fahrstil-
/// Kacheln zeigen Lade-/Fehlerzustände, statt still zu versagen: ein
/// Tap auf "Kurvig" ohne laufendes Feedback fühlt sich für den Nutzer
/// wie ein toter Button an.
class RoutingFlowState {
  final bool isCalculating;
  final String? error;
  final ComputedRoute? route;

  const RoutingFlowState({this.isCalculating = false, this.error, this.route});
}

class RoutingFlowController extends StateNotifier<RoutingFlowState> {
  final RoutingRepository _repository;

  RoutingFlowController(this._repository) : super(const RoutingFlowState());

  Future<ComputedRoute?> calculate({
    required List<Waypoint> waypoints,
    required RoutePreference preference,
  }) async {
    state = const RoutingFlowState(isCalculating: true);
    final result = await _repository.createRoute(
      waypoints: waypoints,
      preference: preference,
    );

    return result.fold(
      (failure) {
        state = RoutingFlowState(error: _messageFor(failure));
        return null;
      },
      (route) {
        final computed = ComputedRoute.fromDomain(route);
        state = RoutingFlowState(route: computed);
        return computed;
      },
    );
  }

  String _messageFor(Failure failure) => switch (failure) {
        NetworkFailure() => 'Backend nicht erreichbar - läuft der Server?',
        RoutingFailure(:final message) => message,
        UnexpectedFailure() => 'Unerwarteter Fehler bei der Routenberechnung',
      };
}

final routingFlowProvider =
    StateNotifierProvider<RoutingFlowController, RoutingFlowState>((ref) {
  return RoutingFlowController(ref.watch(routingRepositoryProvider));
});
