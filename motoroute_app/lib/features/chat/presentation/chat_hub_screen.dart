import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:motoroute_app/core/theme/app_colors.dart';
import 'package:motoroute_app/core/theme/app_spacing.dart';

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
  late final TabController _tabs = TabController(length: 3, vsync: this);

  @override
  void initState() {
    super.initState();
    // Nach dem ersten Frame laden (Provider-Zugriff im State).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(chatOverviewProvider.notifier).load();
    });
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(chatOverviewProvider);
    final token = ref.watch(chatSessionTokenProvider);

    if (token == null) {
      return const _NotSignedIn();
    }

    return Scaffold(
      backgroundColor: AppColors.bgBaseDark,
      appBar: AppBar(
        backgroundColor: AppColors.bgBaseDark,
        title: const Text('💬 Chat'),
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: AppColors.accentPrimaryDark,
          labelColor: AppColors.textPrimaryDark,
          unselectedLabelColor: AppColors.textSecondaryDark,
          tabs: const [
            Tab(text: '🌍 Öffentlich'),
            Tab(text: '🔒 Privat'),
            Tab(text: '👥 Gruppen'),
          ],
        ),
      ),
      floatingActionButton: _fabFor(context, state),
      body: state.isLoading && state.conversations.isEmpty
          ? const Center(child: CircularProgressIndicator(color: AppColors.accentPrimaryDark))
          : state.error != null && state.conversations.isEmpty
              ? _ErrorView(message: state.error!, onRetry: () => ref.read(chatOverviewProvider.notifier).load())
              : TabBarView(
                  controller: _tabs,
                  children: [
                    _PublicTab(connected: state.connected),
                    _ConversationListTab(
                      conversations: state.conversations.where((c) => c.type == ConversationType.private).toList(),
                      emptyText: 'Noch keine privaten Chats.\nSuche einen Biker und starte ein Gespräch!',
                      onNew: () => Navigator.of(context).pushNamed('/chat/new'),
                    ),
                    _ConversationListTab(
                      conversations: state.conversations.where((c) => c.type == ConversationType.group).toList(),
                      emptyText: 'Noch keine Gruppen.\nErstelle eine oder tritt per Einladungscode bei!',
                      onNew: () => _showGroupActions(context),
                    ),
                  ],
                ),
    );
  }

  Widget? _fabFor(BuildContext context, ChatOverviewState state) {
    final index = _tabs.index;
    if (index == 0) return null; // Öffentlicher Chat: kein "neu".
    return FloatingActionButton.extended(
      backgroundColor: AppColors.accentPrimaryDark,
      foregroundColor: AppColors.textPrimaryDark,
      onPressed: () => index == 1
          ? Navigator.of(context).pushNamed('/chat/new')
          : _showGroupActions(context),
      label: Text(index == 1 ? 'Neuer Chat' : 'Gruppen'),
      icon: Icon(index == 1 ? Icons.chat_bubble_outline : Icons.group_add),
    );
  }

  void _showGroupActions(BuildContext context) {
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
              leading: const Icon(Icons.group_add, color: AppColors.accentPrimaryDark),
              title: const Text('Gruppe erstellen', style: TextStyle(color: AppColors.textPrimaryDark)),
              onTap: () {
                Navigator.pop(context);
                Navigator.of(context).pushNamed('/chat/group-create');
              },
            ),
            ListTile(
              leading: const Icon(Icons.vpn_key_outlined, color: AppColors.accentSecondary),
              title: const Text('Gruppe beitreten (Einladungscode)', style: TextStyle(color: AppColors.textPrimaryDark)),
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
            color: AppColors.statusWarning.withValues(alpha: 0.15),
            child: const Text(
              'Keine Internetverbindung - Nachrichten werden geladen, sobald die Verbindung steht.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.statusWarning, fontSize: 12),
            ),
          ),
        Expanded(
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
  final VoidCallback onNew;

  const _ConversationListTab({
    required this.conversations,
    required this.emptyText,
    required this.onNew,
  });

  @override
  Widget build(BuildContext context) {
    if (conversations.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.chat_bubble_outline,
                  size: 48, color: AppColors.textMutedDark),
              const SizedBox(height: AppSpacing.md),
              Text(
                emptyText,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textSecondaryDark),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      color: AppColors.accentPrimaryDark,
      onRefresh: () async {}, // Liste kommt vom Controller (pull-to-refresh folgt).
      child: ListView.separated(
        itemCount: conversations.length,
        separatorBuilder: (_, __) =>
            const Divider(height: 1, color: AppColors.borderHairlineDark),
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
      contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.xs),
      leading: isGroup
          ? CircleAvatar(
              backgroundColor: AppColors.bgSurfaceRaisedDark,
              child: Text(
                title.isNotEmpty ? title.characters.first.toUpperCase() : 'G',
                style: const TextStyle(color: AppColors.accentPrimaryDark),
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
                color: hasUnread ? AppColors.textPrimaryDark : AppColors.textPrimaryDark,
                fontWeight: hasUnread ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
          if (last != null)
            Text(
              formatRelativeTime(last['created_at'] as String),
              style: TextStyle(
                fontSize: 12,
                color: hasUnread ? AppColors.accentPrimaryDark : AppColors.textMutedDark,
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
                color: hasUnread ? AppColors.textPrimaryDark : AppColors.textSecondaryDark,
                fontWeight: hasUnread ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
          // Ungelesen-Badge (Abschnitt 17: deutlich hervorgehoben).
          if (hasUnread)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.accentPrimaryDark,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '$unread',
                style: const TextStyle(
                  color: AppColors.textPrimaryDark,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
        ],
      ),
      onTap: () async {
        await Navigator.of(context).pushNamed('/chat/conversation',
            arguments: {'conversationId': c.id, 'type': c.type.name, 'group': c.group});
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
          const Icon(Icons.cloud_off, size: 48, color: AppColors.textMutedDark),
          const SizedBox(height: AppSpacing.md),
          Text(message, style: const TextStyle(color: AppColors.textSecondaryDark)),
          const SizedBox(height: AppSpacing.md),
          TextButton(onPressed: onRetry, child: const Text('Erneut versuchen')),
        ],
      ),
    );
  }
}

class _NotSignedIn extends StatelessWidget {
  const _NotSignedIn();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgBaseDark,
      appBar: AppBar(
        backgroundColor: AppColors.bgBaseDark,
        title: const Text('💬 Chat'),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.lock_outline, size: 56, color: AppColors.textMutedDark),
              const SizedBox(height: AppSpacing.lg),
              const Text(
                'Zum Chatten anmelden',
                style: TextStyle(
                    color: AppColors.textPrimaryDark,
                    fontSize: 18,
                    fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: AppSpacing.sm),
              const Text(
                'Der Chat ist exklusiv für MotoRoute-Fahrer.\nMelde dich mit deinem Konto an, um loszulegen.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSecondaryDark),
              ),
              const SizedBox(height: AppSpacing.lg),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: AppColors.accentPrimaryDark),
                onPressed: () => Navigator.of(context).pushNamed('/settings'),
                child: const Text('Zu den Einstellungen'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
