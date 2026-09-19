import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:motoroute_app/core/network/api_client.dart';

/// Suchergebnis - Spiegel von SearchResult aus
/// motoroute_api/src/modules/search (Photon-Proxy).
class SearchResult {
  final String label;
  final double lat;
  final double lng;
  final bool isPoi;
  final String? postcode;
  final String? city;

  const SearchResult({
    required this.label,
    required this.lat,
    required this.lng,
    required this.isPoi,
    this.postcode,
    this.city,
  });

  factory SearchResult.fromJson(Map<String, dynamic> json) => SearchResult(
        label: json['label'] as String,
        lat: (json['lat'] as num).toDouble(),
        lng: (json['lng'] as num).toDouble(),
        isPoi: json['type'] == 'POI',
        postcode: json['postcode'] as String?,
        city: json['city'] as String?,
      );
}

/// Zielsuche über das eigene Backend (GET /v1/search), das Photon/
/// Nominatim kapselt. Die App kennt den Geocoding-Anbieter nie - nur
/// das BFF (Kommunikationsprinzip Phase 1/2 Teil C).
class SearchRepository {
  final Dio _dio;

  SearchRepository(this._dio);

  Future<List<SearchResult>> search(String query, {double? nearLat, double? nearLng}) async {
    // Backend liefert ein reines JSON-Array (SearchResult[]) - daher
    // bewusst untypisiert empfangen und selbst verifizieren.
    final response = await _dio.get<dynamic>(
      '/v1/search',
      queryParameters: {
        'q': query,
        if (nearLat != null && nearLng != null) 'near': '$nearLat,$nearLng',
      },
    );

    final data = response.data;
    final List<dynamic> items;
    if (data is List) {
      items = data;
    } else if (data is Map && data['items'] is List) {
      items = data['items'] as List<dynamic>;
    } else {
      items = const [];
    }
    return items
        .map((e) => SearchResult.fromJson(e as Map<String, dynamic>))
        .toList(growable: false);
  }
}

final searchRepositoryProvider = Provider<SearchRepository>((ref) {
  return SearchRepository(ApiClient.create());
});

/// Nicht-synchronisierter Such-State: der Controller entscheidet, wann
/// gesucht wird (debounced on-change + submit), der Screen rendert nur.
class SearchState {
  final bool isLoading;
  final String? error;
  final List<SearchResult> results;
  final bool hasSearched;

  const SearchState({
    this.isLoading = false,
    this.error,
    this.results = const [],
    this.hasSearched = false,
  });

  SearchState copyWith({
    bool? isLoading,
    String? error,
    List<SearchResult>? results,
    bool? hasSearched,
  }) =>
      SearchState(
        isLoading: isLoading ?? this.isLoading,
        error: error,
        results: results ?? this.results,
        hasSearched: hasSearched ?? this.hasSearched,
      );
}

class SearchController extends StateNotifier<SearchState> {
  final SearchRepository _repository;

  SearchController(this._repository) : super(const SearchState());

  Future<void> submit(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      state = const SearchState();
      return;
    }
    state = SearchState(isLoading: true, hasSearched: true);
    try {
      final results = await _repository.search(trimmed);
      state = SearchState(results: results, hasSearched: true);
    } on DioException {
      state = const SearchState(
        error: 'Suche nicht erreichbar - bitte Verbindung prüfen',
        hasSearched: true,
      );
    } catch (_) {
      state = const SearchState(
        error: 'Suche fehlgeschlagen',
        hasSearched: true,
      );
    }
  }
}

final searchControllerProvider =
    StateNotifierProvider<SearchController, SearchState>((ref) {
  return SearchController(ref.watch(searchRepositoryProvider));
});
