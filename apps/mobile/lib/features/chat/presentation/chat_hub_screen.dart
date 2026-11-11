import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:motoroute_app/core/i18n/i18n.dart';
import 'package:motoroute_app/core/network/error_message.dart'
    show technicalCause;
import 'package:motoroute_app/core/network/error_reporter.dart';
import 'package:motoroute_app/core/theme/app_colors.dart';
import 'package:motoroute_app/core/theme/app_spacing.dart';
import 'package:motoroute_app/core/theme/app_theme.dart';
import 'package:motoroute_app/core/theme/app_typography.dart';

import 'package:motoroute_app/features/auth/auth_providers.dart';

import '../chat_providers.dart';
import '../data/chat_repository.dart';
import 'conversation_screen.dart';
import 'widgets/avatar.dart';
import 'widgets/chat_formatters.dart';

/// 💬 Chat-Bereich (Abschnitt 1): Hub mit drei Tabs -
/// 🌍 Öffentlicher Chat / 🔒 Privat / 👥 Gruppen.
class ChatHubScreen extends ConsumerStatefulWidget {
  const ChatHubScreen({super.key});

  @override
  ConsumerState<ChatHubScreen> createState() => _ChatHubScreenState();
}

class _ChatHubScreenState extends ConsumerState<ChatHubScreen>
    with SingleTickerProviderStateMixin {
  ProviderSubscription<String?>? _tokenSubscription;
  late final TabController _tabs = TabController(length: 3, vsync: this);

  @override
  void initState() {
    super.initState();
    _tokenSubscription = ref.listenManual<String?>(
      chatSessionTokenProvider,
      (previous, next) {
        if (next != null) {
          ref
              .read(chatOverviewProvider.notifier)
              .load()
              .catchError((Object e) =>
                  ErrorReporter.instance.report('chat.load', e));
        }
      },
    );
    _tabs.addListener(_onTabChanged);
    // Nach dem ersten Frame laden (Provider-Zugriff im State).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref
          .read(chatOverviewProvider.notifier)
          .load()
          .catchError((Object e) => ErrorReporter.instance.report('chat.load', e));
    });
  }

  void _onTabChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _tokenSubscription?.close();
    _tabs.removeListener(_onTabChanged);
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(chatOverviewProvider);
    final token = ref.watch(chatSessionTokenProvider);
    final auth = ref.watch(authControllerProvider);
    final i18n = ref.watch(i18nProvider);

    if (token == null) {
      return _NotSignedIn(
        signedIn: auth.isAuthenticated,
        i18n: i18n,
      );
    }

    return Scaffold(
      backgroundColor: context.palette.bgBase,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        systemOverlayStyle: AppTheme.overlayFor(context),
        title: Text(i18n.chatTab, style: AppTypography.title),
        actions: [
          // Admin: Meldungen prüfen - nur sichtbar mit Admin-Konto
          // (App-Anforderung: Admin-Konto = überall Admin).
          if (ref.watch(authControllerProvider).user?.isAdmin ?? false)
            IconButton(
              tooltip: 'Meldungen',
              icon: Icon(Icons.shield_outlined,
                  color: context.palette.textSecondary),
              onPressed: () => _showAdminReports(context),
            ),
        ],
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: context.palette.accentPrimary,
          labelColor: context.palette.textPrimary,
          unselectedLabelColor: context.palette.textSecondary,
          tabs: [
            Tab(text: '🌍 ${i18n.chatPublic}'),
            Tab(text: '🔒 ${i18n.chatPrivate}'),
            Tab(text: '👥 ${i18n.chatGroups}'),
          ],
        ),
      ),
      floatingActionButton: _fabFor(context, state),
      body: state.isLoading && state.conversations.isEmpty
          ? Center(
              child:
                  CircularProgressIndicator(color: context.palette.accentPrimary))
          : state.error != null && state.conversations.isEmpty
              ? _ErrorView(
                  message: state.error!,
                  onRetry: () => ref.read(chatOverviewProvider.notifier).load())
              : TabBarView(
                  controller: _tabs,
                  children: [
                    _PublicTab(connected: state.connected),
                    _ConversationListTab(
                      conversations: state.conversations
                          .where((c) => c.type == ConversationType.private)
                          .toList(),
                      emptyText:
                          'Noch keine privaten Chats.\nSuche einen Biker und starte ein Gespräch!',
                      actionLabel: 'Biker suchen',
                      onNew: () => Navigator.of(context).pushNamed('/chat/new'),
                      onRefresh: () =>
                          ref.read(chatOverviewProvider.notifier).load(),
                    ),
                    _ConversationListTab(
                      conversations: state.conversations
                          .where((c) => c.type == ConversationType.group)
                          .toList(),
                      emptyText:
                          'Noch keine Gruppen.\nErstelle eine oder tritt per Einladungscode bei!',
                      actionLabel: 'Gruppe erstellen oder beitreten',
                      onNew: () => _showGroupActions(context),
                      onRefresh: () =>
                          ref.read(chatOverviewProvider.notifier).load(),
                    ),
                  ],
                ),
    );
  }

  Widget? _fabFor(BuildContext context, ChatOverviewState state) {
    final index = _tabs.index;
    if (index == 0) return null; // Öffentlicher Chat: kein "neu".
    return FloatingActionButton.extended(
      backgroundColor: context.palette.accentPrimary,
      foregroundColor: context.palette.textPrimary,
      onPressed: () => index == 1
          ? Navigator.of(context).pushNamed('/chat/new')
          : _showGroupActions(context),
      label: Text(index == 1 ? 'Neuer Chat' : 'Gruppen'),
      icon: Icon(index == 1 ? Icons.chat_bubble_outline : Icons.group_add),
    );
  }

  /// Admin-Sheet: offene Nutzer-Meldungen einsehen und bearbeiten.
  Future<void> _showAdminReports(BuildContext context) async {
    final token = ref.read(chatSessionTokenProvider);
    if (token == null) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: context.palette.bgSurface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        builder: (_, scrollCtrl) => _AdminReportsSheet(
          token: token,
          scrollCtrl: scrollCtrl,
          loadReports: () =>
              ref.read(chatRepositoryProvider).adminReports(token),
          resolveReport: (id, st) => ref
              .read(chatRepositoryProvider)
              .adminResolveReport(token, id, st),
        ),
      ),
    );
  }

  void _showGroupActions(BuildContext context) {
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
              leading: Icon(Icons.group_add,
                  color: context.palette.accentPrimary),
              title: Text('Gruppe erstellen',
                  style: TextStyle(color: context.palette.textPrimary)),
              onTap: () {
                Navigator.pop(context);
                Navigator.of(context).pushNamed('/chat/group-create');
              },
            ),
            ListTile(
              leading: Icon(Icons.vpn_key_outlined,
                  color: context.palette.accentSecondary),
              title: Text('Gruppe beitreten (Einladungscode)',
                  style: TextStyle(color: context.palette.textPrimary)),
              onTap: () {
                Navigator.pop(context);
                Navigator.of(context).pushNamed('/chat/group-join');
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// Öffentlicher-Chat-Tab: lädt die Singleton-Konversation und zeigt sie
/// mit demselben ConversationScreen wie private Chats/Gruppen.
class _PublicTab extends ConsumerStatefulWidget {
  final bool connected;
  const _PublicTab({required this.connected});

  @override
  ConsumerState<_PublicTab> createState() => _PublicTabState();
}

class _PublicTabState extends ConsumerState<_PublicTab> {
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Offline-Banner (Abschnitt 37): bereitz geladene Nachrichten
        // bleiben sichtbar, nur der Hinweis erscheint.
        if (!widget.connected)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppSpacing.sm),
            color: context.palette.statusWarning.withValues(alpha: 0.15),
            child: Text(
              'Keine Internetverbindung - Nachrichten werden geladen, sobald die Verbindung steht.',
              textAlign: TextAlign.center,
              style: TextStyle(color: context.palette.statusWarning, fontSize: 12),
            ),
          ),
        const Expanded(
          child: ConversationScreen(
            conversationId: publicConversationId,
            title: '🌍 Öffentlicher Chat',
            subtitle: 'Alle MotoRoute-Fahrer',
            embedded: true,
          ),
        ),
      ],
    );
  }
}

class _ConversationListTab extends StatelessWidget {
  final List<ConversationSummary> conversations;
  final String emptyText;
  final String actionLabel;
  final VoidCallback onNew;
  final Future<void> Function() onRefresh;

  const _ConversationListTab({
    required this.conversations,
    required this.emptyText,
    required this.actionLabel,
    required this.onNew,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    if (conversations.isEmpty) {
      return RefreshIndicator(
        color: context.palette.accentPrimary,
        onRefresh: onRefresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(
              height: MediaQuery.sizeOf(context).height * 0.55,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.xl),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.chat_bubble_outline,
                          size: 48, color: context.palette.textSecondary),
                      const SizedBox(height: AppSpacing.md),
                      Text(
                        emptyText,
                        textAlign: TextAlign.center,
                        style:
                            TextStyle(color: context.palette.textSecondary),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      FilledButton.icon(
                        onPressed: onNew,
                        icon: const Icon(Icons.add),
                        label: Text(actionLabel),
                        style: FilledButton.styleFrom(
                          backgroundColor: context.palette.accentPrimary,
                          foregroundColor: context.palette.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      color: context.palette.accentPrimary,
      onRefresh: onRefresh,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: conversations.length,
        separatorBuilder: (_, __) =>
            Divider(height: 1, color: context.palette.borderHairline),
        itemBuilder: (context, i) {
          final c = conversations[i];
          return _ConversationTile(conversation: c);
        },
      ),
    );
  }
}

class _ConversationTile extends ConsumerWidget {
  final ConversationSummary conversation;
  const _ConversationTile({required this.conversation});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = conversation;
    final isGroup = c.type == ConversationType.group;
    final title = isGroup
        ? ((c.group?['name'] as String?) ?? 'Gruppe')
        : _otherPartyName(c);
    final last = c.lastMessage;
    final preview = last == null
        ? 'Noch keine Nachrichten'
        : ((last['deleted_at'] != null)
            ? 'Nachricht gelöscht'
            : (() {
                final content = (last['content'] ?? '') as String;
                if (content.isNotEmpty) return content;
                return last['attachment'] != null ? '📎 Anhang' : 'Nachricht';
              })());

    final unread = c.unreadCount;
    final hasUnread = unread > 0;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg, vertical: AppSpacing.xs),
      leading: isGroup
          ? CircleAvatar(
              backgroundColor: context.palette.bgSurfaceRaised,
              child: Text(
                title.isNotEmpty ? title.characters.first.toUpperCase() : 'G',
                style: TextStyle(color: context.palette.accentText),
              ),
            )
          : UserAvatar(avatarUrl: null, name: title, size: 24),
      title: Row(
        children: [
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: hasUnread
                    ? context.palette.textPrimary
                    : context.palette.textPrimary,
                fontWeight: hasUnread ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
          if (last != null)
            Text(
              formatRelativeTime(last['created_at'] as String),
              style: TextStyle(
                fontSize: 12,
                color: hasUnread
                    ? context.palette.accentPrimary
                    : context.palette.textSecondary,
              ),
            ),
        ],
      ),
      subtitle: Row(
        children: [
          Expanded(
            child: Text(
              preview,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: hasUnread
                    ? context.palette.textPrimary
                    : context.palette.textSecondary,
                fontWeight: hasUnread ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
          // Ungelesen-Badge (Abschnitt 17: deutlich hervorgehoben).
          if (hasUnread)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: context.palette.accentPrimary,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '$unread',
                style: TextStyle(
                  color: context.palette.textPrimary,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
        ],
      ),
      onTap: () async {
        await Navigator.of(context).pushNamed('/chat/conversation', arguments: {
          'conversationId': c.id,
          'type': c.type.name,
          'group': c.group
        });
        // Nach Rückkehr: gelesen markieren (Abschnitt 17).
        ref.read(chatOverviewProvider.notifier).markRead(c.id);
      },
    );
  }

  String _otherPartyName(ConversationSummary c) {
    final name = c.group?['name'];
    if (name is String && name.isNotEmpty) return name;
    return 'Chat';
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.cloud_off, size: 48, color: context.palette.stateIdle),
          const SizedBox(height: AppSpacing.md),
          Text(message,
              style: TextStyle(color: context.palette.textSecondary)),
          const SizedBox(height: AppSpacing.md),
          TextButton(onPressed: onRetry, child: const Text('Erneut versuchen')),
        ],
      ),
    );
  }
}

class _NotSignedIn extends StatelessWidget {
  const _NotSignedIn({required this.signedIn, required this.i18n});

  final bool signedIn;
  final I18n i18n;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.palette.bgBase,
      appBar: AppBar(
        backgroundColor: context.palette.bgBase,
        title: const Text('Chat'),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.lock_outline,
                  size: 56, color: context.palette.textSecondary),
              const SizedBox(height: AppSpacing.lg),
              Text(
                signedIn ? i18n.chatTab : i18n.chatLoginRequired,
                style: TextStyle(
                    color: context.palette.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                signedIn
                    ? 'Deine Sitzung wird mit dem Chat verbunden.'
                    : i18n.chatLoginRequiredSub,
                textAlign: TextAlign.center,
                style: TextStyle(color: context.palette.textSecondary),
              ),
              const SizedBox(height: AppSpacing.lg),
              if (signedIn)
                CircularProgressIndicator(
                    color: context.palette.accentPrimary)
              else
                FilledButton(
                  style: FilledButton.styleFrom(
                      backgroundColor: context.palette.accentPrimary),
                  onPressed: () => Navigator.of(context).pushNamed('/welcome'),
                  child: Text(i18n.login),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Admin: Liste offener Nutzer-Meldungen (Chat + Marktplatz-Nutzer) mit
/// Aktionen (In Prüfung / Erledigt / Verwerfen). Serverseitig geschützt -
/// ohne Admin-Rolle antwortet das Backend mit 403.
class _AdminReportsSheet extends StatefulWidget {
  final String token;
  final ScrollController scrollCtrl;
  final Future<List<Map<String, dynamic>>> Function() loadReports;
  final Future<void> Function(String, String) resolveReport;

  const _AdminReportsSheet({
    required this.token,
    required this.scrollCtrl,
    required this.loadReports,
    required this.resolveReport,
  });

  @override
  State<_AdminReportsSheet> createState() => _AdminReportsSheetState();
}

class _AdminReportsSheetState extends State<_AdminReportsSheet> {
  List<Map<String, dynamic>>? _reports;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final reports = await widget.loadReports();
      if (!mounted) return;
      setState(() {
        _reports = reports;
        _busy = false;
      });
    } catch (e) {
      ErrorReporter.instance.report('chat.admin', e);
      if (!mounted) return;
      setState(() {
        _error =
            'Meldungen konnten nicht geladen werden · ${technicalCause(e)}';
        _busy = false;
      });
    }
  }

  Future<void> _resolve(String reportId, String status) async {
    try {
      await widget.resolveReport(reportId, status);
      await _load();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Aktion fehlgeschlagen')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      controller: widget.scrollCtrl,
      padding: const EdgeInsets.all(16),
      children: [
        Row(children: [
          Icon(Icons.flag_outlined, size: 20, color: context.palette.textPrimary),
          const SizedBox(width: 8),
          Text(
            'Nutzer-Meldungen',
            style: TextStyle(
                color: context.palette.textPrimary,
                fontWeight: FontWeight.w700,
                fontSize: 18),
          ),
        ]),
        const SizedBox(height: 12),
        if (_busy)
          Center(
              child:
                  CircularProgressIndicator(color: context.palette.accentPrimary))
        else if (_error != null)
          Text(_error!, style: TextStyle(color: context.palette.statusDanger))
        else if (_reports == null || _reports!.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 32),
            child: Center(
              child: Text('Keine offenen Meldungen.',
                  style: TextStyle(color: context.palette.textSecondary)),
            ),
          )
        else
          for (final r in _reports!)
            _ReportTile(report: r, onResolve: _resolve),
      ],
    );
  }
}

class _ReportTile extends StatelessWidget {
  final Map<String, dynamic> report;
  final Future<void> Function(String, String) onResolve;

  const _ReportTile({required this.report, required this.onResolve});

  @override
  Widget build(BuildContext context) {
    final reported = report['reported'] as Map<String, dynamic>?;
    final who = (reported?['display_name'] ??
            reported?['username'] ??
            reported?['id'] ??
            '?')
        .toString();
    final reason = (report['reason'] ?? '?').toString();
    final details = report['details']?.toString();
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.palette.bgSurfaceRaised,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.palette.borderHairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(who,
              style: TextStyle(
                  color: context.palette.textPrimary,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text('Grund: $reason',
              style: TextStyle(
                  color: context.palette.textSecondary, fontSize: 13)),
          if (details != null && details.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(details,
                style: TextStyle(
                    color: context.palette.textSecondary, fontSize: 12)),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              for (final (label, status) in [
                ('Prüfung', 'reviewing'),
                ('Erledigt', 'resolved'),
                ('Verwerfen', 'dismissed')
              ])
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: context.palette.accentPrimary,
                      side:
                          BorderSide(color: context.palette.accentPrimary),
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed: () => onResolve(report['id'].toString(), status),
                    child: Text(label, style: const TextStyle(fontSize: 12)),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
