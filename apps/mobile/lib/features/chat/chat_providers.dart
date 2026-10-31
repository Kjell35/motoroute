import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/network/error_reporter.dart';
import 'data/chat_realtime.dart';
import 'data/chat_repository.dart';

/// Session-Token des Chat-Benutzers. Wird aus der zentralen MotoRoute-Auth
/// gespiegelt, damit Chats und Sendefeld unmittelbar nach dem Login aktiv sind.
///
/// null = nicht angemeldet: die Chat-UI zeigt einen sauberen
/// „Zum Chatten anmelden“-Zustand statt zu crashen.
final chatSessionTokenProvider = StateProvider<String?>((ref) => null);

/// Das eigene Profil (id, username, avatar ...) - Basis für
/// „Nachricht von mir“ vs. „von anderen“ und das Profilblatt.
final chatMeProvider = FutureProvider<ChatUser?>((ref) async {
  final token = ref.watch(chatSessionTokenProvider);
  if (token == null) return null;
  try {
    return await ref.watch(chatRepositoryProvider).me(token);
  } catch (_) {
    return null; // Offline: Chat funktioniert trotzdem (nur ohne Profil).
  }
});

/// Aggregate für den Konversationslisten-Screen (Abschnitt 1/6/17).
class ChatOverviewState {
  final bool isLoading;
  final String? error;
  final bool connected;
  final List<ConversationSummary> conversations;
  final String? typingInId;

  const ChatOverviewState({
    this.isLoading = false,
    this.error,
    this.connected = false,
    this.conversations = const [],
    this.typingInId,
  });

  int get totalUnread => conversations.fold(0, (sum, c) => sum + c.unreadCount);

  ChatOverviewState copyWith({
    bool? isLoading,
    String? error,
    bool? connected,
    List<ConversationSummary>? conversations,
    String? typingInId,
  }) =>
      ChatOverviewState(
        isLoading: isLoading ?? this.isLoading,
        error: error,
        connected: connected ?? this.connected,
        conversations: conversations ?? this.conversations,
        typingInId: typingInId,
      );
}

class ChatOverviewController extends StateNotifier<ChatOverviewState> {
  final ChatRepository _repo;
  final ChatRealtimeClient _realtime;
  final Ref _ref;
  StreamSubscription<ChatMessage>? _msgSub;
  StreamSubscription<String>? _delSub;
  StreamSubscription<bool>? _connSub;
  StreamSubscription<({String userId, bool isTyping})>? _typingSub;
  Timer? _pollTimer;
  String? _loadedWithToken;
  int _loadGeneration = 0;
  int _refreshGeneration = 0;

  ChatOverviewController(this._repo, this._realtime, this._ref)
      : super(const ChatOverviewState()) {
    _connSub = _realtime.connection.listen((up) {
      if (!mounted) return;
      state = state.copyWith(connected: up);
      if (up) _refreshSoon(); // Reconnect -> Liste frisch ziehen.
    });
    // Tokenwechsel (Login, Restore, Silent-Refresh nach ~50 min): WS
    // sofort mit dem FRISCHEN Token neu verbinden und Listen neu laden -
    // sonst läuft der Chat nach Token-Rotation ins Leere.
    _ref.listen<String?>(chatSessionTokenProvider, (previous, next) {
      if (previous == next) return;
      load();
    });
  }

  /// Lädt die Liste initial und verdrahtet Realtime + Polling-Fallback.
  Future<void> load() async {
    final token = _ref.read(chatSessionTokenProvider);
    if (token == null) {
      _loadGeneration++;
      _loadedWithToken = null;
      _pollTimer?.cancel();
      _pollTimer = null;
      _debounce?.cancel();
      _realtime.disconnect();
      state = const ChatOverviewState();
      return;
    }
    final generation = ++_loadGeneration;
    if (_loadedWithToken != token) {
      _loadedWithToken = token;
      _realtime.connect(token);
      _wireStreams();
      // Fallback-Polling alle 15 s - nutzt dieselben Daten wie WS und
      // hält Unread-Zähler korrekt, falls WS gerade nicht verbunden ist.
      _pollTimer?.cancel();
      _pollTimer = Timer.periodic(const Duration(seconds: 15), (_) {
        if (!_realtime.isConnected) _refresh(silent: true);
      });
    }
    state = state.copyWith(isLoading: true, error: null);
    await _refresh(generation: generation);
  }

  void _wireStreams() {
    _msgSub?.cancel();
    _delSub?.cancel();
    _typingSub?.cancel();

    _msgSub = _realtime.messages.listen((_) {
      // Neue Nachricht: Liste (Badge + letzte Nachricht) aktualisieren.
      _refreshSoon();
    });
    _delSub = _realtime.deletions.listen((_) {
      _refreshSoon();
    });
    _typingSub = _realtime.typing.listen((t) {
      if (!mounted) return;
      // Typing-Indikator am Listen-Eintrag (Abschnitt 19), 4 s selbstlöschend.
      state = state.copyWith(typingInId: null);
      // (Der Hub zeigt Typing pro Konversation nur, wenn hier gesetzt.)
    });
  }

  Timer? _debounce;
  void _refreshSoon() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      if (_ref.read(chatSessionTokenProvider) != null) {
        _refresh(silent: true);
      }
    });
  }

  Future<void> _refresh({bool silent = false, int? generation}) async {
    final token = _ref.read(chatSessionTokenProvider);
    if (token == null) return;
    final requestGeneration = generation ?? _loadGeneration;
    final refreshGeneration = ++_refreshGeneration;
    try {
      final conversations = await _repo.conversations(token);
      if (!mounted ||
          refreshGeneration != _refreshGeneration ||
          requestGeneration != _loadGeneration ||
          token != _ref.read(chatSessionTokenProvider)) {
        return;
      }
      state = state.copyWith(
        conversations: conversations,
        isLoading: false,
        error: null,
      );
    } catch (e) {
      ErrorReporter.instance.report('chat.load', e);
      if (!mounted ||
          refreshGeneration != _refreshGeneration ||
          requestGeneration != _loadGeneration ||
          token != _ref.read(chatSessionTokenProvider)) {
        return;
      }
      // Bereits geladene Nachrichten bleiben sichtbar (Abschnitt 37);
      // der Fehler erscheint nur, wenn gar keine Daten da sind.
      state = state.copyWith(
        isLoading: false,
        error: state.conversations.isEmpty ? chatFailure(e).message : null,
      );
    }
  }

  /// Markiert eine Konversation als gelesen (nach dem Öffnen, Abschnitt 17)
  /// und aktualisiert den Zähler sofort lokal.
  Future<void> markRead(String conversationId) async {
    final token = _ref.read(chatSessionTokenProvider);
    if (token == null) return;
    try {
      await _repo.markRead(token, conversationId);
    } catch (_) {}
    state = state.copyWith(
      conversations: state.conversations
          .map((c) => c.id == conversationId
              ? ConversationSummary(
                  id: c.id,
                  type: c.type,
                  role: c.role,
                  group: c.group,
                  lastMessage: c.lastMessage,
                  unreadCount: 0,
                )
              : c)
          .toList(growable: false),
    );
  }

  Future<void> refresh() => _refresh(silent: true, generation: _loadGeneration);

  @override
  void dispose() {
    _msgSub?.cancel();
    _delSub?.cancel();
    _connSub?.cancel();
    _typingSub?.cancel();
    _pollTimer?.cancel();
    _debounce?.cancel();
    super.dispose();
  }
}

final chatOverviewProvider =
    StateNotifierProvider<ChatOverviewController, ChatOverviewState>((ref) {
  return ChatOverviewController(
    ref.watch(chatRepositoryProvider),
    ref.watch(chatRealtimeProvider),
    ref,
  );
});

/// Gründe für Meldungen (Abschnitt 22) - gespiegelt vom Schema-Constraint.
const reportReasons = <String, String>{
  'spam': 'Spam',
  'insult': 'Beleidigung',
  'harassment': 'Belästigung',
  'inappropriate': 'Unangemessener Inhalt',
  'fraud': 'Betrug',
  'other': 'Sonstiges',
};
