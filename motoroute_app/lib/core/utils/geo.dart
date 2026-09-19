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
      math.cos(_rad(lat1)) * math.cos(_rad(lat2)) * math.sin(dLng / 2) * math.sin(dLng / 2);
  return earthRadiusMeters * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
}

/// Kürzeste Distanz eines Punkts zu einem Polyline-Segment in Metern.
double distanceToSegmentMeters(
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
    return haversineMeters(py, px, ay, ax);
  }

  var t = ((pxM - axM) * dx + (pyM - ayM) * dy) / segLenSq;
  t = t.clamp(0.0, 1.0);
  final projLat = ay + t * (by - ay);
  final projLng = ax + t * (bx - ax);
  return haversineMeters(py, px, projLat, projLng);
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
          geometry[i - 1][1], geometry[i - 1][0], geometry[i][1], geometry[i][0],
        );
  }
  return result;
}

double _rad(double deg) => deg * math.pi / 180.0;
