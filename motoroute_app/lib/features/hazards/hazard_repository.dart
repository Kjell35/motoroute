import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import '../chat/chat_providers.dart';

/// Community-Gefahrenradar: Modelle + Repository + Controller.
/// Spiegel zu /v1/hazards (schema_hazards.sql): Rollsplitt, Sperrungen,
/// Baustellen, Ölspuren - von Bikern gemeldet, von Bikern bestätigt.

/// Die 4 Meldungstypen (Spiegel zum SQL-Enum hazard_report_type).
enum HazardType {
  rollsplitt,
  sperrung,
  baustelle,
  oelspur;

  static HazardType from(String? raw) => HazardType.values.firstWhere(
        (t) => t.name == raw,
        orElse: () => HazardType.baustelle,
      );

  /// Deutsche UI-Labels + Kartenfarbe (rot = blockierend, orange = Warnung).
  String get label => switch (this) {
        HazardType.rollsplitt => '🚧 Rollsplitt',
        HazardType.sperrung => '⛔ Sperrung',
        HazardType.baustelle => '🚜 Baustelle',
        HazardType.oelspur => '🛢️ Ölspur',
      };

  String get apiValue => name;
}

/// Eine aktive Gefahrenmeldung (Zeile aus hazard_report_nearby).
class HazardReport {
  final String id;
  final HazardType type;
  final String description;
  final double lat;
  final double lng;
  final int upvotes;
  final DateTime createdAt;
  final DateTime expiresAt;
  final int distanceM;

  const HazardReport({
    required this.id,
    required this.type,
    required this.description,
    required this.lat,
    required this.lng,
    required this.upvotes,
    required this.createdAt,
    required this.expiresAt,
    required this.distanceM,
  });

  factory HazardReport.fromJson(Map<String, dynamic> json) => HazardReport(
        id: json['id'] as String,
        type: HazardType.from(json['report_type'] as String?),
        description: (json['description'] as String?) ?? '',
        lat: (json['latitude'] as num).toDouble(),
        lng: (json['longitude'] as num).toDouble(),
        upvotes: (json['upvotes'] as num?)?.toInt() ?? 1,
        createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ??
            DateTime.now(),
        expiresAt: DateTime.tryParse(json['expires_at'] as String? ?? '') ??
            DateTime.now(),
        distanceM: (json['distance_m'] as num?)?.toInt() ?? 0,
      );

  /// Wird im Upvote-Flow gebraucht: abgelaufene Meldungen nimmt der
  /// Server nicht mehr an (410) - hier defensiv vormarkiert.
  bool get isExpired => DateTime.now().isAfter(expiresAt);
}

/// REST-Repository gegen /v1/hazards (authentifiziert wie der Chat).
class HazardRepository {
  final Dio _dio;
  HazardRepository(this._dio);

  void _auth(String token) =>
      _dio.options.headers['Authorization'] = 'Bearer $token';

  /// Neue Gefahrenmeldung. Antwort: { id, merged, upvotes }.
  Future<({String id, bool merged, int upvotes})> create({
    required String token,
    required HazardType type,
    required double lat,
    required double lng,
    String? description,
  }) async {
    _auth(token);
    final res = await _dio.post<Map<String, dynamic>>(
      '/v1/hazards',
      data: {
        'reportType': type.apiValue,
        'lat': lat,
        'lng': lng,
        if (description != null && description.isNotEmpty) 'description': description,
      },
    );
    final data = res.data ?? const {};
    return (
      id: data['id'] as String? ?? '',
      merged: data['merged'] as bool? ?? false,
      upvotes: (data['upvotes'] as num?)?.toInt() ?? 1,
    );
  }

  /// Aktive Gefahren im Umkreis (radiusKm, Default 50 km serverseitig).
  Future<List<HazardReport>> nearby({
    required String token,
    required double lat,
    required double lng,
    double radiusKm = 50,
  }) async {
    _auth(token);
    final res = await _dio.get<List<dynamic>>(
      '/v1/hazards/nearby',
      queryParameters: {
        'lat': lat,
        'lon': lng,
        if (radiusKm != 50) 'radiusKm': radiusKm,
      },
    );
    return (res.data ?? const [])
        .map((e) => HazardReport.fromJson(e as Map<String, dynamic>))
        .toList(growable: false);
  }

  /// "Gefahr existiert noch"-Bestätigung. Wirft bei 410 (abgelaufen) -
  /// der Aufrufer entfernt den Marker dann aus der Karte.
  Future<({int upvotes, bool alreadyVoted})> upvote({
    required String token,
    required String id,
  }) async {
    _auth(token);
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '/v1/hazards/$id/upvote',
      );
      final data = res.data ?? const {};
      return (
        upvotes: (data['upvotes'] as num?)?.toInt() ?? 0,
        alreadyVoted: data['alreadyVoted'] as bool? ?? false,
      );
    } on DioException catch (e) {
      if (e.response?.statusCode == 410) {
        throw HazardExpiredException();
      }
      rethrow;
    }
  }
}

/// Die Meldung ist abgelaufen - Marker entfernen, keine Wiederholung.
class HazardExpiredException implements Exception {
  const HazardExpiredException();
}

/// Kartenzustand: aktive Gefahren im geladenen Viewport.
class HazardRadarState {
  final List<HazardReport> reports;
  final bool isLoading;
  final String? error;

  const HazardRadarState({
    this.reports = const [],
    this.isLoading = false,
    this.error,
  });

  HazardRadarState copyWith({
    List<HazardReport>? reports,
    bool? isLoading,
    String? error,
  }) =>
      HazardRadarState(
        reports: reports ?? this.reports,
        isLoading: isLoading ?? this.isLoading,
        error: error,
      );
}

/// Controller: Viewport-Laden (gedrosselt, wie der POI-Layer), Melden
/// von unterwegs (Standort + 2 Klicks im Sheet), Upvote.
class HazardRadarController extends StateNotifier<HazardRadarState> {
  final HazardRepository _repo;
  final Ref _ref;

  HazardRadarController(this._repo, this._ref) : super(const HazardRadarState());

  DateTime _lastLoad = DateTime.fromMillisecondsSinceEpoch(0);
  double? _lastLat;
  double? _lastLng;

  /// Lädt aktive Gefahren um den Kartenausschnitt (Mittelpunkt). Mindest-
  /// abstand 10 s / 5 km - das Radar ist ein Warnlayer, kein Live-Stream.
  Future<void> loadViewport({
    required double centerLat,
    required double centerLng,
  }) async {
    final now = DateTime.now();
    final tooSoon = now.difference(_lastLoad) < const Duration(seconds: 10);
    final sameArea = _lastLat != null &&
        _lastLng != null &&
        (centerLat - _lastLat!).abs() < 0.05 &&
        (centerLng - _lastLng!).abs() < 0.05;
    if (tooSoon && sameArea) return;

    _lastLoad = now;
    _lastLat = centerLat;
    _lastLng = centerLng;
    state = state.copyWith(isLoading: true, error: null);
    try {
      final token = _ref.read(chatSessionTokenProvider);
      if (token == null) {
        // Anonyme Nutzung: Radar zeigt nichts (Melden/Upvoten sind
        // angemeldet-Features), Navigation läuft unangetastet weiter.
        state = const HazardRadarState();
        return;
      }
      final reports = await _repo.nearby(
        token: token,
        lat: centerLat,
        lng: centerLng,
      );
      state = HazardRadarState(reports: reports);
    } on DioException {
      state = state.copyWith(isLoading: false, error: 'Radar nicht erreichbar');
    } catch (_) {
      state = state.copyWith(isLoading: false, error: 'Radar nicht erreichbar');
    }
  }

  /// 2-Klick-Meldung von unterwegs: aktueller Standort + Typ. merged =
  /// bestehende Meldung bestätigt (100-m-Konsolidierung serverseitig).
  Future<({bool ok, bool merged})> reportHere({
    required HazardType type,
    required double lat,
    required double lng,
  }) async {
    final token = _ref.read(chatSessionTokenProvider);
    if (token == null) return (ok: false, merged: false);
    try {
      final res = await _repo.create(token: token, type: type, lat: lat, lng: lng);
      await loadViewportForce(lat: lat, lng: lng);
      return (ok: true, merged: res.merged);
    } catch (_) {
      state = state.copyWith(error: 'Meldung konnte nicht gesendet werden');
      return (ok: false, merged: false);
    }
  }

  /// Upvote mit Validierung; bei 410 (abgelaufen) Marker entfernen.
  Future<({bool ok, bool expired, bool alreadyVoted, int? upvotes})> upvote(String id) async {
    final token = _ref.read(chatSessionTokenProvider);
    if (token == null) return (ok: false, expired: false, alreadyVoted: false, upvotes: null);
    try {
      final res = await _repo.upvote(token: token, id: id);
      // Zähler lokal spiegeln, ohne gleich neu zu laden.
      state = state.copyWith(
        reports: state.reports
            .map((r) => r.id == id
                ? HazardReport(
                    id: r.id, type: r.type, description: r.description,
                    lat: r.lat, lng: r.lng, upvotes: res.upvotes,
                    createdAt: r.createdAt, expiresAt: r.expiresAt,
                    distanceM: r.distanceM)
              : r)
            .toList(growable: false),
      );
      return (ok: true, expired: false, alreadyVoted: res.alreadyVoted, upvotes: res.upvotes);
    } on HazardExpiredException {
      state = state.copyWith(
        reports: state.reports.where((r) => r.id != id).toList(growable: false),
      );
      return (ok: false, expired: true, alreadyVoted: false, upvotes: null);
    } catch (_) {
      return (ok: false, expired: false, alreadyVoted: false, upvotes: null);
    }
  }

  /// Erzwingt ein Neuladen (nach einer Meldung - die eigene Meldung soll
  /// SOFORT auf der Karte erscheinen, Throttle hin oder her).
  Future<void> loadViewportForce({required double lat, required double lng}) async {
    _lastLoad = DateTime.fromMillisecondsSinceEpoch(0);
    await loadViewport(centerLat: lat, centerLng: lng);
  }
}

final hazardRadarProvider =
    StateNotifierProvider<HazardRadarController, HazardRadarState>((ref) {
  return HazardRadarController(HazardRepository(ApiClient.create()), ref);
});
