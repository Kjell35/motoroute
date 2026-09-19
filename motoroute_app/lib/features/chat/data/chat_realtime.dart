import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as ws_status;

import 'chat_repository.dart';

/// Echtzeit-Client (Abschnitt 28): WebSocket zum eigenen Backend
/// (/v1/chat/ws). KEIN Fake-Realtime - ohne Verbindung fällt der Screen
/// auf REST-Polling zurück (im Controller), die UI zeigt den Offline-Hinweis
/// (Abschnitt 37).
///
/// Protokoll = NestJS platform-ws Standard-Umschläge:
///   send:    {"event": "<name>", "data": {...}}
///   receive: {"event": "<name>", "data": {...}}
class ChatRealtimeClient {
  final String _wsBaseUrl;
  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;

  String? _token;
  Timer? _reconnectTimer;
  Timer? _heartbeat;
  int _reconnectAttempts = 0;
  bool _disposed = false;

  final _messagesController = StreamController<ChatMessage>.broadcast();
  final _deletionsController = StreamController<String>.broadcast();
  final _typingController = StreamController<({String userId, bool isTyping})>.broadcast();
  final _connectionState = StreamController<bool>.broadcast();
  final _grouprouteEvents = StreamController<GroupRouteWsEvent>.broadcast();
  final _bikerPoiChanges = StreamController<List<({String id, String action})>>.broadcast();
  final _radarEvents = StreamController<RadarEvent>.broadcast();

  /// Neue Nachrichten (aus dem WS-Strom).
  Stream<ChatMessage> get messages => _messagesController.stream;

  /// Gelöschte Nachrichten (messageId).
  Stream<String> get deletions => _deletionsController.stream;

  /// „Max schreibt gerade …“-Ereignisse (Abschnitt 19).
  Stream<({String userId, bool isTyping})> get typing => _typingController.stream;

  /// Kollaborative Routen-Änderungen (grouproute.*-Events des Backends).
  Stream<GroupRouteWsEvent> get grouprouteEvents => _grouprouteEvents.stream;

  /// Server-Push: kuratierte Biker-POIs wurden geändert (bikerpoi.batch,
  /// vom BFF aus dem Socket.IO-Strom des POI-Dienstes koalesziert).
  /// Enthält bewusst nur IDs + Aktionen - die Daten zieht der Sync-
  /// Controller per Delta-Sync (server-autoritativ, wie bei den
  /// Gruppenrouten), damit der Karten-Zustand nie vom WS-Strom abweicht.
  Stream<List<({String id, String action})>> get bikerPoiChanges => _bikerPoiChanges.stream;

  /// Ride-Radar (Live-Gruppenfahrt + Radar): Positionen der eigenen
  /// Route unabhängig vom Umkreis. Nur nach subscribe_ride (server-
  /// seitiger Membership-Prüfung) kommen hier Events an.
  Stream<RadarEvent> get radarEvents => _radarEvents.stream;

  /// true = verbunden. Der Controller nutzt das für den Offline-Banner.
  Stream<bool> get connection => _connectionState.stream;

  ChatRealtimeClient({String? wsBaseUrl})
      : _wsBaseUrl = wsBaseUrl ??
            (const String.fromEnvironment('API_BASE_URL', defaultValue: 'http://10.0.2.2:3000')
                .replaceFirst('http://', 'ws://')
                .replaceFirst('https://', 'wss://'));

  bool get isConnected => _channel != null && _channel!.closeCode == null;

  void connect(String token) {
    if (_disposed) return;
    _token = token;
    _openSocket();
  }

  void _openSocket() {
    final token = _token;
    if (token == null || _disposed) return;

    _closeChannel(quiet: true);
    try {
      // NestJS platform-ws: Verbindung selbst ist unauthentifiziert, das
      // Token geht als erstes auth-Frame (gleiche Sicherheit wie REST:
      // Validierung serverseitig via Supabase auth.getUser).
      _channel = WebSocketChannel.connect(Uri.parse(_wsBaseUrl));
      _subscription = _channel!.stream.listen(
        _onData,
        onDone: _scheduleReconnect,
        onError: (_) => _scheduleReconnect(),
        cancelOnError: true,
      );
      _connectionState.add(true);
      _reconnectAttempts = 0;
      send('auth', {'token': token});
      // Heartbeat: hält Mobilfunk-Verbindungen offen, erkennt tote Sockets.
      _heartbeat?.cancel();
      _heartbeat = Timer.periodic(const Duration(seconds: 30), (_) {
        // Der Server kennt kein ping-Event -> unbekannte Events antworten
        // mit error, was harmlos ist; primär geht es um TCP-Aktivität.
        send('ping', {});
      });
    } catch (_) {
      _scheduleReconnect();
    }
  }

  void _onData(dynamic raw) {
    try {
      final frame = jsonDecode(raw as String) as Map<String, dynamic>;
      final event = frame['event'] as String?;
      final data = frame['data'];
      switch (event) {
        case 'chat.message.created':
          if (data is Map<String, dynamic>) {
            _messagesController.add(ChatMessage.fromJson(data));
          }
          break;
        case 'chat.message.deleted':
          if (data is Map<String, dynamic>) {
            _deletionsController.add(data['messageId'] as String);
          }
          break;
        case 'chat.typing':
          if (data is Map<String, dynamic>) {
            _typingController.add((
              userId: data['userId'] as String,
              isTyping: data['isTyping'] as bool? ?? false,
            ));
          }
          break;
        case 'grouproute.updated':
        case 'grouproute.stop_added':
        case 'grouproute.stop_removed':
        case 'grouproute.reordered':
        case 'grouproute.recalculated':
        case 'grouproute.status_changed':
        case 'grouproute.permission_changed':
        case 'groupride.sharing_started':
        case 'groupride.position_updated':
        case 'groupride.sharing_stopped':
        case 'groupride.finished':
          if (data is Map<String, dynamic>) {
            _grouprouteEvents.add(GroupRouteWsEvent(
              type: event!,
              routeId: data['routeId'] as String? ?? '',
            ));
          }
          break;
        case 'groupride.radar':
          if (data is Map<String, dynamic>) {
            final members = ((data['members'] as List<dynamic>? ?? const []))
                .whereType<Map<String, dynamic>>()
                .map(RadarMember.fromJson)
                .toList(growable: false);
            _radarEvents.add(RadarEvent(
              routeId: data['routeId'] as String? ?? '',
              members: members,
            ));
          }
          break;
        case 'groupride.radar_leave':
          if (data is Map<String, dynamic>) {
            _radarEvents.add(RadarEvent(
              routeId: data['routeId'] as String? ?? '',
              members: const [],
              leftUserId: data['userId'] as String? ?? '',
            ));
          }
          break;
        case 'bikerpoi.batch':
          if (data is Map<String, dynamic>) {
            final changes = ((data['changes'] as List<dynamic>? ?? const []))
                .whereType<Map<String, dynamic>>()
                .map((c) => (
                      id: c['id'] as String? ?? '',
                      action: c['action'] as String? ?? 'upsert',
                    ))
                .where((c) => c.id.isNotEmpty)
                .toList(growable: false);
            if (changes.isNotEmpty) _bikerPoiChanges.add(changes);
          }
          break;
        case 'auth_ok':
        case 'subscribed':
        case 'error':
        default:
          break; // Protokoll-Frames interessieren den Controller nicht.
      }
    } catch (_) {
      // Kaputtes Frame ignorieren - der Strom lebt weiter.
    }
  }

  void send(String event, Map<String, dynamic> data) {
    final channel = _channel;
    if (channel == null || channel.closeCode != null) return;
    try {
      channel.sink.add(jsonEncode({'event': event, 'data': data}));
    } catch (_) {
      // Sende-Fehler = Verbindung tot; onDone löst Reconnect.
    }
  }

  void subscribe(String conversationId) => send('subscribe', {'conversationId': conversationId});

  void unsubscribe(String conversationId) => send('unsubscribe', {'conversationId': conversationId});

  /// Ride-Radar abonnieren (serverseitige Membership-Prüfung; Antwort
  /// subscribed_ride bzw. error - die Auswertung macht der Controller
  /// über die radarEvents bzw. den Refresh-Pfad).
  void subscribeRide(String routeId) => send('subscribe_ride', {'routeId': routeId});

  void unsubscribeRide(String routeId) => send('unsubscribe_ride', {'routeId': routeId});

  /// Test-Hook: Radar-Event direkt in den Strom injizieren (ohne echten
  /// WS-Server - derselbe Codepfad wie _onData, nur ohne Transport).
  void testInjectRadarEvent(RadarEvent event) => _radarEvents.add(event);

  void sendTyping(String conversationId, {bool isTyping = true}) =>
      send('typing', {'conversationId': conversationId, 'isTyping': isTyping});

  void _scheduleReconnect() {
    if (_disposed) return;
    _connectionState.add(false);
    _heartbeat?.cancel();
    // Exponentielles Backoff, gedeckelt bei 30 s (Mobilfunk: häufige
    // kurze Funklöcher, kein Grund für langen Stillstand).
    final delay = Duration(seconds: (1 << _reconnectAttempts.clamp(0, 5)).clamp(1, 30));
    _reconnectAttempts += 1;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(delay, _openSocket);
  }

  void _closeChannel({bool quiet = false}) {
    _heartbeat?.cancel();
    _subscription?.cancel();
    try {
      _channel?.sink.close(ws_status.normalClosure);
    } catch (_) {
      if (!quiet) rethrow;
    }
    _channel = null;
    if (!quiet) _connectionState.add(false);
  }

  void dispose() {
    _disposed = true;
    _reconnectTimer?.cancel();
    _closeChannel(quiet: true);
    _messagesController.close();
    _deletionsController.close();
    _typingController.close();
    _connectionState.close();
    _grouprouteEvents.close();
    _bikerPoiChanges.close();
    _radarEvents.close();
  }
}

/// Gruppiertes WS-Event einer gemeinsamen Route (routeId genügt dem
/// Client - die Details zieht er sich per GET, damit der Zustand immer
/// server-authoritativ ist, Abschnitt 14).
class GroupRouteWsEvent {
  final String type;
  final String routeId;
  const GroupRouteWsEvent({required this.type, required this.routeId});
}

/// Fahrer-Position aus dem Ride-Radar (groupride.radar).
class RadarMember {
  final String userId;
  final double lat;
  final double lng;
  final String? lastSeen;

  const RadarMember({
    required this.userId,
    required this.lat,
    required this.lng,
    this.lastSeen,
  });

  factory RadarMember.fromJson(Map<String, dynamic> json) => RadarMember(
        userId: json['userId'] as String,
        lat: (json['lat'] as num).toDouble(),
        lng: (json['lng'] as num).toDouble(),
        lastSeen: json['lastSeen'] as String?,
      );
}

/// Ride-Radar-Event: Mitgliederliste der Route (serverseitig verifiziert)
/// oder ein einzelnes Verlassen (leftUserId gesetzt, members leer).
class RadarEvent {
  final String routeId;
  final List<RadarMember> members;
  final String leftUserId;

  const RadarEvent({
    required this.routeId,
    required this.members,
    this.leftUserId = '',
  });

  bool get isLeave => leftUserId.isNotEmpty;
}

final chatRealtimeProvider = Provider<ChatRealtimeClient>((ref) {
  final client = ChatRealtimeClient();
  ref.onDispose(client.dispose);
  return client;
});
