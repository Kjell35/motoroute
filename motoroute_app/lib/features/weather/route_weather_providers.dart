import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';

/// Wetter-Radar entlang der Route - Spiegel zu POST /v1/weather/route
/// (weather.service.ts). Das Backend samplet die Polyline, ordnet jedem
/// Sample seine ETA zu und bewertet Unwetter; die App stellt nur dar.

enum StormSeverity { none, advisory, warning, danger }

class RouteWeatherSegment {
  final double distanceFromStartM;
  final DateTime time;
  final double tempC;
  final double precipitationMmH;
  final double? windGustMs;
  final int conditionCode;
  final StormSeverity severity;

  const RouteWeatherSegment({
    required this.distanceFromStartM,
    required this.time,
    required this.tempC,
    required this.precipitationMmH,
    required this.conditionCode,
    required this.severity,
    this.windGustMs,
  });

  factory RouteWeatherSegment.fromJson(Map<String, dynamic> json) =>
      RouteWeatherSegment(
        distanceFromStartM: (json['distanceFromStartM'] as num).toDouble(),
        time: DateTime.parse(json['time'] as String),
        tempC: (json['tempC'] as num).toDouble(),
        precipitationMmH: (json['precipitationMmH'] as num).toDouble(),
        conditionCode: (json['conditionCode'] as num).toInt(),
        severity: stormSeverityFromApi(json['severity'] as String? ?? 'none'),
        windGustMs: json['windGustMs'] == null
            ? null
            : (json['windGustMs'] as num).toDouble(),
      );

  /// Ampellogik für Widget-Farben: danger >= 17.2 m/s Böen etc.
  bool get isStorm => severity == StormSeverity.danger;
}

StormSeverity stormSeverityFromApi(String value) => switch (value) {
      'danger' => StormSeverity.danger,
      'warning' => StormSeverity.warning,
      'advisory' => StormSeverity.advisory,
      _ => StormSeverity.none,
    };

class ShelterPoi {
  final String id;
  final String name;
  final String category;
  final double lat;
  final double lng;
  final double distanceFromRouteM;

  const ShelterPoi({
    required this.id,
    required this.name,
    required this.category,
    required this.lat,
    required this.lng,
    required this.distanceFromRouteM,
  });

  factory ShelterPoi.fromJson(Map<String, dynamic> json) => ShelterPoi(
        id: json['id'] as String,
        name: json['name'] as String,
        category: json['category'] as String,
        lat: (json['lat'] as num).toDouble(),
        lng: (json['lng'] as num).toDouble(),
        distanceFromRouteM: (json['distanceFromRouteM'] as num).toDouble(),
      );

  String get categoryLabel => switch (category) {
        'MOTO_HOTEL' => 'Motorradhotel',
        'BIKER_MEETUP' => 'Bikertreff',
        'CAMPSITE' => 'Campingplatz',
        _ => 'Schutz',
      };
}

class RouteWeatherReport {
  final bool isEnabled;

  /// Fahrtrichtungs-Meldung des Backends ("In 20 km zieht ein Gewitter
  /// auf: Gewitter") - null heißt unauffällig oder Feature aus.
  final String? alertMessage;

  final StormSeverity alertSeverity;
  final double? alertDistanceFromStartM;

  /// Alle Abschnitte (Spiegel zum Backend) - Basis für destinationSegment
  /// und spätere Detail-Ansichten (z. B. Wetter-Timeline).
  final List<RouteWeatherSegment> segments;

  /// Momentan-Wetter am Ziel (letztes Segment), für das dezente Widget.
  final RouteWeatherSegment? destinationSegment;

  final List<ShelterPoi> shelters;

  const RouteWeatherReport({
    required this.isEnabled,
    this.segments = const [],
    this.alertMessage,
    this.alertSeverity = StormSeverity.none,
    this.alertDistanceFromStartM,
    this.destinationSegment,
    this.shelters = const [],
  });

  factory RouteWeatherReport.fromJson(Map<String, dynamic> json) {
    final segments = (json['segments'] as List? ?? [])
        .map((s) => RouteWeatherSegment.fromJson(s as Map<String, dynamic>))
        .toList(growable: false);
    final alert = json['alert'] as Map<String, dynamic>?;
    return RouteWeatherReport(
      isEnabled: json['isEnabled'] as bool? ?? false,
      segments: segments,
      alertMessage: alert?['message'] as String?,
      alertSeverity: stormSeverityFromApi(
        (alert?['severity'] as String?) ?? 'none',
      ),
      alertDistanceFromStartM: alert?['distanceFromStartM'] == null
          ? null
          : (alert!['distanceFromStartM'] as num).toDouble(),
      destinationSegment: segments.isEmpty ? null : segments.last,
      shelters: (json['shelters'] as List? ?? [])
          .map((s) => ShelterPoi.fromJson(s as Map<String, dynamic>))
          .toList(growable: false),
    );
  }

  bool get hasAlert =>
      alertMessage != null && alertSeverity != StormSeverity.none;
}

class RouteWeatherRepository {
  final Dio _dio;
  RouteWeatherRepository(this._dio);

  Future<RouteWeatherReport> fetchForRoute({
    required List<List<double>> geometry,
    required double durationSeconds,
  }) async {
    final response = await _dio.post<dynamic>(
      '/v1/weather/route',
      data: {'geometry': geometry, 'durationSeconds': durationSeconds},
    );
    return RouteWeatherReport.fromJson(
      (response.data as Map).cast<String, dynamic>(),
    );
  }
}

final routeWeatherRepositoryProvider = Provider<RouteWeatherRepository>((ref) {
  return RouteWeatherRepository(ApiClient.create());
});

class RouteWeatherState {
  final RouteWeatherReport? report;
  final bool isLoading;
  final String? error;

  const RouteWeatherState({this.report, this.isLoading = false, this.error});

  RouteWeatherState copyWith({
    RouteWeatherReport? report,
    bool? isLoading,
    String? error,
  }) =>
      RouteWeatherState(
        report: report ?? this.report,
        isLoading: isLoading ?? this.isLoading,
        error: error,
      );
}

/// Lädt das Wetter-Radar für die aktive Route und aktualisiert es alle
/// 15 Minuten (OWM hourly ändert sich relevant, schneller lohnt nicht -
/// das Backend cache st 10 min sowieso). Fehler degradieren bewusst:
/// Das letzte gültige Report bleibt sichtbar, das Widget zeigt es mit
/// Zeitstempel-Alter weiter an.
class RouteWeatherController extends StateNotifier<RouteWeatherState> {
  final RouteWeatherRepository _repository;
  Timer? _refreshTimer;
  List<List<double>> _geometry = const [];
  double _durationSeconds = 0;

  RouteWeatherController(this._repository) : super(const RouteWeatherState());

  void startForRoute({
    required List<List<double>> geometry,
    required double durationSeconds,
  }) {
    _geometry = geometry;
    _durationSeconds = durationSeconds;
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(
      const Duration(minutes: 15),
      (_) => _load(),
    );
    _load();
  }

  void stop() {
    _refreshTimer?.cancel();
    _refreshTimer = null;
    _geometry = const [];
    _durationSeconds = 0;
  }

  Future<void> _load() async {
    if (_geometry.length < 2) return;
    state = state.copyWith(isLoading: true);
    try {
      final report = await _repository.fetchForRoute(
        geometry: _geometry,
        durationSeconds: _durationSeconds,
      );
      state = RouteWeatherState(report: report);
    } on DioException {
      // Kein Fehler-Wipe: altes Report bleibt - eine 15-min-alte
      // Unwetterwarnung ist immer noch besser als keine.
      state = state.copyWith(
        isLoading: false,
        error: 'Wetter nicht erreichbar',
      );
    } catch (_) {
      state = state.copyWith(isLoading: false, error: 'Wetter fehlgeschlagen');
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  /// Nur für Tests: manueller Reload-Pfad ohne Timer-Warten.
  // ignore: unused_element
  Future<void> reloadForTest() => _load();
}

final routeWeatherControllerProvider =
    StateNotifierProvider<RouteWeatherController, RouteWeatherState>((ref) {
  return RouteWeatherController(ref.watch(routeWeatherRepositoryProvider));
});
