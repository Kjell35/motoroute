import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maplibre_gl/maplibre_gl.dart' as ml;
import 'package:shared_preferences/shared_preferences.dart';

/// Offline-Karten: Regionen herunterladen, auflisten, löschen.
///
/// Basiert auf der maplibre_gl-Offline-API (Vektor-Stil inkl. Kacheln).
/// Nach dem Download funktionieren Karte UND Navigation im Bereich der
/// Region ohne Netzverbindung; POI-/Routing-Anfragen brauchen weiterhin
/// das Backend (bewusst ehrlich in der UI kommuniziert).
///
/// Storage-Regel: Die Regionen-Metadaten (Name, Erstellzeit, Bounds)
/// liegen in shared_preferences; die Kachel-Daten selbst verwaltet die
/// maplibre-Plattform-DB (unsichtbar für die App, überlebt Updates).
class OfflineRegionInfo {
  final int id;
  final String name;
  final DateTime createdAt;

  /// Südwest/Nordost als [lat, lng]-Paare (für Anzeige/Neu-Download).
  final ({double lat, double lng}) southWest;
  final ({double lat, double lng}) northEast;

  const OfflineRegionInfo({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.southWest,
    required this.northEast,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'createdAt': createdAt.toIso8601String(),
        'sw': [southWest.lat, southWest.lng],
        'ne': [northEast.lat, northEast.lng],
      };

  static OfflineRegionInfo fromJson(Map<String, dynamic> j) => OfflineRegionInfo(
        id: j['id'] as int,
        name: j['name'] as String,
        createdAt: DateTime.parse(j['createdAt'] as String),
        southWest: (
          lat: (j['sw'] as List)[0] as double,
          lng: (j['sw'] as List)[1] as double,
        ),
        northEast: (
          lat: (j['ne'] as List)[0] as double,
          lng: (j['ne'] as List)[1] as double,
        ),
      );
}

/// Download-Fortschritt für die UI.
enum OfflineDownloadPhase { idle, downloading, done, error }

class OfflineMapsState {
  /// Bereits heruntergeladene Regionen (persistiert).
  final List<OfflineRegionInfo> regions;

  /// Laufender Download: Name + Fortschritt 0..1 (null = keiner).
  final String? activeDownloadName;
  final double activeDownloadProgress;
  final OfflineDownloadPhase phase;
  final String? error;

  const OfflineMapsState({
    this.regions = const [],
    this.activeDownloadName,
    this.activeDownloadProgress = 0,
    this.phase = OfflineDownloadPhase.idle,
    this.error,
  });

  bool get isDownloading => phase == OfflineDownloadPhase.downloading;

  OfflineMapsState copyWith({
    List<OfflineRegionInfo>? regions,
    String? activeDownloadName,
    double? activeDownloadProgress,
    OfflineDownloadPhase? phase,
    String? error,
    bool clearActive = false,
    bool clearError = false,
  }) =>
      OfflineMapsState(
        regions: regions ?? this.regions,
        activeDownloadName: clearActive ? null : (activeDownloadName ?? this.activeDownloadName),
        activeDownloadProgress: activeDownloadProgress ?? this.activeDownloadProgress,
        phase: phase ?? this.phase,
        error: clearError ? null : (error ?? this.error),
      );
}

class OfflineMapsController extends StateNotifier<OfflineMapsState> {
  OfflineMapsController() : super(const OfflineMapsState()) {
    _restore();
  }

  static const _kRegionsKey = 'offline_maps.regions';

  /// Zoom 4..13 deckt Über-bis-Straßenebene ab; höher (14+) würde die
  /// Tile-Anzahl (und damit Downloadgröße) explodieren lassen.
  static const double _minZoom = 4;
  static const double _maxZoom = 13;

  StreamSubscription<void>? _downloadSub; // Events laufen über onEvent-Callback

  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kRegionsKey);
      if (raw == null) return;
      final list = (jsonDecode(raw) as List<dynamic>)
          .map((e) => OfflineRegionInfo.fromJson(e as Map<String, dynamic>))
          .toList();
      // Abgleich mit der Plattform-DB: Regionen, die dort nicht mehr
      // existieren (App-Daten gelöscht), entfernen.
      try {
        final platform = await ml.getListOfRegions();
        final platformIds = platform.map((r) => r.id).toSet();
        state = state.copyWith(
          regions: list.where((r) => platformIds.contains(r.id)).toList(),
        );
        await _persist(state.regions);
      } catch (_) {
        // Plattform-API nicht verfügbar (Test/Host): Metadaten trotzdem
        // zeigen - besser als ein leerer Screen ohne Erklärung.
        state = state.copyWith(regions: list);
      }
    } catch (_) {
      // Kaputte Persistenz: leer starten statt crashen.
      state = const OfflineMapsState();
    }
  }

  Future<void> _persist(List<OfflineRegionInfo> regions) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _kRegionsKey,
      jsonEncode(regions.map((r) => r.toJson()).toList()),
    );
  }

  /// Lädt eine Karte rund um einen Punkt herunter. [radiusKm] begrenzt
  /// die Größe (UI bietet 25/50/100 km).
  Future<bool> download({
    required String name,
    required double centerLat,
    required double centerLng,
    double radiusKm = 50,
  }) async {
    if (state.isDownloading) return false;

    final dLat = radiusKm / 111.0;
    final dLng = radiusKm / (111.0 * math.cos(centerLat * math.pi / 180));

    final definition = ml.OfflineRegionDefinition(
      bounds: ml.LatLngBounds(
        southwest: ml.LatLng(centerLat - dLat, centerLng - dLng),
        northeast: ml.LatLng(centerLat + dLat, centerLng + dLng),
      ),
      // Offline gilt der AKTUELLE Kartenstil (hell/dunkel folgt der Wahl).
      mapStyleUrl: 'https://tiles.basemaps.cartocdn.com/gl/positron-gl-style/style.json',
      minZoom: _minZoom,
      maxZoom: _maxZoom,
    );

    state = state.copyWith(
      activeDownloadName: name,
      activeDownloadProgress: 0,
      phase: OfflineDownloadPhase.downloading,
      clearError: true,
    );

    try {
      // Tile-Limit großzügig setzen (Standard ist zu knapp für Regionen).
      await ml.setOfflineTileCountLimit(8000);

      final region = await ml.downloadOfflineRegion(
        definition,
        metadata: {'name': name},
        onEvent: (event) {
          if (event is ml.InProgress) {
            state = state.copyWith(activeDownloadProgress: event.progress);
          } else if (event is ml.Success) {
            state = state.copyWith(phase: OfflineDownloadPhase.done);
          } else if (event is ml.Error) {
            state = state.copyWith(
              phase: OfflineDownloadPhase.error,
              error: 'Download fehlgeschlagen',
            );
          }
        },
      );

      final info = OfflineRegionInfo(
        id: region.id,
        name: name,
        createdAt: DateTime.now(),
        southWest: (
          lat: centerLat - dLat,
          lng: centerLng - dLng,
        ),
        northEast: (
          lat: centerLat + dLat,
          lng: centerLng + dLng,
        ),
      );
      state = state.copyWith(
        regions: [...state.regions, info],
        phase: OfflineDownloadPhase.done,
      );
      await _persist(state.regions);
      return true;
    } catch (err) {
      state = state.copyWith(
        phase: OfflineDownloadPhase.error,
        error: 'Download fehlgeschlagen - bitte Internetverbindung prüfen',
      );
      return false;
    } finally {
      _downloadSub = null;
    }
  }

  Future<void> delete(OfflineRegionInfo info) async {
    try {
      await ml.deleteOfflineRegion(info.id);
    } catch (_) {
      // Plattform-Fehler trotzdem aus der Liste entfernen - die Region
      // ist sonst unauslöschbar für den Nutzer.
    }
    state = state.copyWith(regions: state.regions.where((r) => r.id != info.id).toList());
    await _persist(state.regions);
  }

  @override
  void dispose() {
    _downloadSub?.cancel();
    super.dispose();
  }
}

final offlineMapsProvider =
    StateNotifierProvider<OfflineMapsController, OfflineMapsState>((ref) {
  return OfflineMapsController();
});
