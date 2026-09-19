import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:motoroute_app/core/error/failure.dart';
import 'package:motoroute_app/core/network/api_client.dart';

/// Chat-Domain-Modelle - Spiegel der Backend-Endpunkte unter /v1/chat.
/// Bewusst einfache Klassen statt freezed: der Chat hat wenige, stabile
/// Formen und die JSON-Namen folgen direkt dem Backend (snake_case).

/// Öffentlicher Chat / Gruppen-Konversation. Konversations-Typen:
/// public | private | group (schema.sql check constraint).
enum ConversationType { public, private, group }

ConversationType conversationTypeFrom(String? raw) => switch (raw) {
      'public' => ConversationType.public,
      'group' => ConversationType.group,
      _ => ConversationType.private,
    };

class ChatUser {
  final String id;
  final String? username;
  final String? displayName;
  final String? avatarUrl;
  final String? vehicleDesc;
  final String? bio;
  final bool? showOnline;
  final String? lastSeenAt;

  const ChatUser({
    required this.id,
    this.username,
    this.displayName,
    this.avatarUrl,
    this.vehicleDesc,
    this.bio,
    this.showOnline,
    this.lastSeenAt,
  });

  factory ChatUser.fromJson(Map<String, dynamic> json) => ChatUser(
        id: json['id'] as String,
        username: json['username'] as String?,
        displayName: json['display_name'] as String?,
        avatarUrl: json['avatar_url'] as String?,
        vehicleDesc: json['vehicle_desc'] as String?,
        bio: json['bio'] as String?,
        showOnline: json['show_online'] as bool?,
        lastSeenAt: json['last_seen_at'] as String?,
      );

  /// Anzeigename mit Fallback-Kette (Abschnitt 3: Profilansicht).
  String get effectiveName {
    final n = displayName ?? username;
    return (n == null || n.isEmpty) ? 'Biker' : n;
  }
}

class ChatMessage {
  final String id;
  final String conversationId;
  final String senderId;
  final String content;
  final Map<String, dynamic>? attachment;
  final String? replyToId;
  final String createdAt;
  final String? deletedAt;

  /// Vom Backend als `sender:users!sender_id(...)` eingebettet.
  final ChatUser? sender;

  const ChatMessage({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.content,
    this.attachment,
    this.replyToId,
    required this.createdAt,
    this.deletedAt,
    this.sender,
  });

  bool get isDeleted => deletedAt != null;

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    final senderJson = json['sender'];
    return ChatMessage(
      id: json['id'] as String,
      conversationId: json['conversation_id'] as String,
      senderId: json['sender_id'] as String,
      content: (json['content'] ?? '') as String,
      attachment: json['attachment'] as Map<String, dynamic>?,
      replyToId: json['reply_to_id'] as String?,
      createdAt: json['created_at'] as String,
      deletedAt: json['deleted_at'] as String?,
      sender: senderJson is Map<String, dynamic> ? ChatUser.fromJson(senderJson) : null,
    );
  }
}

/// Zeile der Konversationsliste (Abschnitt 6/7/17).
class ConversationSummary {
  final String id;
  final ConversationType type;
  final String role; // owner | member | moderator
  final Map<String, dynamic>? group; // groups-Zeile bei type == group
  final Map<String, dynamic>? lastMessage;
  final int unreadCount;

  const ConversationSummary({
    required this.id,
    required this.type,
    required this.role,
    this.group,
    this.lastMessage,
    required this.unreadCount,
  });

  factory ConversationSummary.fromJson(Map<String, dynamic> json) => ConversationSummary(
        id: json['id'] as String,
        type: conversationTypeFrom(json['type'] as String?),
        role: (json['role'] ?? 'member') as String,
        group: json['group'] as Map<String, dynamic>?,
        lastMessage: json['lastMessage'] as Map<String, dynamic>?,
        unreadCount: (json['unreadCount'] ?? 0) as int,
      );
}

/// Zeile der Mitgliederliste (Abschnitt 14): Rolle + Profil.
class ConversationMember {
  final String userId;
  final String role; // owner | moderator | member
  final ChatUser user;

  const ConversationMember({required this.userId, required this.role, required this.user});

  factory ConversationMember.fromJson(Map<String, dynamic> json) => ConversationMember(
        userId: json['userId'] as String,
        role: (json['role'] ?? 'member') as String,
        user: ChatUser.fromJson(json['profile'] as Map<String, dynamic>),
      );
}

class MessagePage {
  final List<ChatMessage> messages;
  final bool hasMore;

  const MessagePage({required this.messages, required this.hasMore});
}

/// Attachments (Abschnitt 5/20/38): Architektur vorbereitet - type als
/// Diskriminator ("route" | "location" | "gpx" | ...), das Backend
/// speichert das JSONB unverändert. Das MVP sendet nur Text; die
/// Serializer sind die sauberen Anschlussstellen.
class ChatAttachment {
  static Map<String, dynamic> route({
    required String name,
    required double distanceKm,
    required double durationSeconds,
    required int curvyScore,
    String? routeId,
  }) =>
      {
        'type': 'route',
        'routeId': routeId,
        'name': name,
        'distanceKm': distanceKm,
        'durationS': durationSeconds.round(),
        'curvyScore': curvyScore,
      };

  static Map<String, dynamic> location({
    required double lat,
    required double lng,
    required String label,
  }) =>
      {'type': 'location', 'lat': lat, 'lng': lng, 'label': label};
}

/// Chat-Repository: REST gegen /v1/chat. Ein Bearer-Token wird je Call
/// übergeben (Session-Management gehört der App-Schicht, nicht Dio).
class ChatRepository {
  final Dio _dio;

  ChatRepository(this._dio);

  Dio get dio => _dio;

  void _auth(String token) => _dio.options.headers['Authorization'] = 'Bearer $token';

  // ---------------------------------------------------------------- Profil

  Future<ChatUser> me(String token) async {
    _auth(token);
    final res = await _dio.get<Map<String, dynamic>>('/v1/chat/me');
    return ChatUser.fromJson(res.data!);
  }

  Future<ChatUser> updateMe(String token, {String? displayName, String? bio, String? vehicleDesc, bool? showOnline}) async {
    _auth(token);
    final res = await _dio.put<Map<String, dynamic>>('/v1/chat/me', data: {
      if (displayName != null) 'displayName': displayName,
      if (bio != null) 'bio': bio,
      if (vehicleDesc != null) 'vehicleDesc': vehicleDesc,
      if (showOnline != null) 'showOnline': showOnline,
    });
    return ChatUser.fromJson(res.data!);
  }

  Future<List<ChatUser>> searchUsers(String token, String query) async {
    _auth(token);
    final res = await _dio.get<List<dynamic>>('/v1/chat/users/search',
        queryParameters: {'query': query});
    return (res.data ?? [])
        .map((e) => ChatUser.fromJson(e as Map<String, dynamic>))
        .toList(growable: false);
  }

  /// Mitglied einer Konversation (user_id, role, Profil eingebettet).
  Future<List<ConversationMember>> listMembers(String token, String conversationId) async {
    _auth(token);
    final res = await _dio.get<List<dynamic>>('/v1/chat/conversations/$conversationId/members');
    return (res.data ?? [])
        .map((e) => ConversationMember.fromJson(e as Map<String, dynamic>))
        .toList(growable: false);
  }

  Future<ChatUser> getUser(String token, String userId) async {
    _auth(token);
    final res = await _dio.get<Map<String, dynamic>>('/v1/chat/users/$userId');
    return ChatUser.fromJson(res.data!);
  }

  // -------------------------------------------------------- Konversationen

  Future<List<ConversationSummary>> conversations(String token) async {
    _auth(token);
    final res = await _dio.get<Map<String, dynamic>>('/v1/chat/conversations');
    final list = (res.data?['conversations'] as List<dynamic>? ?? []);
    return list
        .map((e) => ConversationSummary.fromJson(e as Map<String, dynamic>))
        .toList(growable: false);
  }

  Future<MessagePage> messages(String token, String conversationId, {String? before, int limit = 30}) async {
    _auth(token);
    final res = await _dio.get<Map<String, dynamic>>(
      '/v1/chat/conversations/$conversationId/messages',
      queryParameters: {'limit': limit, if (before != null) 'before': before},
    );
    final list = (res.data?['messages'] as List<dynamic>? ?? []);
    return MessagePage(
      messages: list.map((e) => ChatMessage.fromJson(e as Map<String, dynamic>)).toList(growable: false),
      hasMore: (res.data?['hasMore'] ?? false) as bool,
    );
  }

  Future<ChatMessage> send(String token, String conversationId, String content, {Map<String, dynamic>? attachment}) async {
    _auth(token);
    final res = await _dio.post<Map<String, dynamic>>(
      '/v1/chat/conversations/$conversationId/messages',
      data: {'content': content, if (attachment != null) 'attachment': attachment},
    );
    return ChatMessage.fromJson(res.data!);
  }

  Future<void> markRead(String token, String conversationId) async {
    _auth(token);
    await _dio.post<void>('/v1/chat/conversations/$conversationId/read');
  }

  Future<void> deleteMessage(String token, String messageId) async {
    _auth(token);
    await _dio.delete<void>('/v1/chat/messages/$messageId');
  }

  Future<String> startPrivateChat(String token, String otherUserId) async {
    _auth(token);
    final res = await _dio.post<Map<String, dynamic>>('/v1/chat/conversations/private',
        data: {'otherUserId': otherUserId});
    return res.data!['conversationId'] as String;
  }

  Future<void> typing(String token, String conversationId, {bool isTyping = true}) async {
    _auth(token);
    await _dio.post<void>('/v1/chat/typing', data: {'conversationId': conversationId, 'isTyping': isTyping});
  }

  // ---------------------------------------------------------------- Gruppen

  Future<String> createGroup(String token, {required String name, String? description, String? imageUrl, String? category}) async {
    _auth(token);
    final res = await _dio.post<Map<String, dynamic>>('/v1/chat/groups', data: {
      'name': name,
      if (description != null) 'description': description,
      if (imageUrl != null) 'imageUrl': imageUrl,
      if (category != null) 'category': category,
    });
    return res.data!['groupId'] as String;
  }

  Future<Map<String, dynamic>> group(String token, String groupId) async {
    _auth(token);
    final res = await _dio.get<Map<String, dynamic>>('/v1/chat/groups/$groupId');
    return res.data!;
  }

  Future<void> updateGroup(String token, String groupId,
      {String? name, String? description, String? imageUrl}) async {
    _auth(token);
    await _dio.put<void>('/v1/chat/groups/$groupId', data: {
      if (name != null) 'name': name,
      if (description != null) 'description': description,
      if (imageUrl != null) 'imageUrl': imageUrl,
    });
  }

  Future<void> deleteGroup(String token, String groupId) async {
    _auth(token);
    await _dio.delete<void>('/v1/chat/groups/$groupId');
  }

  /// Verlässt eine Gruppe. Response: {needsOwnershipTransfer: bool} -
  /// der Owner muss erst übertragen/löschen (Abschnitt 35).
  Future<bool> leaveGroup(String token, String groupId) async {
    _auth(token);
    final res = await _dio.post<Map<String, dynamic>>('/v1/chat/groups/$groupId/leave');
    return (res.data?['needsOwnershipTransfer'] ?? false) as bool;
  }

  Future<void> transferOwnership(String token, String groupId, String newOwnerId) async {
    _auth(token);
    await _dio.post<void>('/v1/chat/groups/$groupId/transfer-ownership',
        data: {'newOwnerId': newOwnerId});
  }

  Future<void> removeMember(String token, String groupId, String userId) async {
    _auth(token);
    await _dio.post<void>('/v1/chat/groups/$groupId/members/remove', data: {'userId': userId});
  }

  Future<String> createInvitation(String token, String groupId, {int? expiresInDays}) async {
    _auth(token);
    final res = await _dio.post<Map<String, dynamic>>('/v1/chat/groups/$groupId/invitations',
        data: {'expiresInDays': expiresInDays});
    return res.data!['code'] as String;
  }

  Future<void> deactivateInvitation(String token, String groupId) async {
    _auth(token);
    await _dio.post<void>('/v1/chat/groups/$groupId/invitations/deactivate');
  }

  Future<Map<String, dynamic>?> activeInvitation(String token, String groupId) async {
    _auth(token);
    final res = await _dio.get<Map<String, dynamic>>('/v1/chat/groups/$groupId/invitations/active');
    final code = res.data?['code'];
    return code == null ? null : {'code': code as String};
  }

  Future<Map<String, dynamic>> previewByCode(String token, String code) async {
    _auth(token);
    final res = await _dio.post<Map<String, dynamic>>('/v1/chat/invitations/preview', data: {'code': code});
    return res.data!;
  }

  Future<String> joinByCode(String token, String code) async {
    _auth(token);
    final res = await _dio.post<Map<String, dynamic>>('/v1/chat/invitations/join', data: {'code': code});
    return res.data!['conversationId'] as String;
  }

  // ------------------------------------------------------------- Moderation

  Future<void> blockUser(String token, String userId) async {
    _auth(token);
    await _dio.post<void>('/v1/chat/blocks', data: {'userId': userId});
  }

  Future<void> unblockUser(String token, String userId) async {
    _auth(token);
    await _dio.delete<void>('/v1/chat/blocks/$userId');
  }

  Future<void> reportMessage(String token, String messageId, String reason, {String? details}) async {
    _auth(token);
    await _dio.post<void>('/v1/chat/reports/message',
        data: {'messageId': messageId, 'reason': reason, if (details != null) 'details': details});
  }

  Future<void> reportUser(String token, String userId, String reason, {String? details}) async {
    _auth(token);
    await _dio.post<void>('/v1/chat/reports/user',
        data: {'reportedUserId': userId, 'reason': reason, if (details != null) 'details': details});
  }
}

/// Dio-Fehler -> Failure (bestehendes Fehlermodell der App).
Failure chatFailure(Object error) {
  if (error is DioException) {
    final status = error.response?.statusCode;
    final data = error.response?.data;
    String code = '';
    if (data is Map) code = (data['error'] ?? '') as String;
    if (error.type == DioExceptionType.connectionError ||
        error.type == DioExceptionType.connectionTimeout) {
      return const NetworkFailure('Keine Internetverbindung');
    }
    if (code == 'RATE_LIMITED') return const NetworkFailure('Zu viele Nachrichten - bitte kurz warten');
    if (code == 'BLOCKED') return const NetworkFailure('Aktion durch Blockierung verhindert');
    if (code == 'INVALID_CODE') return const NetworkFailure('Einladungscode ungültig oder abgelaufen');
    if (code == 'ALREADY_EXISTS') return const NetworkFailure('Existiert bereits');
    if (status == 401) return const NetworkFailure('Bitte neu anmelden');
    if (status == 403) return const NetworkFailure('Kein Zugriff');
    if (status == 404) return const NetworkFailure('Nicht gefunden');
    if (status == 503) return const NetworkFailure('Dienst nicht verfügbar');
    return NetworkFailure('Fehler (${status ?? 'keine Antwort'})');
  }
  return const UnexpectedFailure();
}

final chatRepositoryProvider = Provider<ChatRepository>((ref) {
  return ChatRepository(ApiClient.create());
});
