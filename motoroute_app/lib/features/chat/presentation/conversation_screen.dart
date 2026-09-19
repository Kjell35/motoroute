import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../chat_providers.dart';
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
  String? _error;
  String? _replyToId;
  String? _otherTypingUserId; // Abschnitt 19
  Timer? _typingStopTimer;

  ChatRepository get _repo => ref.read(chatRepositoryProvider);
  String? get _token => ref.read(chatSessionTokenProvider);

  @override
  void initState() {
    super.initState();
    _loadInitial();
    _scrollController.addListener(_onScroll);
    _wireRealtime();
    // Lesen markieren (Abschnitt 17) nach kurzem Verweilen.
    Timer(const Duration(seconds: 2), _markRead);
  }

  @override
  void dispose() {
    ref.read(chatRealtimeProvider).unsubscribe(widget.conversationId);
    _scrollController.dispose();
    _inputController.dispose();
    _composerFocus.dispose();
    _typingStopTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadInitial() async {
    final token = _token;
    if (token == null) {
      setState(() => _isLoading = false);
      return;
    }
    ref.read(chatRealtimeProvider).subscribe(widget.conversationId);
    try {
      final page = await _repo.messages(token, widget.conversationId);
      if (!mounted) return;
      setState(() {
        _messages
          ..clear()
          ..addAll(page.messages);
        _hasMore = page.hasMore;
        _isLoading = false;
        _error = null;
      });
      _jumpToBottom();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = 'Nachrichten konnten nicht geladen werden';
      });
    }
  }

  Future<void> _loadMore() async {
    if (_isLoadingMore || !_hasMore || _messages.isEmpty) return;
    final token = _token;
    if (token == null) return;
    setState(() => _isLoadingMore = true);
    try {
      final page = await _repo.messages(token, widget.conversationId,
          before: _messages.first.createdAt);
      if (!mounted) return;
      setState(() {
        _messages.insertAll(0, page.messages);
        _hasMore = page.hasMore;
        _isLoadingMore = false;
      });
    } catch (_) {
      if (mounted) setState(() => _isLoadingMore = false);
    }
  }

  void _onScroll() {
    // Lazy Loading: knapp über dem Listenanfang ältere Nachrichten holen.
    if (_scrollController.position.pixels < 200) _loadMore();
  }

  void _wireRealtime() {
    final realtime = ref.read(chatRealtimeProvider);
    realtime.messages.listen((msg) {
      if (!mounted || msg.conversationId != widget.conversationId) return;
      if (_messages.any((m) => m.id == msg.id)) return; // Dedupe (WS + Polling)
      setState(() {
        _messages.add(msg);
        _otherTypingUserId = null;
      });
      _jumpToBottom();
    });
    realtime.deletions.listen((messageId) {
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
    });
    realtime.typing.listen((t) {
      if (!mounted || t.userId == ref.read(chatMeProvider).value?.id) return;
      // Nur anzeigen, wenn in DIESEM Chat getippt wird (Abschnitt 19).
      setState(() => _otherTypingUserId = t.isTyping ? t.userId : null);
      _typingStopTimer?.cancel();
      if (t.isTyping) {
        _typingStopTimer = Timer(const Duration(seconds: 4), () {
          if (mounted) setState(() => _otherTypingUserId = null);
        });
      }
    });
    realtime.connection.listen((up) {
      if (mounted) setState(() => _connected = up);
    });
  }

  Future<void> _markRead() async {
    final token = _token;
    if (token == null) return;
    await ref.read(chatOverviewProvider.notifier).markRead(widget.conversationId);
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
      if (!mounted) return;
      // Optimistisch anzeigen; WS-Dedupe verhindert Doppelung.
      if (!_messages.any((m) => m.id == msg.id)) {
        setState(() => _messages.add(msg));
        _jumpToBottom();
      }
    } catch (e) {
      if (!mounted) return;
      _inputController.text = text; // Text zurück ins Feld (nichts verloren)
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Senden fehlgeschlagen: ${e.toString().split('(').first.trim()}')),
      );
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
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Löschen fehlgeschlagen')));
      }
    }
  }

  void _reportMessage(ChatMessage msg) {
    final token = _token;
    showReportSheet(
      context,
      title: 'Nachricht melden',
      onSubmit: (reason, details) async {
        if (token != null) await _repo.reportMessage(token, msg.id, reason, details: details);
      },
    );
  }

  void _openMessageActions(ChatMessage msg) {
    final isMine = msg.senderId == ref.read(chatMeProvider).value?.id;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.bgSurfaceDark,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.reply, color: AppColors.accentPrimaryDark),
              title: const Text('Antworten', style: TextStyle(color: AppColors.textPrimaryDark)),
              onTap: () {
                Navigator.pop(context);
                setState(() => _replyToId = msg.id);
                _composerFocus.requestFocus();
              },
            ),
            if (isMine)
              ListTile(
                leading: const Icon(Icons.delete_outline, color: AppColors.statusDanger),
                title: const Text('Nachricht löschen',
                    style: TextStyle(color: AppColors.textPrimaryDark)),
                subtitle: const Text('Wird für alle als „Nachricht gelöscht“ angezeigt',
                    style: TextStyle(color: AppColors.textMutedDark, fontSize: 12)),
                onTap: () {
                  Navigator.pop(context);
                  _deleteMessage(msg);
                },
              ),
            if (!isMine)
              ListTile(
                leading: const Icon(Icons.flag_outlined, color: AppColors.statusWarning),
                title: const Text('Nachricht melden',
                    style: TextStyle(color: AppColors.textPrimaryDark)),
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
            color: AppColors.statusWarning.withValues(alpha: 0.15),
            child: const Text(
              'Keine Internetverbindung.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.statusWarning, fontSize: 12),
            ),
          ),
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator(color: AppColors.accentPrimaryDark))
              : _error != null
                  ? Center(child: Text(_error!, style: const TextStyle(color: AppColors.textSecondaryDark)))
                  : _buildMessageList(me),
        ),
        if (_otherTypingUserId != null) _buildTypingIndicator(),
        _buildComposer(),
      ],
    );

    if (widget.embedded) return body;
    return Scaffold(
      backgroundColor: AppColors.bgBaseDark,
      appBar: AppBar(
        backgroundColor: AppColors.bgSurfaceDark,
        title: Row(
          children: [
            if (widget.type == ConversationType.group)
              CircleAvatar(
                radius: 16,
                backgroundColor: AppColors.bgSurfaceRaisedDark,
                child: Text(
                  widget.title.isNotEmpty ? widget.title.characters.first.toUpperCase() : 'G',
                  style: const TextStyle(color: AppColors.accentPrimaryDark, fontSize: 13),
                ),
              )
            else
              const Icon(Icons.lock_outline, size: 18, color: AppColors.textSecondaryDark),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: AppColors.textPrimaryDark, fontSize: 16)),
                  if (widget.subtitle != null)
                    Text(widget.subtitle!,
                        style: const TextStyle(color: AppColors.textMutedDark, fontSize: 12)),
                ],
              ),
            ),
            // Gruppeninfo (Abschnitt 33)
            if (widget.type == ConversationType.group)
              IconButton(
                icon: const Icon(Icons.info_outline, color: AppColors.textSecondaryDark),
                onPressed: () => Navigator.of(context).pushNamed(
                  '/chat/group-info',
                  arguments: {'group': widget.group, 'conversationId': widget.conversationId},
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
          style: const TextStyle(color: AppColors.textMutedDark),
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
                  child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
                )
              : TextButton(
                  onPressed: _loadMore,
                  child: const Text('Ältere Nachrichten laden',
                      style: TextStyle(color: AppColors.textSecondaryDark)),
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
          style: TextStyle(color: AppColors.textMutedDark, fontStyle: FontStyle.italic, fontSize: 12),
        ),
      ),
    );
  }

  Widget _buildComposer() {
    final disabled = _token == null;
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
        decoration: const BoxDecoration(
          color: AppColors.bgSurfaceDark,
          border: Border(top: BorderSide(color: AppColors.borderHairlineDark)),
        ),
        child: Row(
          children: [
            if (_replyToId != null)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Chip(
                  label: const Text('Antworten', style: TextStyle(fontSize: 11)),
                  backgroundColor: AppColors.bgSurfaceRaisedDark,
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
                style: const TextStyle(color: AppColors.textPrimaryDark),
                decoration: InputDecoration(
                  hintText: disabled ? 'Zum Chatten anmelden' : 'Nachricht schreiben ...',
                  hintStyle: const TextStyle(color: AppColors.textMutedDark),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: const BorderSide(color: AppColors.borderHairlineDark),
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            GestureDetector(
              onTap: _send,
              child: Container(
                width: 44,
                height: 44,
                decoration: const BoxDecoration(color: AppColors.accentPrimaryDark, shape: BoxShape.circle),
                child: _sending
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.textPrimaryDark),
                      )
                    : const Icon(Icons.send, color: AppColors.textPrimaryDark, size: 20),
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
        color: AppColors.bgSurfaceDark,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.accentPrimaryDark.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('🏍️ ${name.toUpperCase()}',
              style: const TextStyle(
                  color: AppColors.accentPrimaryDark, fontWeight: FontWeight.w800, letterSpacing: 0.5)),
          const SizedBox(height: 6),
          Text(
            [
              if (km != null) '${km.toStringAsFixed(0)} km',
              if (hours != null) '$hours:${minutes.toString().padLeft(2, '0')} h',
              if (score != null) '🌀 Kurven-Score $score',
            ].join(' · '),
            style: const TextStyle(color: AppColors.textPrimaryDark, fontSize: 13),
          ),
          if (routeId != null && routeId.isNotEmpty) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.accentPrimaryDark,
                  foregroundColor: AppColors.textPrimaryDark,
                ),
                icon: const Icon(Icons.route, size: 18),
                label: const Text('ROUTE ÖFFNEN',
                    style: TextStyle(fontWeight: FontWeight.w700, letterSpacing: 0.5)),
                onPressed: () => Navigator.of(context)
                    .pushNamed('/chat/group-route-planner', arguments: {'routeId': routeId}),
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
            color: AppColors.bgSurfaceDark,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.borderHairlineDark),
          ),
          child: Text(
            'Nachricht gelöscht',
            style: TextStyle(color: AppColors.textMutedDark, fontStyle: FontStyle.italic, fontSize: 13),
          ),
        ),
      );
    }

    final senderName = message.sender?.effectiveName ?? 'Biker';
    final bubble = Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.72),
      decoration: BoxDecoration(
        color: isMine ? AppColors.accentPrimaryDark.withValues(alpha: 0.25) : AppColors.bgSurfaceRaisedDark,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(16),
          topRight: const Radius.circular(16),
          bottomLeft: Radius.circular(isMine ? 16 : 4),
          bottomRight: Radius.circular(isMine ? 4 : 16),
        ),
        border: Border.all(color: AppColors.borderHairlineDark),
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
                style: const TextStyle(
                  color: AppColors.accentPrimaryDark,
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
              style: const TextStyle(color: AppColors.textPrimaryDark, fontSize: 15, height: 1.3),
            ),
          const SizedBox(height: 2),
          Text(
            formatClock(message.createdAt),
            style: const TextStyle(color: AppColors.textMutedDark, fontSize: 10),
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
