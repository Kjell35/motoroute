import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import '../auth/auth_providers.dart';

/// Pass-Knacker & Badges: Modell + Repository.
/// Spiegel zu /v1/badges - die Geometrie (ST_DWithin) und die
/// Freischalt-Idempotenz passieren SERVERSEITIG (RPC match_badge_at),
/// die App schickt nur die Position und zeigt die Ergebnisse.

/// Kategorie eines Badges (Spiegel SQL-Check-Constraint).
enum BadgeCategory {
  pass,
  meeting,
  sight;

  static BadgeCategory from(String? raw) => BadgeCategory.values.firstWhere(
        (c) => c.name == raw,
        orElse: () => BadgeCategory.pass,
      );

  /// Icon + Farbe im Trophäenschrank (farbige Icons je Kategorie).
  String get emoji => switch (this) {
        BadgeCategory.pass => '🏔️',
        BadgeCategory.meeting => '🏍️',
        BadgeCategory.sight => '📸',
      };
}

/// Ein Badge aus dem Katalog (ggf. mit Freischalt-Datum).
class BadgeItem {
  final String id;
  final String title;
  final String description;
  final String? iconUrl;
  final BadgeCategory category;
  final double lat;
  final double lon;
  final int radiusMeters;
  final bool unlocked;
  final DateTime? unlockedAt;
  /// Nur im Check-in-Ergebnis gesetzt: Distanz zum Ziel beim Check-in.
  final int? distanceMeters;

  const BadgeItem({
    required this.id,
    required this.title,
    required this.description,
    required this.iconUrl,
    required this.category,
    required this.lat,
    required this.lon,
    required this.radiusMeters,
    required this.unlocked,
    required this.unlockedAt,
    this.distanceMeters,
  });

  factory BadgeItem.fromJson(Map<String, dynamic> json) => BadgeItem(
        id: json['id'] as String,
        title: json['title'] as String? ?? '',
        description: json['description'] as String? ?? '',
        iconUrl: json['iconUrl'] as String?,
        category: BadgeCategory.from(json['category'] as String?),
        lat: (json['lat'] as num?)?.toDouble() ?? 0,
        lon: (json['lon'] as num?)?.toDouble() ?? 0,
        radiusMeters: (json['radiusMeters'] as num?)?.toInt() ?? 100,
        unlocked: json['unlocked'] as bool? ?? false,
        unlockedAt: json['unlockedAt'] == null
            ? null
            : DateTime.tryParse(json['unlockedAt'] as String),
        distanceMeters: (json['distanceMeters'] as num?)?.toInt(),
      );
}

/// Ergebnis eines GPS-Check-ins (POST /v1/badges/checkin).
class CheckinResult {
  final List<BadgeItem> unlockedNow;
  final List<String> revisitedTitles;
  final int totalUnlocked;

  const CheckinResult({
    required this.unlockedNow,
    required this.revisitedTitles,
    required this.totalUnlocked,
  });
}

/// Trophäenschrank-Zustand (GET /v1/badges/me).
class BadgeShelf {
  final List<BadgeItem> badges;
  final int unlockedCount;
  final int totalCount;

  const BadgeShelf({required this.badges, required this.unlockedCount, required this.totalCount});

  static const empty = BadgeShelf(badges: [], unlockedCount: 0, totalCount: 0);
}

/// REST-Repository gegen /v1/badges (authentifiziert).
class BadgesRepository {
  final Dio _dio;
  BadgesRepository(this._dio);

  void _auth(String token) => _dio.options.headers['Authorization'] = 'Bearer $token';

  /// GPS-Check-in an der aktuellen Position. Wirft bei Fehlern DioException
  /// mit ggf. response-Status (die Screens nutzen technicalCause).
  Future<CheckinResult> checkin({
    required String token,
    required double lat,
    required double lon,
  }) async {
    _auth(token);
    final res = await _dio.post<Map<String, dynamic>>(
      '/v1/badges/checkin',
      data: {'lat': lat, 'lon': lon},
    );
    final data = res.data ?? const {};
    return CheckinResult(
      unlockedNow: ((data['unlockedNow'] as List?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(BadgeItem.fromJson)
          .toList(),
      revisitedTitles: ((data['revisited'] as List?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .map((r) => r['title'] as String? ?? '')
          .where((t) => t.isNotEmpty)
          .toList(),
      totalUnlocked: (data['totalUnlocked'] as num?)?.toInt() ?? 0,
    );
  }

  /// Trophäenschrank: Katalog + Freischaltungen des Nutzers.
  Future<BadgeShelf> shelf({required String token}) async {
    _auth(token);
    final res = await _dio.get<Map<String, dynamic>>('/v1/badges/me');
    final data = res.data ?? const {};
    return BadgeShelf(
      badges: ((data['badges'] as List?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(BadgeItem.fromJson)
          .toList(),
      unlockedCount: (data['unlockedCount'] as num?)?.toInt() ?? 0,
      totalCount: (data['totalCount'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Provider: Repository (Dio mit Kaltstart-Retry + 401-Refresh).
final badgesRepositoryProvider = Provider<BadgesRepository>(
  (ref) => BadgesRepository(ApiClient.create()),
);

/// Aktiver Access-Token (aus der Auth-Sitzung) für Badges-Requests.
final badgesTokenProvider = Provider<String?>((ref) {
  final auth = ref.watch(authControllerProvider);
  return auth.isAuthenticated ? ref.read(authControllerProvider.notifier).accessToken : null;
});
