import 'geo.dart';

/// Requires repeated distant fixes before declaring the rider off-route,
/// reducing false reroutes caused by a single noisy GPS sample.
const int kOffRouteFixesToConfirm = 2;

/// Hysteresis keeps the route state stable around the configured thresholds.
const double kOffRouteRecoveryMeters = 40;

class RouteMatchResult {
  final double progressMeters;
  final double distanceMeters;
  final int segmentIndex;
  final bool isOffRoute;
  final int consecutiveOffRouteFixes;

  const RouteMatchResult({
    required this.progressMeters,
    required this.distanceMeters,
    required this.segmentIndex,
    required this.isOffRoute,
    required this.consecutiveOffRouteFixes,
  });
}

/// Stateful matcher: prefers nearby forward segments, prevents regressions
/// from GPS jitter, and debounces off-route decisions.
class RouteMatcher {
  RouteMatcher({
    required this.geometry,
    required this.cumulative,
    this.offRouteThresholdMeters = 60,
    this.maxForwardMeters = 500,
    this.maxBackwardMeters = 30,
    this.offRouteFixesToConfirm = kOffRouteFixesToConfirm,
    this.recoveryDistanceMeters = kOffRouteRecoveryMeters,
  });

  final List<List<double>> geometry;
  final List<double> cumulative;
  final double offRouteThresholdMeters;
  final double maxForwardMeters;
  final double maxBackwardMeters;
  final int offRouteFixesToConfirm;
  final double recoveryDistanceMeters;

  double? _progressMeters;
  int _segmentIndex = 0;
  int _offRouteFixes = 0;
  bool _isOffRoute = false;

  double? get progressMeters => _progressMeters;
  int get segmentIndex => _segmentIndex;
  bool get isOffRoute => _isOffRoute;

  RouteMatchResult match({required double lat, required double lng}) {
    final match = matchRoutePosition(
      lat: lat,
      lng: lng,
      geometry: geometry,
      cumulative: cumulative,
      previousProgressMeters: _progressMeters,
      maxBackwardMeters: maxBackwardMeters,
      maxForwardMeters: maxForwardMeters,
    );

    _progressMeters = match.progressMeters;
    _segmentIndex = match.segmentIndex;

    if (_isOffRoute) {
      if (match.distanceMeters <= recoveryDistanceMeters) {
        _isOffRoute = false;
        _offRouteFixes = 0;
      }
    } else if (match.distanceMeters > offRouteThresholdMeters) {
      _offRouteFixes++;
      if (_offRouteFixes >= offRouteFixesToConfirm) {
        _isOffRoute = true;
      }
    } else {
      _offRouteFixes = 0;
    }

    return RouteMatchResult(
      progressMeters: _progressMeters!,
      distanceMeters: match.distanceMeters,
      segmentIndex: _segmentIndex,
      isOffRoute: _isOffRoute,
      consecutiveOffRouteFixes: _offRouteFixes,
    );
  }
}
