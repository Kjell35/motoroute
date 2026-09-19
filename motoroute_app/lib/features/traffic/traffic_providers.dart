import 'dart:async';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:motoroute_app/core/network/api_client.dart';
import 'package:motoroute_app/core/utils/geo.dart';

/// Kategorien - Spiegel des Backends (tomtom.mapper.ts). Wetter und
/// "Sonstiges" werden gemeldet, aber lösen KEIN proaktives Rerouting
/// aus (zu unkonkret für eine automatische Umleitung).
enum IncidentCategory {
  accident,
  jam,
  laneClosed,
  roadClosed,
  roadWorks,
  brokenDownVehicle,
  weather,
  other;

  static IncidentCategory fromApi(String value) => IncidentCategory.values
      .firstWhere((e) => e.apiName == value, orElse: () => IncidentCategory.other);

  String get apiName => switch (this) {
        IncidentCategory.accident => 'ACCIDENT',
        IncidentCategory.jam => 'JAM',
        IncidentCategory.laneClosed => 'LANE_CLOSED',
        IncidentCategory.roadClosed => 'ROAD_CLOSED',
        IncidentCategory.roadWorks => 'ROAD_WORKS',
        IncidentCategory.brokenDownVehicle => 'BROKEN_DOWN_VEHICLE',
        IncidentCategory.weather => 'WEATHER',
        IncidentCategory.other => 'OTHER',
      };

  /// Kategorien, die eine automatische Umleitung rechtfertigen - ein
  /// Stau/Laub/Wetter-Hinweis allein rechtfertigt keine Umleitung, die
  /// den Fahrspaß-Stil opfern würde.
  bool get blocksRoute => switch (this) {
        IncidentCategory.accident ||
        IncidentCategory.roadClosed ||
        IncidentCategory.jam ||
        IncidentCategory.laneClosed ||
        IncidentCategory.roadWorks ||
        IncidentCategory.brokenDownVehicle =>
          true,
        IncidentCategory.weather || IncidentCategory.other => false,
      };
}

enum IncidentSeverity { low, medium, high, unknown }

class TrafficIncident {
  final String id;
  final IncidentCategory category;
  final IncidentSeverity severity;
  final String? description;
  final String? from;
  final String? to;
  final List<List<double>> geometry; // [lng, lat]-Paare

  const TrafficIncident({
    required this.id,
    required this.category,
    required this.severity,
    required this.geometry,
    this.description,
    this.from,
    this.to,
  });

  factory TrafficIncident.fromJson(Map<String, dynamic> json) => TrafficIncident(
        id: json['id'] as String,
        category: IncidentCategory.fromApi((json['category'] as String?) ?? 'OTHER'),
        severity: switch (json['severity']) {
          'LOW' => IncidentSeverity.low,
          'MEDIUM' => IncidentSeverity.medium,
          'HIGH' => IncidentSeverity.high,
          _ => IncidentSeverity.unknown,
        },
        description: json['description'] as String?,
        from: json['from'] as String?,
        to: json['to'] as String?,
        geometry: (json['geometry'] as List? ?? [])
            .map<List<double>>((p) => (p as List).map((v) => (v as num).toDouble()).toList())
            .toList(),
      );

  bool get isBlocking => severity == IncidentSeverity.high && category.blocksRoute;
}

class TrafficRepository {
  final Dio _dio;
  TrafficRepository(this._dio);

  Future<List<TrafficIncident>> fetchInBoundingBox({
    required double minLng,
    required double minLat,
    required double maxLng,
    required double maxLat,
  }) async {
    final response = await _dio.get<dynamic>('/v1/traffic', queryParameters: {
      'bbox': '$minLng,$minLat,$maxLng,$maxLat',
    });
    final data = response.data;
    if (data is! List) return const [];
    return data
        .map((e) => TrafficIncident.fromJson(e as Map<String, dynamic>))
        .toList(growable: false);
  }
}

final trafficRepositoryProvider = Provider<TrafficRepository>((ref) {
  return TrafficRepository(ApiClient.create());
});

class TrafficState {
  final List<TrafficIncident> incidents;
  final bool isLoading;
  final String? error;
  final bool isEnabled;

  const TrafficState({
    this.incidents = const [],
    this.isLoading = false,
    this.error,
    this.isEnabled = true,
  });

  TrafficState copyWith({
    List<TrafficIncident>? incidents,
    bool? isLoading,
    String? error,
    bool? isEnabled,
  }) =>
      TrafficState(
        incidents: incidents ?? this.incidents,
        isLoading: isLoading ?? this.isLoading,
        error: error,
        isEnabled: isEnabled ?? this.isEnabled,
      );
}

/// Lädt Vorfälle für den Kartenausschnitt, 30-s-Refresh während der
/// Navigation. Fehler brechen nichts: alte Vorfälle bleiben sichtbar
/// (mit Timestamp alter als 5 min wäre eine Warnung sinnvoll - später).
class TrafficController extends StateNotifier<TrafficState> {
  final TrafficRepository _repository;
  Timer? _refreshTimer;

  TrafficController(this._repository) : super(const TrafficState());

  /// Navigation: Startet periodisches Nachladen + Route-Überwachung.
  void startNavigationMonitoring(List<List<double>> routeGeometry) {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _reloadAroundRoute(routeGeometry);
    });
  }

  void stopNavigationMonitoring() {
    _refreshTimer?.cancel();
    _refreshTimer = null;
  }

  Future<void> loadViewport({
    required double minLng,
    required double minLat,
    required double maxLng,
    required double maxLat,
  }) async {
    state = state.copyWith(isLoading: true);
    try {
      final incidents = await _repository.fetchInBoundingBox(
        minLng: minLng,
        minLat: minLat,
        maxLng: maxLng,
        maxLat: maxLat,
      );
      state = TrafficState(incidents: incidents, isEnabled: state.isEnabled);
    } on DioException {
      state = state.copyWith(error: 'Verkehr nicht erreichbar');
    } catch (_) {
      state = state.copyWith(error: 'Verkehrsdaten fehlgeschlagen');
    }
  }

  Future<void> _reloadAroundRoute(List<List<double>> geometry) async {
    // Route-BBox mit Puffer laden statt Viewport: Vorfälle AUSSERHALB
    // des Sichtbereichs, aber auf der Reststrecke, sind relevanter.
    if (geometry.isEmpty) return;
    double minLng = geometry.first[0], maxLng = minLng;
    double minLat = geometry.first[1], maxLat = minLat;
    for (final p in geometry) {
      minLng = math.min(minLng, p[0]);
      maxLng = math.max(maxLng, p[0]);
      minLat = math.min(minLat, p[1]);
      maxLat = math.max(maxLat, p[1]);
    }
    const pad = 0.05; // ~5 km Puffer
    await loadViewport(
      minLng: minLng - pad,
      minLat: minLat - pad,
      maxLng: maxLng + pad,
      maxLat: maxLat + pad,
    );
  }

  /// Prüft, ob ein BLOCKIERENDER Vorfall nahe der Reststrecke liegt.
  /// Returns den ersten Treffer (höchste Severity zuerst sortiert) oder
  /// null - der Navigation-Controller triggert damit proaktives Rerouting.
  TrafficIncident? findBlockingIncidentNearRoute({
    required List<List<double>> routeGeometry,
    double thresholdMeters = 150,
  }) {
    if (routeGeometry.length < 2) return null;

    final blocking = state.incidents.where((i) => i.isBlocking).toList()
      ..sort((a, b) => a.severity.index.compareTo(b.severity.index));

    for (final incident in blocking) {
      for (final point in incident.geometry) {
        final d = distanceToRouteMeters(point[1], point[0], routeGeometry);
        if (d <= thresholdMeters) {
          return incident;
        }
      }
    }
    return null;
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }
}

final trafficControllerProvider =
    StateNotifierProvider<TrafficController, TrafficState>((ref) {
  return TrafficController(ref.watch(trafficRepositoryProvider));
});
