import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/error/failure.dart';
import '../../core/network/api_client.dart';
import '../chat/data/chat_repository.dart' show chatFailure;

/// Status einer gemeinsamen Route (Abschnitt 15). `finalized` statt
/// `final` - letzteres ist ein reserviertes Dart-Schlüsselwort.
enum GroupRouteStatus { planning, finalized, riding, completed, locked }

GroupRouteStatus groupRouteStatusFrom(String? raw) => switch (raw) {
      'final' => GroupRouteStatus.finalized,
      'riding' => GroupRouteStatus.riding,
      'completed' => GroupRouteStatus.completed,
      'locked' => GroupRouteStatus.locked,
      _ => GroupRouteStatus.planning,
    };

extension GroupRouteStatusX on GroupRouteStatus {
  String get label => switch (this) {
        GroupRouteStatus.planning => '📝 Planung',
        GroupRouteStatus.finalized => '✅ Fertig',
        GroupRouteStatus.riding => '🏍️ Unterwegs',
        GroupRouteStatus.completed => '✔️ Abgeschlossen',
        GroupRouteStatus.locked => '🔒 Gesperrt',
      };
  String get apiValue => switch (this) {
        GroupRouteStatus.planning => 'planning',
        GroupRouteStatus.finalized => 'final',
        GroupRouteStatus.riding => 'riding',
        GroupRouteStatus.completed => 'completed',
        GroupRouteStatus.locked => 'locked',
      };
}

/// Bearbeitungsrechte (Abschnitt 4).
enum EditingPermission { allMembers, ownerOnly }

EditingPermission editingPermissionFrom(String? raw) =>
    raw == 'owner_only' ? EditingPermission.ownerOnly : EditingPermission.allMembers;

extension EditingPermissionX on EditingPermission {
  String get label => this == EditingPermission.allMembers
      ? '🔓 Alle Gruppenmitglieder'
      : '🔒 Nur der Owner';
  String get apiValue =>
      this == EditingPermission.allMembers ? 'all_members' : 'owner_only';
}

/// Kategorie eines Stopps (Spiegel zum DB-Check-Constraint).
enum StopCategory { fuel, motoHotel, bikerMeetup, campsite, iceCream, viewpoint, other }

StopCategory stopCategoryFrom(String? raw) => switch (raw) {
      'fuel' => StopCategory.fuel,
      'moto_hotel' => StopCategory.motoHotel,
      'biker_meetup' => StopCategory.bikerMeetup,
      'campsite' => StopCategory.campsite,
      'ice_cream' => StopCategory.iceCream,
      'viewpoint' => StopCategory.viewpoint,
      _ => StopCategory.other,
    };

extension StopCategoryX on StopCategory {
  String get apiValue => switch (this) {
        StopCategory.fuel => 'fuel',
        StopCategory.motoHotel => 'moto_hotel',
        StopCategory.bikerMeetup => 'biker_meetup',
        StopCategory.campsite => 'campsite',
        StopCategory.iceCream => 'ice_cream',
        StopCategory.viewpoint => 'viewpoint',
        StopCategory.other => 'other',
      };
  String get label => switch (this) {
        StopCategory.fuel => '⛽ Tankstelle',
        StopCategory.motoHotel => '🏨 Motorradhotel',
        StopCategory.bikerMeetup => '🏍️ Biker-Treff',
        StopCategory.campsite => '⛺ Campingplatz',
        StopCategory.iceCream => '🍦 Eisdiele',
        StopCategory.viewpoint => '📸 Aussichtspunkt',
        StopCategory.other => '📍 Stopp',
      };
}

/// Ein Stopp auf einer gemeinsamen Route (Abschnitt 22).
class RouteStop {
  final String id;
  final int position;
  final double lat;
  final double lng;
  final String name;
  final StopCategory category;
  final String? description;
  final String? address;
  final String createdBy;
  final String createdAt;

  const RouteStop({
    required this.id,
    required this.position,
    required this.lat,
    required this.lng,
    required this.name,
    required this.category,
    this.description,
    this.address,
    required this.createdBy,
    required this.createdAt,
  });

  factory RouteStop.fromJson(Map<String, dynamic> json) => RouteStop(
        id: json['id'] as String,
        position: (json['position'] as num).toInt(),
        lat: (json['lat'] as num).toDouble(),
        lng: (json['lng'] as num).toDouble(),
        name: json['name'] as String,
        category: stopCategoryFrom(json['category'] as String?),
        description: json['description'] as String?,
        address: json['address'] as String?,
        createdBy: json['created_by'] as String,
        createdAt: json['created_at'] as String,
      );
}

/// Änderungsverlauf-Eintrag (Abschnitt 13).
class RouteChange {
  final String action;
  final String? detail;
  final String? userName;
  final String createdAt;

  const RouteChange({
    required this.action,
    this.detail,
    this.userName,
    required this.createdAt,
  });

  factory RouteChange.fromJson(Map<String, dynamic> json) {
    final sender = json['users'];
    return RouteChange(
      action: json['action'] as String,
      detail: json['detail'] as String?,
      userName:
          sender is Map<String, dynamic> ? ((sender['display_name'] ?? sender['username']) as String?) : null,
      createdAt: json['created_at'] as String,
    );
  }
}

/// Eine gemeinsame Gruppenroute (Abschnitt 26).
class GroupRoute {
  final String id;
  final String groupId;
  final String createdBy;
  final String name;
  final String? description;
  final GroupRouteStatus status;
  final EditingPermission permission;
  final String? startName;
  final double startLat;
  final double startLng;
  final String? destName;
  final double destLat;
  final double destLng;
  final String vehicleType;
  final String routingStyle;
  final bool avoidHighways;
  final bool avoidFerries;
  final bool avoidTolls;
  final double? distanceMeters;
  final double? durationSeconds;
  final int? curveScore;
  final int? elevationMeters;
  final int version;

  const GroupRoute({
    required this.id,
    required this.groupId,
    required this.createdBy,
    required this.name,
    this.description,
    required this.status,
    required this.permission,
    this.startName,
    required this.startLat,
    required this.startLng,
    this.destName,
    required this.destLat,
    required this.destLng,
    required this.vehicleType,
    required this.routingStyle,
    required this.avoidHighways,
    required this.avoidFerries,
    required this.avoidTolls,
    this.distanceMeters,
    this.durationSeconds,
    this.curveScore,
    this.elevationMeters,
    required this.version,
  });

  factory GroupRoute.fromJson(Map<String, dynamic> json) => GroupRoute(
        id: json['id'] as String,
        groupId: json['group_id'] as String,
        createdBy: json['created_by'] as String,
        name: json['name'] as String,
        description: json['description'] as String?,
        status: groupRouteStatusFrom(json['status'] as String?),
        permission: editingPermissionFrom(json['editing_permission'] as String?),
        startName: json['start_name'] as String?,
        startLat: (json['start_lat'] as num).toDouble(),
        startLng: (json['start_lng'] as num).toDouble(),
        destName: json['dest_name'] as String?,
        destLat: (json['dest_lat'] as num).toDouble(),
        destLng: (json['dest_lng'] as num).toDouble(),
        vehicleType: (json['vehicle_type'] ?? 'MOTORCYCLE') as String,
        routingStyle: (json['routing_style'] ?? 'CURVY') as String,
        avoidHighways: (json['avoid_highways'] ?? false) as bool,
        avoidFerries: (json['avoid_ferries'] ?? false) as bool,
        avoidTolls: (json['avoid_tolls'] ?? false) as bool,
        distanceMeters: (json['distance_meters'] as num?)?.toDouble(),
        durationSeconds: (json['duration_seconds'] as num?)?.toDouble(),
        curveScore: (json['curve_score'] as num?)?.toInt(),
        elevationMeters: (json['elevation_meters'] as num?)?.toInt(),
        version: (json['version'] ?? 1) as int,
      );
}

/// Vollständige Ansicht: Route + Stopps + Verlauf (Backend GET :id).
class GroupRouteDetail {
  final GroupRoute route;
  final List<RouteStop> stops;
  final List<RouteChange> history;

  const GroupRouteDetail({
    required this.route,
    required this.stops,
    required this.history,
  });

  factory GroupRouteDetail.fromJson(Map<String, dynamic> json) => GroupRouteDetail(
        route: GroupRoute.fromJson(json['route'] as Map<String, dynamic>),
        stops: ((json['stops'] as List<dynamic>? ?? []))
            .map((e) => RouteStop.fromJson(e as Map<String, dynamic>))
            .toList(growable: false),
        history: ((json['history'] as List<dynamic>? ?? []))
            .map((e) => RouteChange.fromJson(e as Map<String, dynamic>))
            .toList(growable: false),
      );
}

/// Repository für /v1/group-routes. Token je Call wie im ChatRepository.
class GroupRouteRepository {
  final Dio _dio;
  GroupRouteRepository(this._dio);

  void _auth(String token) => _dio.options.headers['Authorization'] = 'Bearer $token';

  Future<String> create(String token, {required String groupId, required String name, String? description,
      required double startLat, required double startLng, String? startName,
      required double destLat, required double destLng, String? destName,
      required String vehicleType, required String routingStyle,
      required bool avoidHighways, required bool avoidFerries, required bool avoidTolls,
      required String permission}) async {
    _auth(token);
    final res = await _dio.post<Map<String, dynamic>>('/v1/group-routes', data: {
      'groupId': groupId,
      'name': name,
      if (description != null) 'description': description,
      'startLat': startLat,
      'startLng': startLng,
      if (startName != null) 'startName': startName,
      'destLat': destLat,
      'destLng': destLng,
      if (destName != null) 'destName': destName,
      'vehicleType': vehicleType,
      'routingStyle': routingStyle,
      'avoidHighways': avoidHighways,
      'avoidFerries': avoidFerries,
      'avoidTolls': avoidTolls,
      'permission': permission,
    });
    return res.data!['routeId'] as String;
  }

  Future<List<GroupRoute>> listForGroup(String token, String groupId) async {
    _auth(token);
    final res = await _dio.get<List<dynamic>>('/v1/group-routes/group/$groupId');
    return (res.data ?? [])
        .map((e) => GroupRoute.fromJson(e as Map<String, dynamic>))
        .toList(growable: false);
  }

  Future<GroupRouteDetail> get(String token, String routeId) async {
    _auth(token);
    final res = await _dio.get<Map<String, dynamic>>('/v1/group-routes/$routeId');
    return GroupRouteDetail.fromJson(res.data!);
  }

  Future<void> update(String token, String routeId, {String? name, String? description}) async {
    _auth(token);
    await _dio.put<void>('/v1/group-routes/$routeId',
        data: {if (name != null) 'name': name, if (description != null) 'description': description});
  }

  Future<void> delete(String token, String routeId) async {
    _auth(token);
    await _dio.delete<void>('/v1/group-routes/$routeId');
  }

  Future<String> duplicate(String token, String routeId, {String? newName}) async {
    _auth(token);
    final res = await _dio.post<Map<String, dynamic>>('/v1/group-routes/$routeId/duplicate',
        data: {if (newName != null) 'newName': newName});
    return res.data!['routeId'] as String;
  }

  Future<void> setPermission(String token, String routeId, EditingPermission permission) async {
    _auth(token);
    await _dio.put<void>('/v1/group-routes/$routeId/permission',
        data: {'permission': permission.apiValue});
  }

  Future<void> setStatus(String token, String routeId, GroupRouteStatus status) async {
    _auth(token);
    await _dio.put<void>('/v1/group-routes/$routeId/status', data: {'status': status.apiValue});
  }

  Future<void> lock(String token, String routeId) async {
    _auth(token);
    await _dio.post<void>('/v1/group-routes/$routeId/lock');
  }

  Future<void> unlock(String token, String routeId) async {
    _auth(token);
    await _dio.post<void>('/v1/group-routes/$routeId/unlock');
  }

  Future<String> addStop(String token, String routeId,
      {required double lat, required double lng, required String name,
      StopCategory category = StopCategory.other, String? description, String? address}) async {
    _auth(token);
    final res = await _dio.post<Map<String, dynamic>>('/v1/group-routes/$routeId/stops', data: {
      'lat': lat,
      'lng': lng,
      'name': name,
      'category': category.apiValue,
      if (description != null) 'description': description,
      if (address != null) 'address': address,
    });
    return res.data!['stopId'] as String;
  }

  Future<void> deleteStop(String token, String stopId) async {
    _auth(token);
    await _dio.delete<void>('/v1/group-routes/stops/$stopId');
  }

  Future<void> reorder(String token, String routeId, List<String> stopIds) async {
    _auth(token);
    await _dio.put<void>('/v1/group-routes/$routeId/stops/reorder', data: {'stopIds': stopIds});
  }

  Future<void> addComment(String token, String stopId, String content) async {
    _auth(token);
    await _dio.post<void>('/v1/group-routes/stops/$stopId/comments', data: {'content': content});
  }

  Failure mapError(Object error) => chatFailure(error);
}

final groupRouteRepositoryProvider = Provider<GroupRouteRepository>((ref) {
  return GroupRouteRepository(ApiClient.create());
});
