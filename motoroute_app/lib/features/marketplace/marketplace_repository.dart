import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import '../auth/auth_providers.dart';

/// Marktplatz (Fahrzeugteile & Zubehör): Modelle + Repository.
/// Spiegel zu /v1/marketplace - KI-Prüfung und Freigabe passieren
/// SERVERSEITIG, die App kann review_status nie selbst setzen.

/// Hauptkategorien (Spiegel marketplace.taxonomy.ts).
enum MpCategory {
  motorradteile,
  autoteile,
  fahrradteile;

  static MpCategory from(String? raw) => MpCategory.values.firstWhere(
        (c) => c.name == raw,
        orElse: () => MpCategory.motorradteile,
      );

  String get label => switch (this) {
        MpCategory.motorradteile => '🏍️ Motorradteile',
        MpCategory.autoteile => '🚗 Autoteile',
        MpCategory.fahrradteile => '🚲 Fahrradteile',
      };

  String get emoji => switch (this) {
        MpCategory.motorradteile => '🏍️',
        MpCategory.autoteile => '🚗',
        MpCategory.fahrradteile => '🚲',
      };
}

/// Zustand eines Angebots (Spiegel SQL-Check-Constraint).
enum MpCondition {
  neu,
  sehrGut,
  gut,
  gebraucht,
  defekt;

  static MpCondition from(String? raw) => MpCondition.values.firstWhere(
        (c) => _apiName(c) == raw,
        orElse: () => MpCondition.gebraucht,
      );

  static String _apiName(MpCondition c) => switch (c) {
        MpCondition.neu => 'neu',
        MpCondition.sehrGut => 'sehr_gut',
        MpCondition.gut => 'gut',
        MpCondition.gebraucht => 'gebraucht',
        MpCondition.defekt => 'defekt',
      };

  String get apiValue => _apiName(this);

  String get label => switch (this) {
        MpCondition.neu => 'Neu',
        MpCondition.sehrGut => 'Sehr gut',
        MpCondition.gut => 'Gut',
        MpCondition.gebraucht => 'Gebraucht',
        MpCondition.defekt => 'Defekt',
      };

  String get emoji => switch (this) {
        MpCondition.neu => '✨',
        MpCondition.sehrGut => '👍',
        MpCondition.gut => '🙂',
        MpCondition.gebraucht => '🔧',
        MpCondition.defekt => '⚠️',
      };
}

/// Review-Status aus der serverseitigen KI-Prüfung.
enum MpReviewStatus {
  pending,
  approved,
  rejected,
  manualReview;

  static MpReviewStatus from(String? raw) => MpReviewStatus.values.firstWhere(
        (r) => _apiName(r) == raw,
        orElse: () => MpReviewStatus.pending,
      );

  static String _apiName(MpReviewStatus r) => switch (r) {
        MpReviewStatus.pending => 'pending',
        MpReviewStatus.approved => 'approved',
        MpReviewStatus.rejected => 'rejected',
        MpReviewStatus.manualReview => 'manual_review',
      };

  String get apiValue => _apiName(this);

  bool get isPubliclyVisible => this == MpReviewStatus.approved;
}

/// Ein Marketplace-Angebot (Zeile aus marketplace_listings + Bilder).
class MpListing {
  final String id;
  final String sellerId;
  final String title;
  final String description;
  final int priceCents;
  final MpCondition condition;
  final MpCategory category;
  final String subcategory;
  final String? brand;
  final String? model;
  final int? year;
  final String locationLabel;
  final bool shipping;
  final String status;
  final MpReviewStatus reviewStatus;
  final String? reviewReason;
  final DateTime createdAt;
  final List<String> imageUrls;

  const MpListing({
    required this.id,
    required this.sellerId,
    required this.title,
    required this.description,
    required this.priceCents,
    required this.condition,
    required this.category,
    required this.subcategory,
    required this.brand,
    required this.model,
    required this.year,
    required this.locationLabel,
    required this.shipping,
    required this.status,
    required this.reviewStatus,
    required this.reviewReason,
    required this.createdAt,
    required this.imageUrls,
  });

  String get priceLabel {
    final euros = priceCents / 100;
    return euros == euros.roundToDouble()
        ? '${euros.toStringAsFixed(0)} €'
        : '${euros.toStringAsFixed(2)} €';
  }

  factory MpListing.fromJson(Map<String, dynamic> json) {
    List<String> images = const [];
    final rawImages = json['images'];
    if (rawImages is List) {
      images = rawImages
          .map((e) => e is Map ? e['storage_path'] as String? : null)
          .whereType<String>()
          .map(_storagePathToUrl)
          .toList(growable: false);
    } else if (json['image_urls'] is List) {
      images = (json['image_urls'] as List).cast<String>();
    }

    return MpListing(
      id: json['id'] as String,
      sellerId: json['seller_id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      description: json['description'] as String? ?? '',
      priceCents: (json['price_cents'] as num?)?.toInt() ?? 0,
      condition: MpCondition.from(json['condition'] as String?),
      category: MpCategory.from(json['category'] as String?),
      subcategory: json['subcategory'] as String? ?? '',
      brand: json['brand'] as String?,
      model: json['model'] as String?,
      year: (json['year'] as num?)?.toInt(),
      locationLabel: json['location_label'] as String? ?? '',
      shipping: json['shipping'] as bool? ?? false,
      status: json['status'] as String? ?? 'active',
      reviewStatus: MpReviewStatus.from(json['review_status'] as String?),
      reviewReason: json['review_reason'] as String?,
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ?? DateTime.now(),
      imageUrls: images,
    );
  }

  /// Storage-Pfad -> öffentliche URL im Bucket marketplace-photos.
  static String _storagePathToUrl(String path) =>
      '${ApiClient.baseUrl.replaceAll(RegExp(r'/v1$'), '')}/storage/v1/object/public/marketplace-photos/$path';
}

/// Kategorien-Antwort des Backends (statische Taxonomie).
class MpCatalog {
  final List<MpCategoryDef> categories;
  const MpCatalog({required this.categories});

  factory MpCatalog.fromJson(Map<String, dynamic> json) => MpCatalog(
        categories: ((json['categories'] as List?) ?? const [])
            .map((e) => MpCategoryDef.fromJson(e as Map<String, dynamic>))
            .toList(growable: false),
      );
}

class MpCategoryDef {
  final String key;
  final String labelDe;
  final String labelEn;
  final List<MpSubcategoryDef> subcategories;

  const MpCategoryDef({
    required this.key,
    required this.labelDe,
    required this.labelEn,
    required this.subcategories,
  });

  factory MpCategoryDef.fromJson(Map<String, dynamic> json) => MpCategoryDef(
        key: json['key'] as String,
        labelDe: json['labelDe'] as String? ?? '',
        labelEn: json['labelEn'] as String? ?? '',
        subcategories: (json['subcategories'] as List? ?? const [])
            .map((e) => MpSubcategoryDef.fromJson(e as Map<String, dynamic>))
            .toList(growable: false),
      );
}

class MpSubcategoryDef {
  final String key;
  final String labelDe;
  final String labelEn;

  const MpSubcategoryDef({required this.key, required this.labelDe, required this.labelEn});

  factory MpSubcategoryDef.fromJson(Map<String, dynamic> json) => MpSubcategoryDef(
        key: json['key'] as String,
        labelDe: json['labelDe'] as String? ?? '',
        labelEn: json['labelEn'] as String? ?? '',
      );
}

/// REST-Repository gegen /v1/marketplace (authentifiziert).
class MarketplaceRepository {
  final Dio _dio;
  MarketplaceRepository(this._dio);

  void _auth(String token) => _dio.options.headers['Authorization'] = 'Bearer $token';

  /// Kategorien-Katalog für das Erstell-Formular.
  Future<MpCatalog> catalog({required String token}) async {
    _auth(token);
    final res = await _dio.get<Map<String, dynamic>>('/v1/marketplace/categories');
    return MpCatalog.fromJson(res.data ?? const {});
  }

  /// Öffentliche Liste mit Filtern.
  Future<List<MpListing>> list({
    required String token,
    String? q,
    String? category,
    String? subcategory,
    String? condition,
    bool? shipping,
    int? maxPrice,
    double? lat,
    double? lng,
    double? radiusKm,
    String sort = 'newest',
    int limit = 30,
  }) async {
    _auth(token);
    final res = await _dio.get<Map<String, dynamic>>(
      '/v1/marketplace/listings',
      queryParameters: {
        if (q != null && q.isNotEmpty) 'q': q,
        if (category != null) 'category': category,
        if (subcategory != null) 'subcategory': subcategory,
        if (condition != null) 'condition': condition,
        if (shipping == true) 'shipping': 'true',
        if (maxPrice != null) 'maxPrice': maxPrice,
        if (lat != null) 'lat': lat,
        if (lng != null) 'lng': lng,
        if (radiusKm != null) 'radiusKm': radiusKm,
        'sort': sort,
        'limit': limit,
      },
    );
    final rows = (res.data ?? const {})['listings'] as List? ?? const [];
    return rows.map((e) => MpListing.fromJson(e as Map<String, dynamic>)).toList(growable: false);
  }

  /// Öffentliches Detail.
  Future<MpListing> get({required String token, required String id}) async {
    _auth(token);
    final res = await _dio.get<Map<String, dynamic>>('/v1/marketplace/listings/$id');
    return MpListing.fromJson(res.data ?? const {});
  }

  /// Neues Angebot erstellen (multipart mit Fotos). Die Antwort enthält
  /// das Listing MIT review_status - die KI-Entscheidung ist schon da.
  Future<MpListing> create({
    required String token,
    required Map<String, dynamic> fields,
    List<String> imagePaths = const [],
  }) async {
    _auth(token);
    final formData = FormData();
    fields.forEach((key, value) => formData.fields.add(MapEntry(key, value.toString())));
    for (final path in imagePaths) {
      final multipart = await MultipartFile.fromFile(path);
      formData.files.add(MapEntry('images', multipart));
    }
    final res = await _dio.post<Map<String, dynamic>>(
      '/v1/marketplace/listings',
      data: formData,
    );
    final body = res.data ?? const {};
    return MpListing.fromJson((body['listing'] ?? body) as Map<String, dynamic>);
  }

  /// Abgelehntes Angebot bearbeiten und ERNEUT einreichen (Punkt 6).
  /// Serverseitige KI-Prüfung läuft erneut.
  Future<MpListing> resubmit({
    required String token,
    required String id,
    required Map<String, dynamic> fields,
    List<String> imagePaths = const [],
  }) async {
    _auth(token);
    final formData = FormData();
    fields.forEach((key, value) => formData.fields.add(MapEntry(key, value.toString())));
    for (final path in imagePaths) {
      final multipart = await MultipartFile.fromFile(path);
      formData.files.add(MapEntry('images', multipart));
    }
    final res = await _dio.put<Map<String, dynamic>>(
      '/v1/marketplace/listings/$id',
      data: formData,
    );
    final body = res.data ?? const {};
    return MpListing.fromJson((body['listing'] ?? body) as Map<String, dynamic>);
  }

  /// Eigene Angebote (Verwaltung im Profil).
  Future<List<MpListing>> mine({required String token}) async {
    _auth(token);
    final res = await _dio.get<Map<String, dynamic>>('/v1/marketplace/me/listings');
    final rows = (res.data ?? const {})['listings'] as List? ?? const [];
    return rows.map((e) => MpListing.fromJson(e as Map<String, dynamic>)).toList(growable: false);
  }

  Future<MpListing> setStatus({
    required String token,
    required String id,
    required String status,
  }) async {
    _auth(token);
    final res = await _dio.put<Map<String, dynamic>>(
      '/v1/marketplace/me/listings/$id/status',
      data: {'status': status},
    );
    return MpListing.fromJson((res.data ?? const {}) as Map<String, dynamic>);
  }

  Future<void> delete({required String token, required String id}) async {
    _auth(token);
    await _dio.delete<void>('/v1/marketplace/me/listings/$id');
  }

  // Favoriten
  Future<List<MpListing>> favorites({required String token}) async {
    _auth(token);
    final res = await _dio.get<Map<String, dynamic>>('/v1/marketplace/me/favorites');
    final rows = (res.data ?? const {})['listings'] as List? ?? const [];
    return rows.map((e) => MpListing.fromJson(e as Map<String, dynamic>)).toList(growable: false);
  }

  Future<void> addFavorite({required String token, required String id}) async {
    _auth(token);
    await _dio.post<void>('/v1/marketplace/me/favorites/$id');
  }

  Future<void> removeFavorite({required String token, required String id}) async {
    _auth(token);
    await _dio.delete<void>('/v1/marketplace/me/favorites/$id');
  }

  // Meldung
  Future<void> report({
    required String token,
    required String id,
    required String reason,
    String? details,
  }) async {
    _auth(token);
    await _dio.post<void>('/v1/marketplace/listings/$id/report', data: {
      'reason': reason,
      if (details != null && details.isNotEmpty) 'details': details,
    });
  }

  // Verkäufer kontaktieren -> privater Chat wird erstellt/geöffnet.
  Future<String> contactSeller({
    required String token,
    required String id,
    String? message,
  }) async {
    _auth(token);
    final res = await _dio.post<Map<String, dynamic>>(
      '/v1/marketplace/listings/$id/contact',
      data: {'message': message},
    );
    return (res.data ?? const {})['conversationId'] as String? ?? '';
  }

  // Admin
  Future<List<MpListing>> adminPending({required String token}) async {
    _auth(token);
    final res = await _dio.get<Map<String, dynamic>>('/v1/marketplace/admin/pending');
    final rows = (res.data ?? const {})['listings'] as List? ?? const [];
    return rows.map((e) => MpListing.fromJson(e as Map<String, dynamic>)).toList(growable: false);
  }

  /// Offene Meldungen für den Admin (Id, Grund, Details, Angebotstitel).
  Future<List<({int id, String reason, String details, String listingTitle})>>
      adminReports({required String token}) async {
    _auth(token);
    final res = await _dio.get<Map<String, dynamic>>('/v1/marketplace/admin/reports');
    final rows = (res.data ?? const {})['reports'] as List? ?? const [];
    return rows.map<({int id, String reason, String details, String listingTitle})>((row) {
      final r = row as Map<String, dynamic>;
      final listing = r['listing'] as Map<String, dynamic>? ?? const {};
      return (
        id: (r['id'] as num?)?.toInt() ?? 0,
        reason: r['reason'] as String? ?? '',
        details: r['details'] as String? ?? '',
        listingTitle: listing['title'] as String? ?? '(Angebot)',
      );
    }).toList(growable: false);
  }

  Future<void> adminPatch({
    required String token,
    required String id,
    String? status,
    String? reviewStatus,
    String? reason,
  }) async {
    _auth(token);
    await _dio.put<void>('/v1/marketplace/admin/listings/$id', data: {
      if (status != null) 'status': status,
      if (reviewStatus != null) 'reviewStatus': reviewStatus,
      if (reason != null) 'reason': reason,
    });
  }

  Future<void> adminResolveReport({required String token, required int reportId}) async {
    _auth(token);
    await _dio.put<void>('/v1/marketplace/admin/reports/$reportId/resolve');
  }

  // =========================================================================
  // Autocomplete (Suggest) - Marken/Modelle aus aktiven Angebot
  // =========================================================================

  /// Vorschläge für die Suchfeld-Autovervollständigung. Der Server liefert
  /// Präfix-Treffer mit Häufigkeit; die Tippfehler-Toleranz (Damerau-
  /// Levenshtein) macht die UI im suggestProvider (siehe dort).
  Future<MpSuggestions> suggest({required String token, required String q}) async {
    _auth(token);
    final res = await _dio.get<Map<String, dynamic>>(
      '/v1/marketplace/suggest',
      queryParameters: {'q': q},
    );
    return MpSuggestions.fromJson(res.data ?? const {});
  }

  // =========================================================================
  // Bewertungen (Migration 0007)
  // =========================================================================

  /// Reviews eines Angebots (öffentlich lesbar).
  Future<MpReviews> reviews({required String token, required String listingId}) async {
    _auth(token);
    final res = await _dio.get<Map<String, dynamic>>(
      '/v1/marketplace/listings/$listingId/reviews',
    );
    return MpReviews.fromJson(res.data ?? const {});
  }

  /// Eigene Bewertung abgeben/ändern (Regel: nur nach Chat-Kontakt).
  Future<void> createReview({
    required String token,
    required String listingId,
    required int rating,
    String? comment,
  }) async {
    _auth(token);
    await _dio.post<void>(
      '/v1/marketplace/listings/$listingId/reviews',
      data: {'rating': rating, if (comment != null && comment.isNotEmpty) 'comment': comment},
    );
  }

  // =========================================================================
  // In-App-Benachrichtigungen
  // =========================================================================

  /// Ungelesen-Zahl + Inbox-Einträge.
  Future<MpNotifications> notifications({required String token}) async {
    _auth(token);
    final res = await _dio.get<Map<String, dynamic>>('/v1/marketplace/notifications');
    return MpNotifications.fromJson(res.data ?? const {});
  }

  /// Alles als gelesen markieren.
  Future<void> markNotificationsRead({required String token}) async {
    _auth(token);
    await _dio.post<void>('/v1/marketplace/notifications/read-all');
  }
}

/// Autovervollständigungsvorschläge (Marken + Modelle mit Trefferzahl).
class MpSuggestions {
  final List<MpSuggestion> brands;
  final List<MpSuggestion> models;

  const MpSuggestions({required this.brands, required this.models});

  factory MpSuggestions.fromJson(Map<String, dynamic> json) => MpSuggestions(
        brands: _parseList(json['brands']),
        models: _parseList(json['models']),
      );

  static List<MpSuggestion> _parseList(dynamic raw) =>
      ((raw as List?) ?? const [])
          .map((e) => MpSuggestion.fromJson(e as Map<String, dynamic>))
          .toList(growable: false);
}

class MpSuggestion {
  final String label;
  final int count;

  const MpSuggestion({required this.label, required this.count});

  factory MpSuggestion.fromJson(Map<String, dynamic> json) => MpSuggestion(
        label: (json['label'] as String?) ?? '',
        count: (json['count'] as num?)?.toInt() ?? 0,
      );
}

/// Reviews eines Angebots inkl. Durchschnitt.
class MpReviews {
  final List<MpReview> reviews;
  final double average;
  final int count;

  const MpReviews({required this.reviews, required this.average, required this.count});

  factory MpReviews.fromJson(Map<String, dynamic> json) {
    final list = ((json['reviews'] as List?) ?? const [])
        .map((e) => MpReview.fromJson(e as Map<String, dynamic>))
        .toList(growable: false);
    final count = (json['count'] as num?)?.toInt() ?? list.length;
    final average = (json['average'] as num?)?.toDouble() ?? 0;
    return MpReviews(reviews: list, average: average, count: count);
  }
}

class MpReview {
  final int rating;
  final String comment;
  final String? createdAt;
  final String? author;

  const MpReview({
    required this.rating,
    required this.comment,
    required this.createdAt,
    required this.author,
  });

  factory MpReview.fromJson(Map<String, dynamic> json) => MpReview(
        rating: (json['rating'] as num?)?.toInt() ?? 0,
        comment: (json['comment'] as String?) ?? '',
        createdAt: json['created_at'] as String?,
        author: json['author'] as String?,
      );
}

/// In-App-Benachrichtigungen (Favorit/Meldung/Review am eigenen Angebot).
class MpNotifications {
  final List<MpNotification> items;
  final int unread;

  const MpNotifications({required this.items, required this.unread});

  factory MpNotifications.fromJson(Map<String, dynamic> json) => MpNotifications(
        items: ((json['items'] as List?) ?? const [])
            .map((e) => MpNotification.fromJson(e as Map<String, dynamic>))
            .toList(growable: false),
        unread: (json['unread'] as num?)?.toInt() ?? 0,
      );
}

class MpNotification {
  final String id;
  final String type; // favorite | report | review
  final String body;
  final String? readAt;
  final String? createdAt;
  final String? actor;
  final String? listingTitle;

  const MpNotification({
    required this.id,
    required this.type,
    required this.body,
    required this.readAt,
    required this.createdAt,
    required this.actor,
    required this.listingTitle,
  });

  factory MpNotification.fromJson(Map<String, dynamic> json) {
    final actor = json['actor'] as Map<String, dynamic>?;
    final listing = json['listing'] as Map<String, dynamic>?;
    return MpNotification(
      id: (json['id'] as String?) ?? '',
      type: (json['type'] as String?) ?? '',
      body: (json['body'] as String?) ?? '',
      readAt: json['read_at'] as String?,
      createdAt: json['created_at'] as String?,
      actor: (actor?['display_name'] ?? actor?['username']) as String?,
      listingTitle: listing?['title'] as String?,
    );
  }
}

/// Provider: Repository (Dio mit Kaltstart-Retry) + Token-Shortcut.
final marketplaceRepositoryProvider = Provider<MarketplaceRepository>(
  (ref) => MarketplaceRepository(ApiClient.create()),
);

/// Aktiver Access-Token (aus der Auth-Sitzung) für Marketplace-Requests.
final marketplaceTokenProvider = Provider<String?>((ref) {
  final auth = ref.watch(authControllerProvider);
  return auth.isAuthenticated ? ref.read(authControllerProvider.notifier).accessToken : null;
});
