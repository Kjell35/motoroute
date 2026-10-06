import 'dart:math' as math;

/// Glättet GPS-Heading (Zappeln bei niedriger Geschwindigkeit) per
/// kompassartiger Mittelung + Hysterese.
/// Domain-Logik, pure Dart (docs/02-architecture.md §2).
class HeadingFilter {
  HeadingFilter({this.windowSize = 5, this.minDeltaDegrees = 12});

  /// Anzahl der Fixes im gleitenden Fenster.
  final int windowSize;

  /// Neue Richtung wird erst übernommen, wenn sie ≥ so viel vom geglätteten
  /// Stand abweicht (Hysterese gegen Flackern bei Geradeausfahrt).
  final double minDeltaDegrees;

  final List<double> _window = <double>[];
  double? _smoothed;

  double? get smoothedHeading => _smoothed;

  /// Fügt einen Fix hinzu und liefert den geglätteten Heading.
  double? push(double? rawHeadingDegrees) {
    if (rawHeadingDegrees == null) return _smoothed;
    final double h = _normalize(rawHeadingDegrees);
    _window.add(h);
    if (_window.length > windowSize) _window.removeAt(0);
    if (_window.length < 3) {
      _smoothed = _normalize(_circularMean(_window));
      return _smoothed;
    }
    final double candidate = _circularMean(_window);
    final double delta = _angularDistance(candidate, _smoothed ?? candidate);
    if (_smoothed == null || delta >= minDeltaDegrees) {
      _smoothed = candidate;
    }
    return _smoothed;
  }

  void reset() {
    _window.clear();
    _smoothed = null;
  }

  static double _circularMean(List<double> degrees) {
    double sinSum = 0, cosSum = 0;
    for (final double d in degrees) {
      final double r = d * math.pi / 180.0;
      sinSum += math.sin(r);
      cosSum += math.cos(r);
    }
    final double angle = math.atan2(sinSum, cosSum) * 180.0 / math.pi;
    return _normalize(angle);
  }

  static double _angularDistance(double a, double b) {
    final double diff = (a - b).abs() % 360;
    return diff > 180 ? 360 - diff : diff;
  }

  static double _normalize(double deg) {
    final double d = deg % 360.0;
    return d < 0 ? d + 360.0 : d;
  }
}
