import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/i18n.dart';
import '../../../core/network/error_message.dart' show friendlyErrorMessage;
import '../../../core/network/error_reporter.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../chat_providers.dart';
import '../data/chat_outbox.dart';
import '../data/chat_realtime.dart';
import '../data/chat_repository.dart';
import 'widgets/avatar.dart';
import 'widgets/chat_formatters.dart';
import 'widgets/report_sheet.dart';
import 'widgets/user_profile_sheet.dart';

/// Singleton-ID des öffentlichen Chats - Spiegel von schema.sql
/// (Seed-Konstante) und PUBLIC_CONVERSATION_ID im Backend.
const publicConversationId = '00000000-0000-0000-0000-000000000001';

/// Konversations-Screen für alle Typen (public/private/group) - Abschnitt
/// 31/32/33 teilen dieselbe Nachrichtenliste; Header und Aktionen
/// unterscheiden sich über `type`/`group`.
///
/// Performance (Abschnitt 36): Pagination per Cursor (ältere Nachrichten
/// werden beim Scrollen nachgeladen), Realtime-Anhängen ohne Re-Fetch der
/// Historie, Listen virtualisiert via ListView.builder (default).
/// Meldung nach fehlgeschlagenem Senden: der Text steht wieder im
/// Eingabefeld, und die Meldung bietet den zweiten Versuch direkt an,
/// damit der Nutzer nicht erst den Sendeknopf suchen muss.
SnackBar chatSendFailedSnackBar({
  required String message,
  required VoidCallback onRetry,
}) =>
    SnackBar(
      // Etwas laenger als der Standard, damit die Aktion lesbar bleibt.
      duration: const Duration(seconds: 6),
      content: Text(message),
      action: SnackBarAction(label: 'Erneut senden', onPressed: onRetry),
    );

/// Wartezeit des Ersatz-Pollings nach [failures] Fehlschlaegen in Folge.
///
/// 8 s, dann 16 s, 32 s und ab drei Fehlschlaegen 60 s. Kleiner Wert, weil
/// der Chat bei kurzen Funkloechern schnell wieder aktuell sein soll.
int chatPollIntervalSeconds(int failures) {
  final step = failures < 0 ? 0 : (failures > 3 ? 3 : failures);
  final seconds = 8 * (1 << step);
  return seconds > 60 ? 60 : seconds;
}

class ConversationScreen extends ConsumerStatefulWidget {
  final String conversationId;
  final String title;
  final String? subtitle;
  final ConversationType type;
  final Map<String, dynamic>? group;

  /// `embedded` = ohne eigenes Scaffold/AppBar (nutzt den Hub-Tab).
  final bool embedded;

  const ConversationScreen({
    super.key,
    required this.conversationId,
    required this.title,
    this.subtitle,
    this.type = ConversationType.public,
    this.group,
    this.embedded = false,
  });

  @override
  ConsumerState<ConversationScreen> createState() => _ConversationScreenState();
}

class _ConversationScreenState extends ConsumerState<ConversationScreen> {
  final _scrollController = ScrollController();
  final _inputController = TextEditingController();
  final _composerFocus = FocusNode();

  List<ChatMessage> _messages = []; // Neu-Zuweisung bei Soft-Delete-Updates.
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = false;
  bool _sending = false;
  bool _connected = true;
  int _pollFailures = 0;
  String? _error;
  String? _replyToId;
  String? _otherTypingUserId; // Abschnitt 19
  Timer? _typingStopTimer;
  Timer? _fallbackPollTimer;
  bool _polling = false;
  String? _loadedForToken;
  int _loadGeneration = 0;
  int _loadMoreGeneration = 0;
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  Timer? _readTimer;

  ChatRepository get _repo => ref.read(chatRepositoryProvider);
  String? get _token => ref.read(chatSessionTokenProvider);

  @override
  void initState() {
    super.initState();
    _loadInitial();
    _scrollController.addListener(_onScroll);
    _wireRealtime();
    // Lesen markieren (Abschnitt 17) nach kurzem Verweilen.
    _readTimer = Timer(const Duration(seconds: 2), _markRead);
    ref.listenManual<String?>(chatSessionTokenProvider, (previous, next) {
      if (previous == next) return;
      _loadGeneration++;
      _loadMoreGeneration++;
      _loadedForToken = null;
      _polling = false;
      if (next == null) {
        ref.read(chatRealtimeProvider).unsubscribe(widget.conversationId);
        setState(() {
          _isLoadingMore = false;
          _messages = [];
          _hasMore = false;
          _isLoading = false;
          _error = null;
        });
      } else {
        final realtime = ref.read(chatRealtimeProvider);
        realtime.connect(next);
        setState(() {
          _isLoadingMore = false;
          _messages = [];
          _hasMore = false;
          _isLoading = true;
          _error = null;
        });
        _loadInitial();
      }
    });
    // REST-Fallback: Solange der WebSocket nicht verbunden ist (Funkloch,
    // Render-Kaltstart), holt ein Poller neue Nachrichten - der Chat
    // funktioniert dann verzögert, aber zuverlässig (Vater-tauglich).
    // Der Abstand waechst mit jedem Fehlschlag (siehe _scheduleFallbackPoll).
    _connected = ref.read(chatRealtimeProvider).isConnected;
    _scheduleFallbackPoll();
  }

  @override
  void dispose() {
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    _loadGeneration++;
    _loadMoreGeneration++;
    ref.read(chatRealtimeProvider).unsubscribe(widget.conversationId);
    _scrollController.dispose();
    _inputController.dispose();
    _composerFocus.dispose();
    _typingStopTimer?.cancel();
    _fallbackPollTimer?.cancel();
    _readTimer?.cancel();
    super.dispose();
  }

  /// Plant den naechsten Ersatz-Poll.
  ///
  /// Der Abstand waechst mit jedem Fehlschlag (8 s → 16 s → 32 s → 60 s):
  /// im Funkloch soll nicht alle acht Sekunden ein Request ins Leere laufen.
  /// Nach einem Erfolg oder einer stehenden WebSocket-Verbindung beginnt es
  /// wieder bei 8 s.
  void _scheduleFallbackPoll() {
    _fallbackPollTimer?.cancel();
    final seconds = chatPollIntervalSeconds(_pollFailures);
    _fallbackPollTimer = Timer(Duration(seconds: seconds), () async {
      if (!mounted) return;
      if (ref.read(chatRealtimeProvider).isConnected) {
        _pollFailures = 0;
      } else {
        final ok = await _pollNewMessages();
        _pollFailures = ok ? 0 : _pollFailures + 1;
      }
      if (mounted) _scheduleFallbackPoll();
    });
  }

  /// Fallback-Poll (nur wenn WS aus): letzte 30 Nachrichten ziehen und
  /// Unbekannte ergänzen - derselbe Dedupe-Pfad wie beim WS-Empfang.
  ///
  /// `true` = Anfrage kam durch (auch ohne neue Nachrichten), `false` =
  /// Fehlschlag - daran haengt das Backoff.
  Future<bool> _pollNewMessages() async {
    final token = _token;
    if (token == null) return true;
    if (_polling) return true;
    final generation = _loadGeneration;
    _polling = true;
    try {
      final page =
          await _repo.messages(token, widget.conversationId, limit: 30);
      if (!mounted || _token != token || generation != _loadGeneration) {
        return true;
      }
      final knownIds = _messages.map((m) => m.id).toSet();
      final fresh =
          page.messages.where((m) => !knownIds.contains(m.id)).toList();
      if (fresh.isNotEmpty) {
        final merged = [..._messages, ...fresh]
          ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
        setState(() => _messages = merged);
        _jumpToBottom();
      }
      return true;
    } catch (_) {
      // Offline: der naechste Versuch wartet laenger (Backoff).
      return false;
    } finally {
      if (generation == _loadGeneration) {
        _polling = false;
      }
    }
  }

  Future<void> _loadInitial() async {
    final token = _token;
    if (token == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }
    final generation = ++_loadGeneration;
    _loadedForToken = token;
    ref.read(chatRealtimeProvider).subscribe(widget.conversationId);
    try {
      final page = await _repo.messages(token, widget.conversationId);
      if (!mounted ||
          _token != token ||
          _loadedForToken != token ||
          generation != _loadGeneration) {
        return;
      }
      setState(() {
        final mergedById = <String, ChatMessage>{
          for (final message in page.messages) message.id: message,
          for (final message in _messages) message.id: message,
        };
        _messages = mergedById.values.toList()
          ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
        _hasMore = page.hasMore;
        _isLoading = false;
        _error = null;
      });
      _jumpToBottom();
    } catch (e) {
      ErrorReporter.instance.report('chat.load', e);
      if (!mounted ||
          _token != token ||
          _loadedForToken != token ||
          generation != _loadGeneration) {
        return;
      }
      setState(() {
        _isLoading = false;
        _error =
            'Nachrichten konnten nicht geladen werden · ${friendlyErrorMessage(e, ref.read(i18nProvider))}';
      });
    }
  }

  Future<void> _retryInitialLoad() async {
    if (_isLoading) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });
    await _loadInitial();
  }

  Future<void> _loadMore() async {
    if (_isLoadingMore || !_hasMore || _messages.isEmpty) return;
    final token = _token;
    if (token == null) return;
    final generation = ++_loadMoreGeneration;
    final firstMessageId = _messages.first.id;
    setState(() => _isLoadingMore = true);
    try {
      final page = await _repo.messages(token, widget.conversationId,
          before: _messages.first.createdAt);
      if (!mounted ||
          generation != _loadMoreGeneration ||
          token != _token ||
          _messages.isEmpty ||
          _messages.first.id != firstMessageId) {
        return;
      }
      setState(() {
        final existingIds = _messages.map((message) => message.id).toSet();
        final older = page.messages
            .where((message) => !existingIds.contains(message.id))
            .toList(growable: false);
        _messages.insertAll(0, older);
        _hasMore =
            page.messages.isEmpty || older.isEmpty ? false : page.hasMore;
        _isLoadingMore = false;
      });
    } catch (_) {
      if (mounted && generation == _loadMoreGeneration) {
        setState(() => _isLoadingMore = false);
      }
    }
  }

  void _onScroll() {
    // Lazy Loading: knapp über dem Listenanfang ältere Nachrichten holen.
    if (_scrollController.hasClients &&
        _scrollController.position.pixels < 200) {
      _loadMore();
    }
  }

  void _wireRealtime() {
    final realtime = ref.read(chatRealtimeProvider);
    _subscriptions.add(realtime.messages.listen((msg) {
      if (!mounted || msg.conversationId != widget.conversationId) return;
      if (_messages.any((m) => m.id == msg.id)) return; // Dedupe (WS + Polling)
      setState(() {
        _messages.add(msg);
        _otherTypingUserId = null;
      });
      _jumpToBottom();
    }));
    _subscriptions.add(realtime.deletions.listen((messageId) {
      if (!mounted) return;
      setState(() {
        _messages = _messages
            .map((m) => m.id == messageId
                ? ChatMessage(
                    id: m.id,
                    conversationId: m.conversationId,
                    senderId: m.senderId,
                    content: '',
                    attachment: null,
                    replyToId: m.replyToId,
                    createdAt: m.createdAt,
                    deletedAt: DateTime.now().toIso8601String(),
                    sender: m.sender,
                  )
                : m)
            .toList(growable: false);
      });
    }));
    _subscriptions.add(realtime.typing.listen((t) {
      if (!mounted || t.userId == ref.read(chatMeProvider).value?.id) return;
      // Nur anzeigen, wenn in DIESEM Chat getippt wird (Abschnitt 19).
      setState(() => _otherTypingUserId = t.isTyping ? t.userId : null);
      _typingStopTimer?.cancel();
      if (t.isTyping) {
        _typingStopTimer = Timer(const Duration(seconds: 4), () {
          if (mounted) setState(() => _otherTypingUserId = null);
        });
      }
    }));
    _subscriptions.add(realtime.connection.listen((up) {
      if (mounted) setState(() => _connected = up);
      if (up) {
        // Wiederverbunden: Backoff zuruecksetzen und Wartendes rausschicken.
        _pollFailures = 0;
        _flushOutbox();
      }
    }));
    // Steht die Verbindung beim Oeffnen schon, gibt es kein neues Event -
    // dann muss die Warteschlange einmal direkt angestossen werden.
    if (realtime.isConnected) _flushOutbox();
  }

  Future<void> _markRead() async {
    if (_token == null) return;
    await ref
        .read(chatOverviewProvider.notifier)
        .markRead(widget.conversationId);
  }

  void _jumpToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      }
    });
  }

  Future<void> _send() async {
    final token = _token;
    final text = _inputController.text.trim();
    if (token == null || text.isEmpty || _sending) return;

    setState(() => _sending = true);
    _inputController.clear();
    try {
      final msg = await _repo.send(token, widget.conversationId, text);
      if (!mounted || _token != token) return;
      // Optimistisch anzeigen; WS-Dedupe verhindert Doppelung.
      if (!_messages.any((m) => m.id == msg.id)) {
        setState(() => _messages.add(msg));
        _jumpToBottom();
      }
    } catch (e) {
      ErrorReporter.instance.report('chat.send', e);
      if (!mounted) return;
      // In die Warteschlange statt nur zurueck ins Feld: die Nachricht
      // ueberlebt das Verlassen des Screens und einen App-Neustart.
      await ref
          .read(chatOutboxProvider.notifier)
          .enqueue(widget.conversationId, text);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(chatSendFailedSnackBar(
        message:
            'Nicht gesendet - wartet auf Verbindung: ${friendlyErrorMessage(e, ref.read(i18nProvider))}',
        onRetry: _flushOutbox,
      ));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _onComposerChanged(String text) {
    final token = _token;
    if (token == null) return;
    // Typing-Event über WS (throttled serverseitig), Abschnitt 19.
    if (text.isNotEmpty) {
      ref.read(chatRealtimeProvider).sendTyping(widget.conversationId);
    }
  }

  Future<void> _deleteMessage(ChatMessage msg) async {
    final token = _token;
    if (token == null) return;
    try {
      await _repo.deleteMessage(token, msg.id);
      if (!mounted) return;
      setState(() {
        _messages = _messages
            .map((m) => m.id == msg.id
                ? ChatMessage(
                    id: m.id,
                    conversationId: m.conversationId,
                    senderId: m.senderId,
                    content: '',
                    attachment: null,
                    replyToId: m.replyToId,
                    createdAt: m.createdAt,
                    deletedAt: DateTime.now().toIso8601String(),
                    sender: m.sender,
                  )
                : m)
            .toList(growable: false);
      });
    } catch (e) {
      ErrorReporter.instance.report('chat.other', e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                'Löschen fehlgeschlagen: ${friendlyErrorMessage(e, ref.read(i18nProvider))}')));
      }
    }
  }

  void _reportMessage(ChatMessage msg) {
    final token = _token;
    showReportSheet(
      context,
      title: 'Nachricht melden',
      onSubmit: (reason, details) async {
        if (token != null) {
          await _repo.reportMessage(token, msg.id, reason, details: details);
        }
      },
    );
  }

  void _openMessageActions(ChatMessage msg) {
    final isMine = msg.senderId == ref.read(chatMeProvider).value?.id;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: context.palette.bgSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading:
                  Icon(Icons.reply, color: context.palette.accentPrimary),
              title: Text('Antworten',
                  style: TextStyle(color: context.palette.textPrimary)),
              onTap: () {
                Navigator.pop(context);
                setState(() => _replyToId = msg.id);
                _composerFocus.requestFocus();
              },
            ),
            if (isMine)
              ListTile(
                leading: Icon(Icons.delete_outline,
                    color: context.palette.statusDanger),
                title: Text('Nachricht löschen',
                    style: TextStyle(color: context.palette.textPrimary)),
                subtitle: Text(
                    'Wird für alle als „Nachricht gelöscht“ angezeigt',
                    style: TextStyle(
                        color: context.palette.textSecondary, fontSize: 12)),
                onTap: () {
                  Navigator.pop(context);
                  _deleteMessage(msg);
                },
              ),
            if (!isMine)
              ListTile(
                leading: Icon(Icons.flag_outlined,
                    color: context.palette.statusWarning),
                title: Text('Nachricht melden',
                    style: TextStyle(color: context.palette.textPrimary)),
                onTap: () {
                  Navigator.pop(context);
                  _reportMessage(msg);
                },
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(chatMeProvider).value;
    final body = Column(
      children: [
        if (!_connected)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 6),
            color: context.palette.statusWarning.withValues(alpha: 0.15),
            child: Text(
              'Keine Verbindung zum Chat – Nachrichten werden gespeichert und automatisch gesendet.',
              textAlign: TextAlign.center,
              style: TextStyle(color: context.palette.statusWarning, fontSize: 12),
            ),
          ),
        Expanded(
          child: _isLoading && _messages.isEmpty
              ? Center(
                  child: CircularProgressIndicator(
                      color: context.palette.accentPrimary))
              : _error != null && _messages.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpacing.lg),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _error!,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  color: context.palette.textSecondary),
                            ),
                            const SizedBox(height: AppSpacing.md),
                            FilledButton.icon(
                              onPressed: _retryInitialLoad,
                              icon: const Icon(Icons.refresh),
                              label: const Text('Erneut versuchen'),
                              style: FilledButton.styleFrom(
                                backgroundColor: context.palette.accentPrimary,
                                foregroundColor: context.palette.textPrimary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  : _buildMessageList(me),
        ),
        if (_otherTypingUserId != null) _buildTypingIndicator(),
        _buildOutboxBar(),
        _buildComposer(),
      ],
    );

    if (widget.embedded) return body;
    return Scaffold(
      backgroundColor: context.palette.bgBase,
      appBar: AppBar(
        backgroundColor: context.palette.bgSurface,
        title: Row(
          children: [
            if (widget.type == ConversationType.group)
              CircleAvatar(
                radius: 16,
                backgroundColor: context.palette.bgSurfaceRaised,
                child: Text(
                  widget.title.isNotEmpty
                      ? widget.title.characters.first.toUpperCase()
                      : 'G',
                  style: TextStyle(
                      color: context.palette.accentText, fontSize: 13),
                ),
              )
            else
              Icon(Icons.lock_outline,
                  size: 18, color: context.palette.textSecondary),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: context.palette.textPrimary, fontSize: 16)),
                  if (widget.subtitle != null)
                    Text(widget.subtitle!,
                        style: TextStyle(
                            color: context.palette.textSecondary, fontSize: 12)),
                ],
              ),
            ),
            // Gruppeninfo (Abschnitt 33)
            if (widget.type == ConversationType.group)
              IconButton(
                icon: Icon(Icons.info_outline,
                    color: context.palette.textSecondary),
                onPressed: () => Navigator.of(context).pushNamed(
                  '/chat/group-info',
                  arguments: {
                    'group': widget.group,
                    'conversationId': widget.conversationId
                  },
                ),
              ),
          ],
        ),
      ),
      body: body,
    );
  }

  Widget _buildMessageList(ChatUser? me) {
    if (_messages.isEmpty) {
      return Center(
        child: Text(
          'Noch keine Nachrichten.\nSchreib die erste!',
          textAlign: TextAlign.center,
          style: TextStyle(color: context.palette.textSecondary),
        ),
      );
    }
    return ListView.builder(
      controller: _scrollController,
      reverse: false,
      padding: const EdgeInsets.all(AppSpacing.md),
      itemCount: _messages.length + (_hasMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (_hasMore && index == 0) {
          return _isLoadingMore
              ? const Padding(
                  padding: EdgeInsets.all(12),
                  child: Center(
                      child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2))),
                )
              : TextButton(
                  onPressed: _loadMore,
                  child: Text('Ältere Nachrichten laden',
                      style: TextStyle(color: context.palette.textSecondary)),
                );
        }
        final adjusted = _hasMore ? index - 1 : index;
        final msg = _messages[adjusted];
        return _MessageBubble(
          message: msg,
          isMine: me != null && msg.senderId == me.id,
          onTap: () => _openMessageActions(msg),
          onSenderTap: (sender) => showUserProfileSheet(context, ref, sender),
        );
      },
    );
  }

  Widget _buildTypingIndicator() {
    return Padding(
      padding: const EdgeInsets.only(left: AppSpacing.lg, bottom: 4),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          'schreibt gerade …',
          style: TextStyle(
              color: context.palette.textSecondary,
              fontStyle: FontStyle.italic,
              fontSize: 12),
        ),
      ),
    );
  }

  /// Sendet, was in der Warteschlange liegt, und laedt danach die Historie
  /// nach - so erscheint die eben gesendete Nachricht mit ihrer Server-ID.
  Future<void> _flushOutbox() async {
    final token = _token;
    if (token == null) return;
    final sent = await ref.read(chatOutboxProvider.notifier).flush(_repo, token);
    if (!mounted || sent == 0) return;
    await _pollNewMessages();
  }

  /// Hinweis ueber dem Eingabefeld, solange Nachrichten warten.
  Widget _buildOutboxBar() {
    final pending = ref
        .watch(chatOutboxProvider)
        .where((m) => m.conversationId == widget.conversationId)
        .toList(growable: false);
    if (pending.isEmpty) return const SizedBox.shrink();
    final label = pending.length == 1
        ? '1 Nachricht wartet auf Verbindung'
        : '${pending.length} Nachrichten warten auf Verbindung';
    return Container(
      width: double.infinity,
      color: context.palette.bgSurfaceRaised,
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md, vertical: AppSpacing.xs),
      child: Row(children: [
        Icon(Icons.cloud_upload_outlined,
            size: 16, color: context.palette.textSecondary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(label,
              style: TextStyle(
                  color: context.palette.textSecondary, fontSize: 12)),
        ),
        TextButton(
          onPressed: _flushOutbox,
          child: const Text('Jetzt senden', style: TextStyle(fontSize: 12)),
        ),
      ]),
    );
  }

  Widget _buildComposer() {
    final disabled = _token == null || _isLoading;
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md, vertical: AppSpacing.sm),
        decoration: BoxDecoration(
          color: context.palette.bgSurface,
          border: Border(top: BorderSide(color: context.palette.borderHairline)),
        ),
        child: Row(
          children: [
            if (_replyToId != null)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Chip(
                  label:
                      const Text('Antworten', style: TextStyle(fontSize: 11)),
                  backgroundColor: context.palette.bgSurfaceRaised,
                  onDeleted: () => setState(() => _replyToId = null),
                ),
              ),
            Expanded(
              child: TextField(
                controller: _inputController,
                focusNode: _composerFocus,
                enabled: !disabled,
                maxLines: null,
                minLines: 1,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _send(),
                onChanged: _onComposerChanged,
                style: TextStyle(color: context.palette.textPrimary),
                decoration: InputDecoration(
                  hintText: _token == null
                      ? 'Zum Chatten anmelden'
                      : _isLoading
                          ? 'Nachrichten werden geladen …'
                          : 'Nachricht schreiben ...',
                  hintStyle: TextStyle(color: context.palette.textSecondary),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide:
                        BorderSide(color: context.palette.borderHairline),
                  ),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            IconButton(
              onPressed: disabled || _sending ? null : _send,
              tooltip: 'Nachricht senden',
              icon: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                    color: context.palette.accentPrimary, shape: BoxShape.circle),
                child: _sending
                    ? Padding(
                        padding: const EdgeInsets.all(12),
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: context.palette.textPrimary),
                      )
                    : Icon(Icons.send,
                        color: context.palette.textPrimary, size: 20),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Route-Card im Chat (Abschnitt 20): Name, km, Dauer, Kurven-Score,
/// Stopps + Öffnen-Button.
class _RouteCard extends StatelessWidget {
  final Map<String, dynamic> attachment;
  const _RouteCard({required this.attachment});

  @override
  Widget build(BuildContext context) {
    final name = (attachment['name'] ?? 'Route') as String;
    final km = (attachment['distanceKm'] as num?)?.toDouble();
    final durationS = (attachment['durationS'] as num?)?.toInt();
    final score = attachment['curvyScore'];
    final routeId = attachment['routeId'] as String?;
    final hours = durationS == null ? null : durationS ~/ 3600;
    final minutes = durationS == null ? null : (durationS % 3600) ~/ 60;

    return Container(
      margin: const EdgeInsets.only(top: 4, bottom: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.palette.bgSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: context.palette.accentPrimary.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(name.toUpperCase(),
              style: TextStyle(
                  color: context.palette.accentText,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5)),
          const SizedBox(height: 6),
          Text(
            [
              if (km != null) '${km.toStringAsFixed(0)} km',
              if (hours != null)
                '$hours:${minutes.toString().padLeft(2, '0')} h',
              if (score != null) '🌀 Kurven-Score $score',
            ].join(' · '),
            style:
                TextStyle(color: context.palette.textPrimary, fontSize: 13),
          ),
          if (routeId != null && routeId.isNotEmpty) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: context.palette.accentPrimary,
                  foregroundColor: context.palette.textPrimary,
                ),
                icon: const Icon(Icons.route, size: 18),
                label: const Text('ROUTE ÖFFNEN',
                    style: TextStyle(
                        fontWeight: FontWeight.w700, letterSpacing: 0.5)),
                onPressed: () => Navigator.of(context).pushNamed(
                    '/chat/group-route-planner',
                    arguments: {'routeId': routeId}),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Nachrichten-Bubble (Abschnitt 20/21/31): Profilbild, Name, Zeit,
/// Text. Gelöschte Nachrichten zeigen den Tombstone.
class _MessageBubble extends StatelessWidget {
  final ChatMessage message;
  final bool isMine;
  final VoidCallback onTap;
  final ValueChanged<ChatUser> onSenderTap;

  const _MessageBubble({
    required this.message,
    required this.isMine,
    required this.onTap,
    required this.onSenderTap,
  });

  @override
  Widget build(BuildContext context) {
    if (message.isDeleted) {
      return Align(
        alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: context.palette.bgSurface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: context.palette.borderHairline),
          ),
          child: Text(
            'Nachricht gelöscht',
            style: TextStyle(
                color: context.palette.textSecondary,
                fontStyle: FontStyle.italic,
                fontSize: 13),
          ),
        ),
      );
    }

    final senderName = message.sender?.effectiveName ?? 'Biker';
    final bubble = Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      constraints:
          BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.72),
      decoration: BoxDecoration(
        color: isMine
            ? context.palette.accentPrimary.withValues(alpha: 0.25)
            : context.palette.bgSurfaceRaised,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(16),
          topRight: const Radius.circular(16),
          bottomLeft: Radius.circular(isMine ? 16 : 4),
          bottomRight: Radius.circular(isMine ? 4 : 16),
        ),
        border: Border.all(color: context.palette.borderHairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isMine)
            GestureDetector(
              onTap: () {
                if (message.sender != null) onSenderTap(message.sender!);
              },
              child: Text(
                senderName,
                style: TextStyle(
                  // Akzent als SCHRIFT: im hellen Schema dunkler, sonst nur
                  // 3,39:1 auf der hellen Blase.
                  color: context.palette.accentText,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          // Route-Card (Abschnitt 19/20 der Gruppenrouten-Vorgabe):
          // attachment.type == 'route' rendert die Kartenansicht statt
          // reinen Text - "ROUTE ÖFFNEN" springt in den kollaborativen
          // Planer, wenn eine routeId mitkommt.
          if (message.attachment?['type'] == 'route')
            _RouteCard(attachment: message.attachment!)
          else
            Text(
              message.content,
              style: TextStyle(
                  color: context.palette.textPrimary, fontSize: 15, height: 1.3),
            ),
          const SizedBox(height: 2),
          Text(
            formatClock(message.createdAt),
            style: TextStyle(
                color: context.palette.textSecondaryStrong, fontSize: 10),
          ),
        ],
      ),
    );

    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: isMine
            ? Align(alignment: Alignment.centerRight, child: bubble)
            : Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  GestureDetector(
                    onTap: () {
                      if (message.sender != null) onSenderTap(message.sender!);
                    },
                    child: UserAvatar(
                      avatarUrl: message.sender?.avatarUrl,
                      name: senderName,
                      size: 14,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(child: bubble),
                ],
              ),
      ),
    );
  }
}
