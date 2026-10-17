import 'dart:async';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import '../../core/state/app_providers.dart';
import 'poi_offline_cache.dart';
import 'poi_offline_sync.dart';
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

  /// Rohwert der Dienst-Kategorie (eine der 8 Biker-Kategorien, z. B.
  /// 'gartenlokal'). Das App-UI mappt weiter auf 6 Kategorien - dieser
  /// Wert bleibt für die lokale Offline-DB und Dienst-Statistiken
  /// erhalten. Null bei älteren Caches ohne das Feld.
  final BikerPoiSourceCategory? sourceCategory;

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
    this.sourceCategory,
  });

  /// Öffentliche Brücke: BFF-App-Kategorie (z. B. 'PUB') -> PoiCategory.
  /// Der private Extension-Zugriff ist bibliotheksprivat - der Karten-
  /// Layer konvertiert SQLite-Zeilen über diesen statischen Weg.
  static PoiCategory categoryOfWire(String wire) => wire._asPoiCategory;

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
        sourceCategory: BikerPoiSourceCategory.tryParse(json['sourceCategory'] as String?),
      );
}

/// Persistenter Delta-Sync gegen /v1/biker-pois/sync.
///
/// Wie es funktioniert:
/// - [OfflineSyncService] (gleicher Ordner) macht die eigentliche Arbeit:
///   Verbindungsprobe, Delta-Sync mit Pagination, Persistenz in SQLite
///   (motoroute_pois.db), Cursor in SharedPreferences.
/// - Dieser Controller ist die State-Brücke zum Karten-Layer: Er restoret
///   den DB-Bestand beim App-Start, stößt Syncs (Intervall/Push/Reconnect)
///   an und spiegelt die POIs in den Riverpod-State - NUR bei tatsächlichen
///   Datenänderungen, damit der Layer nicht bei jedem 10-Minuten-Takt
///   ohne Grund neu zeichnet.
/// - OSM-POIs aus dem BFF bleiben unverändert erhalten, Biker-POIs ERGÄN-
///   zen die Karte (verschiedene Namensräume via id-Präfix `biker-`).
class BikerPoiSyncController extends StateNotifier<BikerPoiSyncState> {
  /// Offline-Sync: Verbindungsprobe, Delta-Sync, SQLite-Persistenz. Der
  /// Controller wird zur reinen State-Brücke (Karten-Layer) — die
  /// Datenquelle ist die lokale Datenbank (auch offline).
  final OfflineSyncService offline;

  BikerPoiSyncController(
    Dio dio, {
    OfflineSyncService? offlineSync,
    PoiOfflineDatabase? database,
    ConnectivityProbe? probe,
  })  : offline = offlineSync ??
            OfflineSyncService(
              dio: dio,
              database: database ?? PoiOfflineDatabase(),
              probe: probe,
            ),
        super(const BikerPoiSyncState());

  /// Aktive Kategorien des Biker-Dienstes - wird vom Karten-Layer gelesen,
  /// um die Delta-Filterung konsistent zur UI zu halten.
  Set<PoiCategory> activeCategories = PoiCategoryApi.bikerServiceCategories;

  /// App-Start: Bestand aus SQLite in den State restoren (Offline-
  /// Verfügbarkeit ohne Wartezeit auf den ersten Sync).
  Future<void> restoreCache() async {
    final rows = await offline.database.getAllBikerPois();
    state = state.copyWith(
      pois: rows.map(_bikerPoiOf).toList(growable: false),
      cursor: await offline.readCursor(),
    );
  }

  BikerPoi _bikerPoiOf(CachedBikerPoi row) => BikerPoi(
        id: row.id,
        category: row.appCategory._asPoiCategory,
        name: row.name,
        lat: row.lat,
        lng: row.lng,
        source: 'BIKER_SERVICE',
        bikerScore: row.bikerScore,
        motorcycleParking: row.motorcycleParking,
        meetingPoint: row.meetingPoint,
        sourceCategory: row.sourceCategory,
      );

  /// Führt einen Delta-Sync durch (Probe → Delta → SQLite). [lat]/[lng]/
  /// [radiusKm] optional für Umkreis-Filterung (Kartenmittelpunkt). Der
  /// State wird nur aktualisiert, wenn der Sync neue Daten brachte -
  /// offline (still) und error ändern die POIs nicht.
  Future<void> sync({double? lat, double? lng, double? radiusKm}) async {
    if (state.isSyncing) return;
    state = state.copyWith(isSyncing: true, error: null);
    try {
      final result = await offline.sync(
        lat: lat,
        lng: lng,
        radiusKm: radiusKm,
        categories: activeCategories.map((c) => c.apiValue).toSet(),
      );
      if (_disposed) return;
      if (result != OfflineSyncResult.ok) {
        // offline (stiller Offline-Pfad, Karte läuft aus SQLite weiter)
        // oder error (UI darf warnen): POIs bleiben, wie sie sind.
        state = state.copyWith(
          isSyncing: false,
          error: switch (result) {
            OfflineSyncResult.offline => null,
            _ => 'Biker-POIs konnten nicht synchronisiert werden',
          },
        );
        return;
      }
      if (!offline.lastSyncChangedData) {
        // Delta ohne Änderungen: kein State-Update -> der Karten-Layer
        // zeichnet nicht neu (10-Minuten-Takt mit identischem Stand).
        state = state.copyWith(isSyncing: false, error: null);
        return;
      }
      final rows = await offline.database.getAllBikerPois();
      if (_disposed) return;
      state = state.copyWith(
        pois: rows.map(_bikerPoiOf).toList(growable: false),
        cursor: await offline.readCursor(),
        isSyncing: false,
        error: null,
      );
    } catch (_) {
      if (_disposed) return;
      state = state.copyWith(
        isSyncing: false,
        error: 'Biker-POIs konnten nicht synchronisiert werden',
      );
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
    offline.dispose();
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
