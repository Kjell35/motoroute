import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/network/api_client.dart';
import '../../core/state/app_providers.dart';
import 'poi_providers.dart';

extension _PoiCategoryParse on String {
  PoiCategory get _asPoiCategory => switch (this) {
        'FUEL' => PoiCategory.fuel,
        'MOTO_HOTEL' => PoiCategory.motoHotel,
        'BIKER_MEETUP' => PoiCategory.bikerMeetup,
        'CAMPSITE' => PoiCategory.campsite,
        'ICE_CREAM' => PoiCategory.iceCream,
        'SPEED_CAMERA' => PoiCategory.speedCamera,
        'RESTAURANT' => PoiCategory.restaurant,
        'PUB' => PoiCategory.pub,
        'SNACK' => PoiCategory.snack,
        _ => PoiCategory.restaurant,
      };
}

/// Ergebniszeile des Biker-POI-Dienstes (BFF /v1/biker-pois/sync).
/// Erweitert den OSM-Poi um den BIKER-SCORE - das Alleinstellungsmerkmal
/// des TomTom-Kuratierungs-Dienstes („Wie bikertauglich ist der Laden?").
class BikerPoi extends Poi {
  final int bikerScore;
  final bool motorcycleParking;
  final bool meetingPoint;

  const BikerPoi({
    required super.id,
    required super.category,
    required super.name,
    required super.lat,
    required super.lng,
    required super.source,
    required this.bikerScore,
    required this.motorcycleParking,
    required this.meetingPoint,
  });

  factory BikerPoi.fromJson(Map<String, dynamic> json) => BikerPoi(
        id: json['id'] as String,
        category: (json['category'] as String)._asPoiCategory,
        name: (json['name'] as String?) ?? '',
        lat: (json['lat'] as num).toDouble(),
        lng: (json['lon'] as num).toDouble(),
        source: 'BIKER_SERVICE',
        bikerScore: (json['bikerScore'] ?? 0) as int,
        motorcycleParking:
            ((json['amenities'] as Map<String, dynamic>?)?['motorcycle_parking'] ?? false) as bool,
        meetingPoint:
            ((json['amenities'] as Map<String, dynamic>?)?['meeting_point'] ?? false) as bool,
      );
}

/// Persistenter Delta-Sync gegen /v1/biker-pois/sync.
///
/// Wie es funktioniert:
/// - Beim Start wird `since` = letzter gespeicherter Cursor geladen
///   (SharedPreferences). Beim ersten Mal: Epoch → der Dienst liefert
///   ALLE aktiven POIs der gefilterten Kategorien (max. 2000 pro Call,
///   danach über hasMore/Cursor nachziehen).
/// - Jede Antwort aktualisiert den Cursor auf den serverseitigen Stand;
///   gecachte POIs werden in einer lokalen Box (JSON im SharedPreferences)
///   gehalten und dem Karten-Layer als MERGE übergeben - OSM-POIs aus dem
///   BFF bleiben unverändert erhalten, Biker-POIs überlagern sie nicht,
///   sondern ERGÄNZEN die Karte (verschiedene Namensräume via id-Präfix).
/// - Offline: gecachte POIs bleiben verfügbar (Abschnitt 37 der Chat-
///   Vorgabe analog hier), der Sync versucht es beim nächsten Start wieder.
class BikerPoiSyncController extends StateNotifier<BikerPoiSyncState> {
  final Dio _dio;
  static const _cursorKey = 'biker_poi.sync.cursor';
  static const _cacheKey = 'biker_poi.sync.cache';

  BikerPoiSyncController(this._dio) : super(const BikerPoiSyncState());

  /// Aktive Kategorien des Biker-Dienstes - wird vom Karten-Layer gelesen,
  /// um die Delta-Filterung konsistent zur UI zu halten.
  Set<PoiCategory> activeCategories = PoiCategoryApi.bikerServiceCategories;

  Future<void> restoreCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cursor = prefs.getString(_cursorKey);
      final raw = prefs.getString(_cacheKey);
      if (raw != null) {
        final list = (jsonDecode(raw) as List<dynamic>)
            .map((e) => BikerPoi.fromJson(e as Map<String, dynamic>))
            .toList();
        // Cache-Größenlimit: 5000 POIs reichen für einen Regionalsync;
        // bei Überschreitung älteste nach updatedAt verwerfen.
        final capped = list.length > 5000
            ? (list..sort((a, b) => a.id.compareTo(b.id))).sublist(0, 5000)
            : list;
        state = state.copyWith(pois: capped, cursor: cursor ?? state.cursor);
      } else {
        state = state.copyWith(cursor: cursor);
      }
    } catch (_) {
      // Kaputter Cache: neu synchronisieren statt crashen.
      state = const BikerPoiSyncState();
    }
  }

  /// Führt einen Delta-Sync durch. [lat]/[lng]/[radiusKm] optional für
  /// Umkreis-Filterung (Kartenmittelpunkt).
  Future<void> sync({double? lat, double? lng, double? radiusKm}) async {
    if (state.isSyncing) return;
    state = state.copyWith(isSyncing: true, error: null);
    try {
      final since = state.cursor ?? '1970-01-01T00:00:00.000Z';
      final response = await _dio.get<Map<String, dynamic>>(
        '/v1/biker-pois/sync',
        queryParameters: {
          'since': since,
          if (lat != null && lng != null && radiusKm != null) ...{
            'lat': lat,
            'lon': lng,
            'radiusKm': radiusKm,
          },
          'categories': activeCategories.map((c) => c.apiValue).join(','),
        },
      );

      final upserted = ((response.data?['pois'] as List<dynamic>? ?? []))
          .map((e) => BikerPoi.fromJson(e as Map<String, dynamic>))
          .toList();
      final deletedIds = Set<String>.from(response.data?['deletedIds'] as List<dynamic>? ?? []);
      final newCursor = response.data?['since'] as String?;

      // Merge: alte rausschmeißen (deleted + aktualisierte), neue rein.
      final merged = Map<String, BikerPoi>.fromEntries(
        state.pois.map((p) => MapEntry(p.id, p)),
      );
      for (final id in deletedIds) {
        merged.remove(id);
      }
      for (final poi in upserted) {
        merged[poi.id] = poi;
      }

      final pois = merged.values.toList(growable: false);
      state = state.copyWith(pois: pois, cursor: newCursor, isSyncing: false);

      // Cursor + Cache persistieren (Offline-Verfügbarkeit, Abschnitt 37).
      try {
        final prefs = await SharedPreferences.getInstance();
        if (newCursor != null) await prefs.setString(_cursorKey, newCursor);
        await prefs.setString(
          _cacheKey,
          jsonEncode(pois.take(5000).map((p) => {
                'id': p.id,
                'name': p.name,
                'category': p.category.apiValue,
                'lat': p.lat,
                'lon': p.lng,
                'bikerScore': p.bikerScore,
                'amenities': {
                  'motorcycle_parking': p.motorcycleParking,
                  'meeting_point': p.meetingPoint,
                },
              }).toList()),
        );
      } catch (_) {
        // Persistenz-Fehler: Sync bleibt trotzdem erfolgreich.
      }
    } on DioException catch (e) {
      if (_disposed) return;
      // 503 = Dienst nicht konfiguriert: kein Fehler, kein Retry-Sturm -
      // die Karte läuft mit OSM-POIs weiter.
      final unavailable = e.response?.statusCode == 503;
      state = state.copyWith(
        isSyncing: false,
        error: unavailable ? null : 'Biker-POIs konnten nicht synchronisiert werden',
      );
    } catch (_) {
      if (_disposed) return;
      state = state.copyWith(isSyncing: false, error: 'Biker-POIs konnten nicht synchronisiert werden');
    }
  }

  /// Server-Push (bikerpoi.batch über /v1/chat/ws): betroffene IDs
  /// SOFORT aus dem Delta-Sync nachziehen - ohne das 10-Minuten-Intervall
  /// abzuwarten. Der Sync bleibt die Datenquelle (server-autoritativ);
  /// das Batch-Frame selbst enthält nur IDs, keine Nutzdaten.
  ///
  /// Läuft ein Sync bereits, wird die IDs-Menge gemerkt und nach dessen
  /// Abschluss erneut gezogen - kein verlorener Push, kein konkurrierender
  /// Schreibzugriff auf [state].
  Future<void> applyPush(Set<String> ids) async {
    if (ids.isEmpty || _disposed) return;
    if (state.isSyncing) {
      _pushBacklog.addAll(ids);
      _scheduleBacklogFlush();
      return;
    }
    await sync();
    if (_pushBacklog.isNotEmpty) _scheduleBacklogFlush();
  }

  final Set<String> _pushBacklog = {};
  Timer? _backlogTimer;

  void _scheduleBacklogFlush() {
    _backlogTimer?.cancel();
    _backlogTimer = Timer(const Duration(milliseconds: 500), () {
      if (_disposed || _pushBacklog.isEmpty) return;
      if (state.isSyncing) {
        _scheduleBacklogFlush(); // Sync läuft noch - später erneut versuchen.
        return;
      }
      _pushBacklog.clear();
      sync();
    });
  }

  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    _backlogTimer?.cancel();
    super.dispose();
  }
}

class BikerPoiSyncState {
  final List<BikerPoi> pois;
  final String? cursor;
  final bool isSyncing;
  final String? error;

  const BikerPoiSyncState({
    this.pois = const [],
    this.cursor,
    this.isSyncing = false,
    this.error,
  });

  BikerPoiSyncState copyWith({
    List<BikerPoi>? pois,
    String? cursor,
    bool? isSyncing,
    String? error,
  }) =>
      BikerPoiSyncState(
        pois: pois ?? this.pois,
        cursor: cursor ?? this.cursor,
        isSyncing: isSyncing ?? this.isSyncing,
        error: error,
      );
}

final bikerPoiSyncProvider =
    StateNotifierProvider<BikerPoiSyncController, BikerPoiSyncState>((ref) {
  return BikerPoiSyncController(ApiClient.create());
});

/// Distanz in Metern (für Umkreis-Vergleiche im Layer-Merge) - Haversine.
double distanceMeters(double lat1, double lng1, double lat2, double lng2) {
  const earthRadius = 6371000.0;
  final dLat = _degToRad(lat2 - lat1);
  final dLng = _degToRad(lng2 - lng1);
  final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(_degToRad(lat1)) * math.cos(_degToRad(lat2)) * math.sin(dLng / 2) * math.sin(dLng / 2);
  return earthRadius * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
}

double _degToRad(double deg) => deg * math.pi / 180.0;
