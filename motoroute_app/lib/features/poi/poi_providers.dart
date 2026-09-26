import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:motoroute_app/core/network/api_client.dart';
import 'package:motoroute_app/core/state/app_providers.dart';

/// POI auf der Karte - Spiegel der Poi-Entity des Backends. `source`
/// behält die OSM/COMMUNITY/CURATED-Unterscheidung bei, damit die App
/// später kuratierte Motorradhotels anders markieren kann als reine
/// OSM-Tankstellen (Produktunterscheidung aus Phase 1/2 Teil E).
class Poi {
  final String id;
  final PoiCategory category;
  final String name;
  final double lat;
  final double lng;
  final String source;

  const Poi({
    required this.id,
    required this.category,
    required this.name,
    required this.lat,
    required this.lng,
    required this.source,
  });

  factory Poi.fromJson(Map<String, dynamic> json) => Poi(
        id: json['id'] as String,
        category: (json['category'] as String).poiCategory,
        name: (json['name'] as String?) ?? '',
        lat: (json['lat'] as num).toDouble(),
        lng: (json['lng'] as num).toDouble(),
        source: (json['source'] as String?) ?? 'OSM',
      );
}

extension on String {
  PoiCategory get poiCategory => switch (this) {
        'FUEL' => PoiCategory.fuel,
        'MOTO_HOTEL' => PoiCategory.motoHotel,
        'BIKER_MEETUP' => PoiCategory.bikerMeetup,
        'CAMPSITE' => PoiCategory.campsite,
        'ICE_CREAM' => PoiCategory.iceCream,
        'SPEED_CAMERA' => PoiCategory.speedCamera,
        _ => PoiCategory.fuel,
      };
}

/// Detail-Daten eines POIs (GET /v1/pois/:id) - Basis für das
/// Detail-Sheet: Beschreibung, Website, Bild und Veröffentlichungs-Info.
class PoiDetail {
  final String id;
  final String category;
  final String name;
  final String source;
  final String? description;
  final String? website;
  final String? imageUrl;
  final int? bikerScore;
  final String? originTag;
  final String? publishedAt;
  final String? publishedBy;

  const PoiDetail({
    required this.id,
    required this.category,
    required this.name,
    required this.source,
    required this.description,
    required this.website,
    required this.imageUrl,
    required this.bikerScore,
    required this.originTag,
    required this.publishedAt,
    required this.publishedBy,
  });

  factory PoiDetail.fromJson(Map<String, dynamic> json) => PoiDetail(
        id: (json['id'] as String?) ?? '',
        category: (json['category'] as String?) ?? '',
        name: (json['name'] as String?) ?? '',
        source: (json['source'] as String?) ?? 'OSM',
        description: json['description'] as String?,
        website: json['website'] as String?,
        imageUrl: json['imageUrl'] as String?,
        bikerScore: (json['bikerScore'] as num?)?.toInt(),
        originTag: json['originTag'] as String?,
        publishedAt: json['publishedAt'] as String?,
        publishedBy: json['publishedBy'] as String?,
      );
}

class PoiRepository {
  final Dio _dio;

  PoiRepository(this._dio);

  /// Lädt POIs im Kartenausschnitt. bbox-Format:
  /// "minLng,minLat,maxLng,maxLat" (wie Backend-DTO).
  Future<List<Poi>> fetchInBoundingBox({
    required double minLng,
    required double minLat,
    required double maxLng,
    required double maxLat,
    required Set<PoiCategory> categories,
  }) async {
    if (categories.isEmpty) return const [];
    final response = await _dio.get<dynamic>(
      '/v1/pois',
      queryParameters: {
        'bbox': '$minLng,$minLat,$maxLng,$maxLat',
        'categories': categories.map((c) => c.apiValue).join(','),
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
    return items.map((e) => Poi.fromJson(e as Map<String, dynamic>)).toList(growable: false);
  }

  /// Detail-Daten für das POI-Sheet (404 -> PoiDetail?-null; das Sheet
  /// zeigt dann die Basis-Infos aus dem Karten-Treffer).
  Future<PoiDetail?> fetchDetail(String id) async {
    if (id.startsWith('biker-')) {
      // Biker-Service-Delta-POIs leben im App-Cache, nicht in der
      // poi-Tabelle - ohne serverseitige Zeile gibt es kein erweitertes
      // Detail; das Sheet fällt auf die Basis-Daten zurück.
      return null;
    }
    final res = await _dio.get<Map<String, dynamic>>('/v1/pois/$id');
    return PoiDetail.fromJson(res.data ?? const {});
  }
}

final poiRepositoryProvider = Provider<PoiRepository>((ref) {
  return PoiRepository(ApiClient.create());
});

/// Ergebnis eines POI-Layer-Loads - Fehler werden bewusst mitgeführt,
/// statt sie auf einen leeren Layer zu mappen: "Kein Netz" muss sich
/// auf der Karte von "gibt hier keine Tankstellen" unterscheiden.
class PoiLayerState {
  final List<Poi> pois;
  final bool isLoading;
  final String? error;

  const PoiLayerState({this.pois = const [], this.isLoading = false, this.error});

  PoiLayerState copyWith({List<Poi>? pois, bool? isLoading, String? error}) =>
      PoiLayerState(
        pois: pois ?? this.pois,
        isLoading: isLoading ?? this.isLoading,
        error: error,
      );
}

/// Lädt POIs für einen Kartenausschnitt neu (per Ref in der Karte
/// getriggert, wenn sich der Ausschnitt ändert oder Kategorien togglen).
class PoiLayerController extends StateNotifier<PoiLayerState> {
  final PoiRepository _repository;

  PoiLayerController(this._repository) : super(const PoiLayerState());

  Future<void> load({
    required double minLng,
    required double minLat,
    required double maxLng,
    required double maxLat,
    required Set<PoiCategory> categories,
  }) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final pois = await _repository.fetchInBoundingBox(
        minLng: minLng,
        minLat: minLat,
        maxLng: maxLng,
        maxLat: maxLat,
        categories: categories,
      );
      state = PoiLayerState(pois: pois);
    } on DioException {
      state = PoiLayerState(error: 'POIs nicht verfügbar - offline?');
    } catch (_) {
      state = PoiLayerState(error: 'POIs konnten nicht geladen werden');
    }
  }

  /// Spiegelt ein extern geladenes Ergebnis in den State (der Map-Layer
  /// lädt selbst - hier landen nur Resultate, kein interner ref-Zugriff).
  void adopt(List<Poi> pois) {
    state = PoiLayerState(pois: pois);
  }

  void reportError(String message) {
    state = PoiLayerState(error: message);
  }

  /// MERGE aus zwei Quellen (Abschnitt "Biker-POI-Dienst integrieren"):
  /// OSM-POIs (Live-Viewport-Abfrage) + Biker-POIs (Delta-Sync aus dem
  /// TomTom-Kuratierungs-Dienst). Dedupe über die POI-Id - Biker-POIs
  /// tragen das id-Präfix "biker-" und kollidieren daher nie mit OSM-
  /// UUIDs. Kategorien-Filter bleibt dieselbe UI-Quelle (beide Quellen
  /// werden über dieselben PoiCategory-Toggles gesteuert).
  void adoptMerged({required List<Poi> osmPois, required List<Poi> bikerPois}) {
    final merged = <String, Poi>{
      for (final p in bikerPois) p.id: p,
      for (final p in osmPois) p.id: p,
    };
    state = PoiLayerState(pois: merged.values.toList(growable: false));
  }
}

final poiLayerControllerProvider =
    StateNotifierProvider<PoiLayerController, PoiLayerState>((ref) {
  return PoiLayerController(ref.watch(poiRepositoryProvider));
});
