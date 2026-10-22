/// Geo-Mathematik für die Navigations-Logik (Off-Route-Erkennung,
/// Fortschritts-Berechnung). Bewusst rein funktional und ohne
/// Flutter-Bezug, damit jede Formel unit-testbar ist - hier liegen die
/// einzigen Stellen, an denen ein Rundungsfehler während der Fahrt
/// tatsächlich Gefahr bedeutet (falsches "Sie haben die Route verlassen").
library;

import 'dart:math' as math;

const double earthRadiusMeters = 6371000.0;

/// Distanz zweier Koordinaten in Metern (Haversine).
double haversineMeters(double lat1, double lng1, double lat2, double lng2) {
  final dLat = _rad(lat2 - lat1);
  final dLng = _rad(lng2 - lng1);
  final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(_rad(lat1)) *
          math.cos(_rad(lat2)) *
          math.sin(dLng / 2) *
          math.sin(dLng / 2);
  return earthRadiusMeters * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
}

/// Ergebnis des Abgleichs eines GPS-Fixes mit der Routen-Geometrie.
class RoutePositionMatch {
  final double progressMeters;
  final double distanceMeters;
  final int segmentIndex;

  const RoutePositionMatch({
    required this.progressMeters,
    required this.distanceMeters,
    required this.segmentIndex,
  });
}

/// Kürzeste Distanz eines Punkts zu einem Polyline-Segment in Metern.
double distanceToSegmentMeters(
  double px,
  double py,
  double ax,
  double ay,
  double bx,
  double by,
) =>
    _projectOntoSegment(px, py, ax, ay, bx, by).distanceMeters;

({double distanceMeters, double fraction}) _projectOntoSegment(
  double px,
  double py,
  double ax,
  double ay,
  double bx,
  double by,
) {
  // equirectangular-Projektion um die Segment-Mitte - für Segment-
  // Distanzen < ein paar km ausreichend genau und deutlich billiger
  // als wiederholtes Haversine. WICHTIG: ALLE Punkte (auch A)
  // einheitlich projizieren - ein verfälschter Projektionsursprung
  // verschiebt das Lot und produziert falsche Off-Route-Entscheidungen.
  final latRef = _rad((ay + by) / 2);
  final cosRef = math.cos(latRef);
  final axM = _rad(ax) * cosRef;
  final ayM = _rad(ay);
  final bxM = _rad(bx) * cosRef;
  final byM = _rad(by);
  final pxM = _rad(px) * cosRef;
  final pyM = _rad(py);

  final dx = bxM - axM;
  final dy = byM - ayM;
  final segLenSq = dx * dx + dy * dy;

  // Degeneriertes Segment (Start == Ende): Punktdistanz.
  if (segLenSq == 0) {
    return (distanceMeters: haversineMeters(py, px, ay, ax), fraction: 0);
  }

  final fraction =
      (((pxM - axM) * dx + (pyM - ayM) * dy) / segLenSq).clamp(0.0, 1.0);
  final projLat = ay + fraction * (by - ay);
  final projLng = ax + fraction * (bx - ax);
  return (
    distanceMeters: haversineMeters(py, px, projLat, projLng),
    fraction: fraction,
  );
}

/// Ordnet einen GPS-Fix einem Streckensegment zu und berechnet den
/// projizierten Fortschritt entlang der Route. Mit [previousProgressMeters]
/// und Vor-/Rückwärtsgrenzen springt der Match nicht bei GPS-Rauschen auf
/// einen entfernten Abschnitt derselben Route.
RoutePositionMatch matchRoutePosition({
  required double lat,
  required double lng,
  required List<List<double>> geometry,
  required List<double> cumulative,
  double? previousProgressMeters,
  double maxBackwardMeters = 30,
  double maxForwardMeters = double.infinity,
}) {
  if (geometry.isEmpty) {
    return RoutePositionMatch(
      progressMeters: previousProgressMeters ?? 0,
      distanceMeters: double.infinity,
      segmentIndex: 0,
    );
  }
  if (geometry.length == 1) {
    return RoutePositionMatch(
      progressMeters: previousProgressMeters ?? 0,
      distanceMeters: haversineMeters(lat, lng, geometry[0][1], geometry[0][0]),
      segmentIndex: 0,
    );
  }

  var nearestDistance = double.infinity;
  var nearestProgress = 0.0;
  var nearestSegment = 0;
  var bestProgressDistance = double.infinity;
  var matchedProgress = previousProgressMeters ?? 0;
  var matchedSegment = 0;
  var fallbackDistance = double.infinity;
  var fallbackProgress = 0.0;
  var fallbackSegment = 0;
  final minProgress = previousProgressMeters == null
      ? double.negativeInfinity
      : previousProgressMeters - maxBackwardMeters;
  final maxProgress = previousProgressMeters == null
      ? double.infinity
      : previousProgressMeters + maxForwardMeters;

  for (var i = 0; i < geometry.length - 1; i++) {
    final a = geometry[i];
    final b = geometry[i + 1];
    final projection = _projectOntoSegment(lng, lat, a[0], a[1], b[0], b[1]);
    final segmentLength = cumulative[i + 1] - cumulative[i];
    final progress = cumulative[i] + segmentLength * projection.fraction;

    if (projection.distanceMeters < nearestDistance) {
      nearestDistance = projection.distanceMeters;
      nearestProgress = progress;
      nearestSegment = i;
    }
    final hasPlausibleProgress = previousProgressMeters == null
        ? progress >= 0 && progress <= maxForwardMeters
        : progress >= previousProgressMeters && progress <= maxProgress;
    if (hasPlausibleProgress && projection.distanceMeters < fallbackDistance) {
      fallbackDistance = projection.distanceMeters;
      fallbackProgress = progress;
      fallbackSegment = i;
    }
    if (progress < minProgress || progress > maxProgress) continue;
    if (projection.distanceMeters < bestProgressDistance) {
      bestProgressDistance = projection.distanceMeters;
      matchedProgress = progress;
      matchedSegment = i;
    }
  }

  if (bestProgressDistance.isInfinite) {
    // GPS-/Stream-Lücken können größer als das lokale Suchfenster sein.
    // Fortschritt in diesem Fall nur begrenzt weiterführen, damit ein Fix
    // nicht direkt auf eine weit entfernte parallele/überlappende Strecke springt.
    if (previousProgressMeters == null) {
      matchedProgress = nearestProgress;
      matchedSegment = nearestSegment;
    } else {
      if (fallbackDistance.isInfinite) {
        matchedProgress = previousProgressMeters;
        matchedSegment = 0;
        for (var i = 0; i < cumulative.length - 1; i++) {
          if (previousProgressMeters >= cumulative[i] &&
              previousProgressMeters <= cumulative[i + 1]) {
            matchedSegment = i;
            break;
          }
        }
      } else {
        matchedProgress = fallbackProgress;
        matchedSegment = fallbackSegment;
      }
    }
  } else if (previousProgressMeters != null) {
    // Kleine Positionsschwankungen dürfen das aktive Manöver nicht rückwärts
    // springen lassen, obwohl der Match noch im Toleranzfenster liegt.
    matchedProgress = math.max(previousProgressMeters, matchedProgress);
  }

  return RoutePositionMatch(
    progressMeters: matchedProgress,
    distanceMeters: nearestDistance,
    segmentIndex: matchedSegment,
  );
}

/// Kürzeste Distanz eines Punkts zu einer ganzen Route (Meter) - Kern
/// der Off-Route-Erkennung: GPS-Punkt vs. Routen-Geometrie.
double distanceToRouteMeters(
  double lat,
  double lng,
  List<List<double>> geometry, // [lng, lat]-Paare
) {
  if (geometry.isEmpty) return double.infinity;
  if (geometry.length == 1) {
    return haversineMeters(lat, lng, geometry[0][1], geometry[0][0]);
  }
  var best = double.infinity;
  for (var i = 0; i < geometry.length - 1; i++) {
    final d = distanceToSegmentMeters(
      lng,
      lat,
      geometry[i][0],
      geometry[i][1],
      geometry[i + 1][0],
      geometry[i + 1][1],
    );
    if (d < best) best = d;
  }
  return best;
}

/// Kumulierte Distanzen entlang der Geometrie - Grundlage für den
/// Fortschritt in der aktiven Navigation.
List<double> cumulativeDistances(List<List<double>> geometry) {
  final result = List<double>.filled(geometry.length, 0);
  for (var i = 1; i < geometry.length; i++) {
    result[i] = result[i - 1] +
        haversineMeters(
          geometry[i - 1][1],
          geometry[i - 1][0],
          geometry[i][1],
          geometry[i][0],
        );
  }
  return result;
}

double _rad(double deg) => deg * math.pi / 180.0;
