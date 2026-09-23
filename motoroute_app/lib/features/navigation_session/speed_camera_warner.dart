import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vibration/vibration.dart';

import '../poi/poi_providers.dart';
import '../../core/state/app_providers.dart' show PoiCategory;

/// Blitzer-Fahrtwarnung während der aktiven Navigation.
///
/// Funktionsweise:
/// 1. Beim Navigationsstart lädt der Warner die SPEED_CAMERA-POIs
///    entlang der Route (Bounding-Box der Geometrie + 500 m Puffer)
///    über den bestehenden POI-Endpunkt (OSM/Overpass).
/// 2. Bei jedem GPS-Fix wird die Distanz zur nächsten Kamera geprüft.
///    Innerhalb der Warndistanz (120 m bei > 50 km/h Fahrzeit-Skalierung
///    sonst) feuert EIN Alarm pro Kamera (Re-Alarm erst nach 2 km oder
///    neuer Fahrt) - keine Dauerpiepserei im Vorbeifahren.
/// 3. Warnung = optisch (NavigationScreen-Banner, state.nextCamera)
///    + haptisch (Vibration 2x 400 ms).
///
/// Datenschutzerklärung-Konformität: Es werden nur POI-Koordinaten des
/// eigenen Backends abgefragt - keine Positions-Historie, kein Tracking.
class SpeedCameraWarning {
  /// Distanz in Metern zur nächsten Kamera (falls Warnung aktiv).
  final double distanceMeters;

  /// Position der Kamera.
  final double lat;
  final double lng;

  const SpeedCameraWarning({
    required this.distanceMeters,
    required this.lat,
    required this.lng,
  });
}

/// Zustand des Warners: geladene Kameras + die aktuell aktive Warnung.
class SpeedCameraState {
  /// Kameras entlang der Route (aus dem POI-Layer).
  final List<({double lat, double lng})> cameras;

  /// Aktive Warnung oder null.
  final SpeedCameraWarning? activeWarning;

  /// IDs bereits alarmierter Kameras (kein Re-Alarm im Vorbeifahren) -
  /// indexbasiert (Position in der Liste, stabil genug für die Fahrt).
  final Set<int> warnedIndices;

  const SpeedCameraState({
    this.cameras = const [],
    this.activeWarning,
    this.warnedIndices = const {},
  });

  bool get hasCameras => cameras.isNotEmpty;

  SpeedCameraState copyWith({
    List<({double lat, double lng})>? cameras,
    SpeedCameraWarning? activeWarning,
    Set<int>? warnedIndices,
    bool clearWarning = false,
  }) =>
      SpeedCameraState(
        cameras: cameras ?? this.cameras,
        activeWarning: clearWarning ? null : (activeWarning ?? this.activeWarning),
        warnedIndices: warnedIndices ?? this.warnedIndices,
      );
}

class SpeedCameraWarnerController extends StateNotifier<SpeedCameraState> {
  final Ref _ref;

  /// Warndistanz: 120 m Grundwert - entspricht ~4 s Reaktionszeit bei
  /// 100 km/h. Bei langsamer Fahrt (Stau im Ort) reicht 80 m.
  static const double warnDistanceMeters = 120;
  static const double warnDistanceSlowMeters = 80;

  /// Nach Verlassen der Warndistanz gilt die Kamera als " passiert".
  static const double passedDistanceMeters = 250;

  SpeedCameraWarnerController(this._ref) : super(const SpeedCameraState());

  Timer? _cooldown;
  bool _disposed = false;

  /// Lädt Blitzer entlang der Route (beim Navigationsstart).
  Future<void> loadForRoute(List<List<double>> geometry) async {
    if (geometry.isEmpty) return;

    // Bounding-Box der Route + Puffer.
    double minLat = 90, maxLat = -90, minLng = 180, maxLng = -180;
    for (final p in geometry) {
      if (p[1] < minLat) minLat = p[1];
      if (p[1] > maxLat) maxLat = p[1];
      if (p[0] < minLng) minLng = p[0];
      if (p[0] > maxLng) maxLng = p[0];
    }
    const pad = 0.005; // ~500 m
    final bbox = (minLng - pad, minLat - pad, maxLng + pad, maxLat + pad);

    try {
      final pois = await _ref.read(poiRepositoryProvider).fetchInBoundingBox(
            minLng: bbox.$1,
            minLat: bbox.$2,
            maxLng: bbox.$3,
            maxLat: bbox.$4,
            categories: {PoiCategory.speedCamera},
          );
      if (_disposed) return;
      state = state.copyWith(
        cameras: pois.map((p) => (lat: p.lat, lng: p.lng)).toList(growable: false),
        clearWarning: true,
      );
    } catch (_) {
      // Keine Blitzer-Daten ist kein Navigationsfehler - Stillstand des
      // Warners (die Navigation läuft unbeeinflusst weiter).
      if (_disposed) return;
      state = state.copyWith(cameras: const [], clearWarning: true);
    }
  }

  /// GPS-Fix-Check: nächste Kamera innerhalb der Warndistanz?
  Future<void> onPosition(double lat, double lng, {double speedMps = 0}) async {
    if (state.cameras.isEmpty) return;

    double best = double.infinity;
    int bestIdx = -1;
    for (var i = 0; i < state.cameras.length; i++) {
      final c = state.cameras[i];
      final d = _haversine(lat, lng, c.lat, c.lng);
      if (d < best) {
        best = d;
        bestIdx = i;
      }
    }
    if (bestIdx < 0) return;

    // Kamera weit weg: offene Warnung aufräumen - BEVOR der Cooldown
    // greift, sonst bliebe der Banner stehen (Cleanup ist kein Alarm).
    if (best > passedDistanceMeters) {
      if (state.activeWarning != null) {
        state = state.copyWith(clearWarning: true);
      }
      return;
    }

    // Cooldown sperrt nur NEUE Alarme, nicht das Aufräumen oben.
    if (_cooldown != null) return;

    final warnDistance =
        speedMps > 14 ? warnDistanceMeters : warnDistanceSlowMeters; // > 50 km/h

    if (best <= warnDistance && !state.warnedIndices.contains(bestIdx)) {
      // Alarm! Einmal pro Kamera, dann Cooldown gegen Kettenalarme.
      _cooldown = Timer(const Duration(seconds: 4), () => _cooldown = null);
      state = state.copyWith(
        activeWarning: SpeedCameraWarning(distanceMeters: best, lat: state.cameras[bestIdx].lat, lng: state.cameras[bestIdx].lng),
        warnedIndices: {...state.warnedIndices, bestIdx},
      );
      await _vibrate();
    }
  }

  Future<void> _vibrate() async {
    try {
      if (await Vibration.hasVibrator() != true) return;
      await Vibration.vibrate(pattern: [300, 200, 300]);
    } catch (_) {
      // Vibration ist Best-Effort (Emulator, fehlende Permission ...).
    }
  }

  double _haversine(double lat1, double lng1, double lat2, double lng2) {
    const R = 6371000.0;
    final dLat = _rad(lat2 - lat1);
    final dLng = _rad(lng2 - lng1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_rad(lat1)) * math.cos(_rad(lat2)) * math.sin(dLng / 2) * math.sin(dLng / 2);
    return 2 * R * math.asin(math.sqrt(a));
  }

  double _rad(double deg) => deg * math.pi / 180;

  @override
  void dispose() {
    _disposed = true;
    _cooldown?.cancel();
    super.dispose();
  }
}

final speedCameraWarnerProvider =
    StateNotifierProvider.autoDispose<SpeedCameraWarnerController, SpeedCameraState>(
  (ref) => SpeedCameraWarnerController(ref),
);

/// Warntext für den Navigation-Banner ("Blitzer in 90 m").
String speedCameraBannerText(SpeedCameraWarning w) {
  final meters = w.distanceMeters.round();
  if (meters >= 1000) return 'Blitzer in ${(meters / 1000).toStringAsFixed(1)} km';
  return 'Blitzer in $meters m';
}
