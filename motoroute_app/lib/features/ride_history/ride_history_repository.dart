import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';

/// Fahrhistorie: Modelle + Repository gegen /v1/ride-history.
///
/// DATENSCHUTZ: Das Backend filtert alles Nicht-Freigegebene serverseitig
/// (Privacy-Flags + RLS). Diese Models spiegeln die öffentliche Sicht -
/// sie enthalten per Konstruktion keine Daten, die nicht freigegeben
/// wurden (z. B. exakte Start/Ziel-Koordinaten nur bei
/// hide_start_end=false des Besitzers).

/// Gefahrene Strecke im öffentlichen Profil (Statistik immer, GPS-Linie
/// nur wenn share_track=true des Besitzers).
class PublicRide {
  final String externalId;
  final String title;
  final DateTime startedAt;
  final double distanceMeters;
  final double durationSeconds;
  final double elevationGainMeters;
  final String? region;
  final String? description;
  final List<LatLngPoint> track;
  final List<RidePoi> pois;
  final String? startLabel;
  final String? endLabel;
  final LatLngPoint? start;
  final LatLngPoint? end;

  const PublicRide({
    required this.externalId,
    required this.title,
    required this.startedAt,
    required this.distanceMeters,
    required this.durationSeconds,
    required this.elevationGainMeters,
    this.region,
    this.description,
    this.track = const [],
    this.pois = const [],
    this.startLabel,
    this.endLabel,
    this.start,
    this.end,
  });

  double get km => distanceMeters / 1000;
  double get hours => durationSeconds / 3600;

  factory PublicRide.fromJson(Map<String, dynamic> j) => PublicRide(
        externalId: j['externalId'] as String? ?? '',
        title: j['title'] as String? ?? 'Tour',
        startedAt: DateTime.tryParse(j['startedAt'] as String? ?? '') ?? DateTime.now(),
        distanceMeters: (j['distanceMeters'] as num?)?.toDouble() ?? 0,
        durationSeconds: (j['durationSeconds'] as num?)?.toDouble() ?? 0,
        elevationGainMeters: (j['elevationGainMeters'] as num?)?.toDouble() ?? 0,
        region: j['region'] as String?,
        description: j['description'] as String?,
        track: ((j['track'] as List?) ?? const [])
            .map((e) => LatLngPoint.fromJson(e as Map<String, dynamic>))
            .toList(growable: false),
        pois: ((j['pois'] as List?) ?? const [])
            .map((e) => RidePoi.fromJson(e as Map<String, dynamic>))
            .toList(growable: false),
        startLabel: j['startLabel'] as String?,
        endLabel: j['endLabel'] as String?,
        start: j['start'] == null
            ? null
            : LatLngPoint.fromJson(j['start'] as Map<String, dynamic>),
        end: j['end'] == null
            ? null
            : LatLngPoint.fromJson(j['end'] as Map<String, dynamic>),
      );
}

class LatLngPoint {
  final double lat;
  final double lng;
  const LatLngPoint({required this.lat, required this.lng});

  factory LatLngPoint.fromJson(Map<String, dynamic> j) => LatLngPoint(
        lat: (j['lat'] as num).toDouble(),
        lng: (j['lng'] as num).toDouble(),
      );

  Map<String, dynamic> toJson() => {'lat': lat, 'lng': lng};
}

class RidePoi {
  final String label;
  final double lat;
  final double lng;
  const RidePoi({required this.label, required this.lat, required this.lng});

  factory RidePoi.fromJson(Map<String, dynamic> j) => RidePoi(
        label: j['label'] as String? ?? '',
        lat: (j['lat'] as num).toDouble(),
        lng: (j['lng'] as num).toDouble(),
      );
}

/// Besuchter Ort (Bikertreff, Tankstelle, Camping ...).
class PublicPlace {
  final String externalId;
  final String category;
  final String label;
  final double lat;
  final double lng;
  final int visitCount;
  final String? lastVisitedAt;

  const PublicPlace({
    required this.externalId,
    required this.category,
    required this.label,
    required this.lat,
    required this.lng,
    required this.visitCount,
    this.lastVisitedAt,
  });

  factory PublicPlace.fromJson(Map<String, dynamic> j) => PublicPlace(
        externalId: j['externalId'] as String? ?? '',
        category: j['category'] as String? ?? 'other',
        label: j['label'] as String? ?? '',
        lat: (j['lat'] as num?)?.toDouble() ?? 0,
        lng: (j['lng'] as num?)?.toDouble() ?? 0,
        visitCount: (j['visitCount'] as num?)?.toInt() ?? 1,
        lastVisitedAt: j['lastVisitedAt'] as String?,
      );
}

/// Antwort von GET /v1/ride-history/public/:userId.
class PublicProfileHistory {
  final String userId;
  final String? displayName;
  final String? username;
  final String? avatarUrl;
  final bool isPrivate;

  final int rideCount;
  final double totalKm;
  final double totalHours;
  final double totalElevationGain;
  final List<String> regions;
  final List<PublicRide> rides;
  final List<PublicPlace> places;

  const PublicProfileHistory({
    required this.userId,
    this.displayName,
    this.username,
    this.avatarUrl,
    required this.isPrivate,
    required this.rideCount,
    required this.totalKm,
    required this.totalHours,
    required this.totalElevationGain,
    required this.regions,
    required this.rides,
    required this.places,
  });

  factory PublicProfileHistory.fromJson(Map<String, dynamic> j) {
    final profile = j['profile'] as Map<String, dynamic>? ?? const {};
    final history = j['history'] as Map<String, dynamic>? ?? const {};
    return PublicProfileHistory(
      userId: profile['userId'] as String? ?? '',
      displayName: profile['displayName'] as String?,
      username: profile['username'] as String?,
      avatarUrl: profile['avatarUrl'] as String?,
      isPrivate: profile['isPrivate'] as bool? ?? true,
      rideCount: (history['rideCount'] as num?)?.toInt() ?? 0,
      totalKm: (history['totalKm'] as num?)?.toDouble() ?? 0,
      totalHours: (history['totalHours'] as num?)?.toDouble() ?? 0,
      totalElevationGain: (history['totalElevationGain'] as num?)?.toDouble() ?? 0,
      regions: ((history['regions'] as List?) ?? const [])
          .map((e) => e as String)
          .toList(growable: false),
      rides: ((history['rides'] as List?) ?? const [])
          .map((e) => PublicRide.fromJson(e as Map<String, dynamic>))
          .toList(growable: false),
      places: ((history['places'] as List?) ?? const [])
          .map((e) => PublicPlace.fromJson(e as Map<String, dynamic>))
          .toList(growable: false),
    );
  }
}

/// Antwort von GET /v1/ride-history/me (eigene Daten + Einstellungen).
class MyRideHistory {
  final bool rideHistoryEnabled;
  final String authPrivacy;
  final bool shareRides;
  final bool sharePlaces;
  final bool hideStartEnd;

  const MyRideHistory({
    required this.rideHistoryEnabled,
    required this.authPrivacy,
    required this.shareRides,
    required this.sharePlaces,
    required this.hideStartEnd,
  });

  factory MyRideHistory.fromJson(Map<String, dynamic> j) {
    final s = j['settings'] as Map<String, dynamic>? ?? const {};
    return MyRideHistory(
      rideHistoryEnabled: s['rideHistoryEnabled'] as bool? ?? true,
      authPrivacy: s['authPrivacy'] as String? ?? 'private',
      shareRides: s['shareRides'] as bool? ?? false,
      sharePlaces: s['sharePlaces'] as bool? ?? false,
      hideStartEnd: s['hideStartEnd'] as bool? ?? true,
    );
  }
}

class RideHistoryRepository {
  Future<PublicProfileHistory> fetchPublicProfile(String token, String userId) async {
    final res = await ApiClient.create().get<Map<String, dynamic>>(
      '/v1/ride-history/public/$userId',
      options: Options(headers: {'Authorization': 'Bearer $token'}),
    );
    return PublicProfileHistory.fromJson(res.data ?? const {});
  }

  Future<MyRideHistory> fetchMySettings(String token) async {
    final res = await ApiClient.create().get<Map<String, dynamic>>(
      '/v1/ride-history/me',
      options: Options(headers: {'Authorization': 'Bearer $token'}),
    );
    return MyRideHistory.fromJson(res.data ?? const {});
  }

  /// 5 globale Schalter + optional pro Tour/Ort ändern.
  Future<void> updatePrivacy(
    String token, {
    bool? rideHistoryEnabled,
    String? authPrivacy,
    bool? shareRides,
    bool? sharePlaces,
    bool? hideStartEnd,
  }) async {
    await ApiClient.create().put(
      '/v1/ride-history/privacy',
      data: jsonEncode({
        if (rideHistoryEnabled != null) 'rideHistoryEnabled': rideHistoryEnabled,
        if (authPrivacy != null) 'authPrivacy': authPrivacy,
        if (shareRides != null) 'shareRides': shareRides,
        if (sharePlaces != null) 'sharePlaces': sharePlaces,
        if (hideStartEnd != null) 'hideStartEnd': hideStartEnd,
      }),
      options: Options(headers: {'Authorization': 'Bearer $token'}),
    );
  }

  /// Eine abgeschlossene Tour synchronisieren. Schlägt fehl (z. B. Server
  /// weg, Migration fehlt), wirft die Methode - der Aufrufer (Recorder-
  /// Abschluss) behandelt das best-effort: Die Tour bleibt lokal im
  /// Tagebuch gespeichert, der Sync wiederholt sich bei der nächsten
  /// Fahrt NICHT automatisch (bewusst: keine Warteschlange mit
  /// Standortdaten auf dem Gerät).
  Future<void> syncRide(String token, Map<String, dynamic> payload) async {
    await ApiClient.create().post(
      '/v1/ride-history/rides',
      data: payload,
      options: Options(headers: {'Authorization': 'Bearer $token'}),
    );
  }
}

final rideHistoryRepositoryProvider = Provider<RideHistoryRepository>((ref) {
  return RideHistoryRepository();
});
