import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import '../chat/data/chat_repository.dart' show chatFailure, ChatUser;

/// Live-Zustand eines teilenden Fahrers (Backend ride_live_state).
class LiveRider {
  final String userId;
  final double lat;
  final double lng;
  final bool started;
  final bool finished;
  final String? lastBeatAt;

  /// Vom Backend eingebettetes Profil.
  final ChatUser? user;

  const LiveRider({
    required this.userId,
    required this.lat,
    required this.lng,
    required this.started,
    required this.finished,
    this.lastBeatAt,
    this.user,
  });

  factory LiveRider.fromJson(Map<String, dynamic> json) {
    final profile = json['user_id'] != null && json['username'] != null
        ? ChatUser.fromJson({
            'id': json['user_id'],
            'username': json['username'],
            'display_name': json['display_name'],
            'avatar_url': json['avatar_url'],
          })
        : null;
    return LiveRider(
      userId: json['user_id'] as String,
      lat: (json['last_lat'] as num).toDouble(),
      lng: (json['last_lng'] as num).toDouble(),
      started: (json['started'] ?? false) as bool,
      finished: (json['finished'] ?? false) as bool,
      lastBeatAt: json['last_beat_at'] as String?,
      user: profile,
    );
  }
}

/// Repository für /v1/group-rides.
class GroupRideRepository {
  final Dio _dio;
  GroupRideRepository(this._dio);

  void _auth(String token) => _dio.options.headers['Authorization'] = 'Bearer $token';

  /// Alle aktuell teilenden Fahrer (nur bei aktiver Freigabe vorhanden).
  Future<List<LiveRider>> liveState(String token, String routeId) async {
    _auth(token);
    final res = await _dio.get<List<dynamic>>('/v1/group-rides/$routeId/live');
    return (res.data ?? [])
        .map((e) => LiveRider.fromJson(e as Map<String, dynamic>))
        .toList(growable: false);
  }

  /// OPT-IN: Freigabe mit erster Position starten.
  Future<void> startSharing(String token, String routeId, {required double lat, required double lng}) async {
    _auth(token);
    await _dio.post<void>('/v1/group-rides/$routeId/sharing', data: {'lat': lat, 'lng': lng});
  }

  /// Heartbeat während der Fahrt.
  Future<void> heartbeat(String token, String routeId, {required double lat, required double lng}) async {
    _auth(token);
    await _dio.put<void>('/v1/group-rides/$routeId/heartbeat', data: {'lat': lat, 'lng': lng});
  }

  /// Freigabe beenden (Position wird serverseitig physisch gelöscht).
  Future<void> stopSharing(String token, String routeId) async {
    _auth(token);
    await _dio.delete<void>('/v1/group-rides/$routeId/sharing');
  }

  /// Sich selbst als "fertig gefahren" markieren.
  Future<void> finish(String token, String routeId) async {
    _auth(token);
    await _dio.post<void>('/v1/group-rides/$routeId/finish');
  }
}

final groupRideRepositoryProvider = Provider<GroupRideRepository>((ref) {
  return GroupRideRepository(ApiClient.create());
});

/// Aufbereiterfehler (bestehendes Failure-Modell).
String rideFailureMessage(Object error) => chatFailure(error).message;
