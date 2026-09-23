import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'data/tour_repository.dart';
import 'domain/tour_entities.dart';

/// Singleton-Zugriff auf die Touren-DB. Lazy: die DB öffnet sich beim
/// ersten Zugriff (App-Startkosten niedrig halten).
final tourDatabaseProvider = Provider<TourDatabase>((ref) {
  final database = TourDatabase();
  ref.onDispose(() {
    database.db.then((d) => d.close()).catchError((_) {});
  });
  return database;
});

/// Unveränderlicher Listen-State des Tagebuchs.
class TourDiaryState {
  final bool isLoading;
  final String? error;
  final List<RecordedTour> tours;

  const TourDiaryState({
    this.isLoading = false,
    this.error,
    this.tours = const [],
  });

  TourDiaryState copyWith({bool? isLoading, String? error, List<RecordedTour>? tours}) =>
      TourDiaryState(
        isLoading: isLoading ?? this.isLoading,
        error: error,
        tours: tours ?? this.tours,
      );
}

class TourDiaryController extends StateNotifier<TourDiaryState> {
  TourDiaryController(this._ref) : super(const TourDiaryState(isLoading: true));

  final Ref _ref;

  Future<void> load() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final tours = await _ref.read(tourDatabaseProvider).getAllTours();
      if (!mounted) return;
      state = TourDiaryState(isLoading: false, tours: tours);
    } catch (e) {
      if (!mounted) return;
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> deleteTour(int id) async {
    await _ref.read(tourDatabaseProvider).deleteTour(id);
    state = state.copyWith(
      tours: state.tours.where((t) => t.id != id).toList(growable: false),
    );
  }

  /// Nach dem Speichern einer neuen Tour die Liste auffrischen.
  Future<void> refresh() => load();
}

final tourDiaryProvider =
    StateNotifierProvider<TourDiaryController, TourDiaryState>((ref) {
  return TourDiaryController(ref);
});

/// Aggregierte Statistiken über alle Touren (Kopf des Tagebuchs).
class TourSummary {
  final int count;
  final double totalKm;
  final double totalHours;
  final double totalElevationGain;

  const TourSummary({
    required this.count,
    required this.totalKm,
    required this.totalHours,
    required this.totalElevationGain,
  });
}

TourSummary summarizeTours(List<RecordedTour> tours) => TourSummary(
      count: tours.length,
      totalKm: tours.fold(0.0, (s, t) => s + t.distanceMeters / 1000),
      totalHours: tours.fold(0.0, (s, t) => s + t.durationSeconds / 3600),
      totalElevationGain: tours.fold(0.0, (s, t) => s + t.elevationGainMeters),
    );
