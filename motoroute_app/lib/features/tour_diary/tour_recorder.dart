import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../../core/utils/geo.dart';
import '../map/data/location_repository.dart';
import '../settings/energy_saver.dart' show energySaverControllerProvider;
import 'domain/tour_entities.dart';
import 'tour_diary_providers.dart' show tourDatabaseProvider;
import '../map/data/location_repository.dart'
    show locationRepositoryProvider;

/// Live-Aufzeichnung einer Fahrt: sammelt GPS-Punkte, gefahrene
/// Kilometer, Höhenmeter und verstrichene Zeit. Bewusst VOM Navigations-
/// Controller getrennt - die Aufzeichnung läuft mit, ohne deren
/// Rerouting/Statistik-Logik zu stören, und könnte später auch freie
/// Fahrten ohne Route aufzeichnen.
///
/// Speichern passiert AUSSCHLIESSLICH bei [stop] (ein Insert pro Fahrt);
/// während der Fahrt bleiben die Punkte im RAM - keine DB-Last, kein
/// Schreib-Amplification auf dem Gerät.
class TourRecorderState {
  final bool isRecording;
  final List<TrackPoint> points;
  final double distanceMeters;
  final double elevationGainMeters;
  final DateTime? startedAt;

  const TourRecorderState({
    this.isRecording = false,
    this.points = const [],
    this.distanceMeters = 0,
    this.elevationGainMeters = 0,
    this.startedAt,
  });

  double get durationSeconds {
    // Sekunden seit Start - live gemessen, nicht aus Punkten abgeleitet
    // (der GPS-Stream stockt bei Stillstand, die Zeit läuft weiter).
    final start = startedAt;
    if (start == null) return 0;
    return DateTime.now().difference(start).inMilliseconds / 1000;
  }

  TourRecorderState copyWith({
    bool? isRecording,
    List<TrackPoint>? points,
    double? distanceMeters,
    double? elevationGainMeters,
    DateTime? startedAt,
  }) =>
      TourRecorderState(
        isRecording: isRecording ?? this.isRecording,
        points: points ?? this.points,
        distanceMeters: distanceMeters ?? this.distanceMeters,
        elevationGainMeters: elevationGainMeters ?? this.elevationGainMeters,
        startedAt: startedAt ?? this.startedAt,
      );
}

class TourRecorderController extends StateNotifier<TourRecorderState> {
  final Ref _ref;
  final LocationRepository _locationRepository;
  StreamSubscription<Position>? _positionSubscription;

  /// Mindest-Abstand zwischen zwei gespeicherten Punkten - verhindert,
  /// dass Stillstand (Ampel) tausende identische Punkte erzeugt.
  static const _minPointDistanceMeters = 8.0;

  TourRecorderController(this._ref, this._locationRepository)
      : super(const TourRecorderState());

  void start() {
    if (state.isRecording) return;
    state = TourRecorderState(
      isRecording: true,
      points: const [],
      distanceMeters: 0,
      elevationGainMeters: 0,
      startedAt: DateTime.now(),
    );
    _subscribe();
  }

  void _subscribe() {
    _positionSubscription?.cancel();
    final tuning = _ref.read(energySaverControllerProvider.notifier).locationTuning;
    _positionSubscription = _locationRepository.watchPosition(tuning: tuning).listen(
          _onPosition,
          // Aufzeichnung darf Navigation-Fehler nicht verschlimmern:
          // still weitermachen, der nächste Fix kommt.
          onError: (Object _) {},
        );
  }

  void _onPosition(Position position) {
    if (!state.isRecording) return;
    final points = state.points;
    if (points.isNotEmpty) {
      final last = points.last;
      final d = haversineMeters(last.lat, last.lng, position.latitude, position.longitude);
      if (d < _minPointDistanceMeters) return; // Stillstand/Rauschen
    }

    final ele = position.altitude;
    final hasEle = ele.isFinite && !ele.isNaN;
    final point = TrackPoint(
      lat: position.latitude,
      lng: position.longitude,
      elevationMeters: hasEle ? ele : null,
      secondsSinceStart: state.durationSeconds,
    );

    double distance = state.distanceMeters;
    double gain = state.elevationGainMeters;
    if (points.isNotEmpty) {
      final last = points.last;
      distance += haversineMeters(last.lat, last.lng, point.lat, point.lng);
    }
    if (hasEle) {
      for (var i = points.length - 1; i >= 0; i--) {
        final prev = points[i].elevationMeters;
        if (prev != null) {
          if (ele > prev) gain += ele - prev;
          break;
        }
      }
    }

    state = state.copyWith(
      points: [...points, point],
      distanceMeters: distance,
      elevationGainMeters: gain,
    );
  }

  /// Beendet die Aufzeichnung und speichert die Tour. Liefert die
  /// gespeicherte Tour zurück - oder null bei zu wenigen Punkten
  /// (z. B. sofort abgebrochen); eine 2-Punkte-"Tour" wäre Müll.
  Future<RecordedTour?> stop({
    String? title,
    List<TourPoiRef> pois = const [],
  }) async {
    if (!state.isRecording) return null;
    _positionSubscription?.cancel();
    _positionSubscription = null;

    final points = state.points;
    final started = state.startedAt;
    if (points.length < 5 || started == null) {
      state = const TourRecorderState();
      return null;
    }

    final ended = DateTime.now();
    final durationSec = ended.difference(started).inMilliseconds / 1000;
    final tour = RecordedTour(
      title: title ?? _defaultTitle(started),
      startedAt: started,
      endedAt: ended,
      distanceMeters: state.distanceMeters,
      elevationGainMeters: state.elevationGainMeters,
      durationSeconds: durationSec,
      track: points,
      pois: pois,
    );

    final id = await _ref.read(tourDatabaseProvider).insertTour(tour);
    state = const TourRecorderState();
    return tour.copyWith(id: id);
  }

  /// Aufzeichnung verwerfen (ohne Speichern) - z. B. bei < 5 Punkten.
  void discard() {
    _positionSubscription?.cancel();
    _positionSubscription = null;
    state = const TourRecorderState();
  }

  String _defaultTitle(DateTime start) {
    String two(int v) => v.toString().padLeft(2, '0');
    return 'Tour ${two(start.day)}.${two(start.month)}.${start.year}';
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    super.dispose();
  }
}

final tourRecorderProvider =
    StateNotifierProvider<TourRecorderController, TourRecorderState>((ref) {
  return TourRecorderController(ref, ref.watch(locationRepositoryProvider));
});
