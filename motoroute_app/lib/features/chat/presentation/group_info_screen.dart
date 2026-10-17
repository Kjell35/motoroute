import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../chat_providers.dart';
import '../data/chat_repository.dart';
import 'widgets/avatar.dart';
import 'widgets/user_profile_sheet.dart';

/// Gruppeninfo + Owner-Verwaltung (Abschnitt 14/15/33/35): Mitgliederliste
/// mit Rollen, Einladungscode-Verwaltung, Bearbeiten (nur Owner),
/// Verlassen inkl. Ownership-Transfer-Zwang.
class GroupInfoScreen extends ConsumerStatefulWidget {
  final String conversationId;
  final Map<String, dynamic>? group;

  const GroupInfoScreen({super.key, required this.conversationId, this.group});

  @override
  ConsumerState<GroupInfoScreen> createState() => _GroupInfoScreenState();
}

class _GroupInfoScreenState extends ConsumerState<GroupInfoScreen> {
  Map<String, dynamic>? _group;
  List<ConversationMember> _members = [];
  bool _loading = true;
  String? _error;
  String? _activeCode;

  @override
  void initState() {
    super.initState();
    _group = widget.group;
    _load();
  }

  Future<void> _load() async {
    final token = ref.read(chatSessionTokenProvider);
    if (token == null) {
      setState(() => _loading = false);
      return;
    }
    final repo = ref.read(chatRepositoryProvider);
    try {
      // Gruppen-ID aus conversation_id ableiten: Der Endpunkt /groups/:id
      // erwartet die Gruppen-UUID - aus dem Gruppenobjekt oder Nachladen.
      final groupId = (_group?['id'] ?? '') as String;
      final group = groupId.isEmpty ? _group : await repo.group(token, groupId);
      final members = await repo.listMembers(token, widget.conversationId);
      if (!mounted) return;
      String? code;
      if (group != null && group['id'] != null && (group['owner_id'] ?? '') == ref.read(chatMeProvider).value?.id) {
        try {
          final inv = await repo.activeInvitation(token, group['id'] as String);
          code = inv?['code'] as String?;
        } catch (_) {}
      }
      setState(() {
        _group = group ?? _group;
        _members = members;
        _activeCode = code;
        _loading = false;
        _error = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Gruppe konnte nicht geladen werden';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(chatMeProvider).value;
    final isOwner = _group != null && (_group!['owner_id'] ?? '') == me?.id;
    return Scaffold(
      backgroundColor: AppColors.bgBaseDark,
      appBar: AppBar(
        backgroundColor: AppColors.bgBaseDark,
        title: const Text('ℹ️ Gruppeninfo'),
        actions: [
          if (isOwner)
            IconButton(
              icon: const Icon(Icons.settings, color: AppColors.textSecondaryDark),
              tooltip: 'Gruppe bearbeiten',
              onPressed: _editGroup,
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.accentPrimaryDark))
          : _error != null
              ? Center(child: Text(_error!, style: const TextStyle(color: AppColors.textSecondaryDark)))
              : ListView(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  children: [
                    _header(),
                    const SizedBox(height: AppSpacing.lg),
                    if (isOwner) ..._ownerSection(),
                    const SizedBox(height: AppSpacing.lg),
                    _membersSection(isOwner),
                    const SizedBox(height: AppSpacing.xl),
                    _leaveSection(isOwner),
                  ],
                ),
    );
  }

  Widget _header() {
    final name = (_group?['name'] ?? 'Gruppe') as String;
    final description = _group?['description'] as String?;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.bgSurfaceDark,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borderHairlineDark),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 32,
            backgroundColor: AppColors.bgSurfaceRaisedDark,
            child: Text(
              name.isNotEmpty ? name.characters.first.toUpperCase() : 'G',
              style: const TextStyle(color: AppColors.accentPrimaryDark, fontSize: 22, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    style: const TextStyle(
                        color: AppColors.textPrimaryDark, fontSize: 20, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text('${_members.length} Mitglieder',
                    style: const TextStyle(color: AppColors.textSecondaryDark)),
                if (description != null && description.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(description,
                      style: const TextStyle(color: AppColors.textSecondaryDark, fontSize: 13)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------ Owner-Bereich

  List<Widget> _ownerSection() {
    return [
      const Text('👑 Owner-Bereich',
          style: TextStyle(color: AppColors.accentPrimaryDark, fontWeight: FontWeight.w700)),
      const SizedBox(height: AppSpacing.sm),
      Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: AppColors.bgSurfaceDark,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.borderHairlineDark),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Einladungscode',
                style: TextStyle(color: AppColors.textSecondaryDark, fontSize: 13)),
            const SizedBox(height: 6),
            SelectableText(
              _activeCode ?? 'Noch kein aktiver Code',
              style: const TextStyle(
                  color: AppColors.textPrimaryDark, fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: 2),
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('Neu erstellen'),
                    onPressed: _createCode,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.block, size: 18),
                    label: const Text('Deaktivieren'),
                    onPressed: _activeCode == null ? null : _deactivateCode,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ];
  }

  Future<void> _createCode() async {
    final token = ref.read(chatSessionTokenProvider);
    final groupId = _group?['id'] as String?;
    if (token == null || groupId == null) return;
    try {
      final code = await ref.read(chatRepositoryProvider).createInvitation(token, groupId);
      if (!mounted) return;
      setState(() => _activeCode = code);
      _showCopiedSnackBar('Neuer Code: $code');
    } catch (_) {
      _showCopiedSnackBar('Code konnte nicht erstellt werden');
    }
  }

  Future<void> _deactivateCode() async {
    final token = ref.read(chatSessionTokenProvider);
    final groupId = _group?['id'] as String?;
    if (token == null || groupId == null) return;
    try {
      await ref.read(chatRepositoryProvider).deactivateInvitation(token, groupId);
      if (!mounted) return;
      setState(() => _activeCode = null);
      _showCopiedSnackBar('Code deaktiviert');
    } catch (_) {
      _showCopiedSnackBar('Deaktivieren fehlgeschlagen');
    }
  }

  void _showCopiedSnackBar(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // --------------------------------------------------------------- Mitglieder

  Widget _membersSection(bool isOwner) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Mitglieder (${_members.length})',
            style: const TextStyle(
                color: AppColors.textPrimaryDark, fontSize: 16, fontWeight: FontWeight.w700)),
        const SizedBox(height: AppSpacing.sm),
        ..._members.map((member) {
          final user = member.user;
          final role = member.role;
          return ListTile(
            contentPadding: EdgeInsets.zero,
            leading: UserAvatar(avatarUrl: user.avatarUrl, name: user.effectiveName),
            title: Row(
              children: [
                Flexible(
                  child: Text(user.effectiveName,
                      style: const TextStyle(color: AppColors.textPrimaryDark)),
                ),
                if (role == 'owner') ...[
                  const SizedBox(width: 6),
                  const Text('👑', style: TextStyle(fontSize: 12)),
                ],
              ],
            ),
            subtitle: Text(role == 'owner' ? 'Owner' : 'Mitglied',
                style: const TextStyle(color: AppColors.textMutedDark, fontSize: 12)),
            trailing: isOwner && role != 'owner'
                ? PopupMenuButton<String>(
                    color: AppColors.bgSurfaceDark,
                    icon: const Icon(Icons.more_vert, color: AppColors.textSecondaryDark),
                    onSelected: (action) => _memberAction(action, user),
                    itemBuilder: (_) => [
                      const PopupMenuItem(value: 'remove', child: Text('Entfernen')),
                      const PopupMenuItem(value: 'transfer', child: Text('Owner übertragen')),
                    ],
                  )
                : null,
            onTap: () => showUserProfileSheet(context, ref, user),
          );
        }),
      ],
    );
  }

  Future<void> _memberAction(String action, ChatUser user) async {
    final token = ref.read(chatSessionTokenProvider);
    final groupId = _group?['id'] as String?;
    if (token == null || groupId == null) return;
    final repo = ref.read(chatRepositoryProvider);
    try {
      if (action == 'remove') {
        await repo.removeMember(token, groupId, user.id);
        _showCopiedSnackBar('${user.effectiveName} entfernt');
      } else if (action == 'transfer') {
        await repo.transferOwnership(token, groupId, user.id);
        _showCopiedSnackBar('Ownership an ${user.effectiveName} übertragen');
      }
      await _load();
    } catch (_) {
      _showCopiedSnackBar('Aktion fehlgeschlagen');
    }
  }

  // ------------------------------------------------------------- Verlassen

  Widget _leaveSection(bool isOwner) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 🏍️ Route planen (gemeinsame Tourplanung) - Abschnitt 1 der
        // Gruppenrouten-Vorgabe. Nur der Owner plant neue Routen;
        // Mitglieder sehen dieselbe Liste (lesend/navigierend).
        FilledButton.icon(
          icon: const Icon(Icons.route, color: AppColors.textPrimaryDark),
          label: const Text('ROUTE PLANEN', style: TextStyle(fontWeight: FontWeight.w700, letterSpacing: 1)),
          onPressed: () => Navigator.of(context).pushNamed(
            '/chat/group-route-list',
            arguments: {'groupId': _group?['id'] ?? ''},
          ),
          style: FilledButton.styleFrom(backgroundColor: AppColors.bgSurfaceRaisedDark),
        ),
        const SizedBox(height: AppSpacing.md),
        OutlinedButton.icon(
          icon: const Icon(Icons.logout, color: AppColors.statusDanger),
          label: const Text('Gruppe verlassen', style: TextStyle(color: AppColors.statusDanger)),
          onPressed: () => _confirmLeave(isOwner),
          style: OutlinedButton.styleFrom(side: const BorderSide(color: AppColors.statusDanger)),
        ),
        if (isOwner) ...[
          const SizedBox(height: AppSpacing.sm),
          OutlinedButton.icon(
            icon: const Icon(Icons.delete_forever, color: AppColors.statusDanger),
            label: const Text('Gruppe löschen', style: TextStyle(color: AppColors.statusDanger)),
            onPressed: _confirmDelete,
            style: OutlinedButton.styleFrom(side: const BorderSide(color: AppColors.statusDanger)),
          ),
        ],
      ],
    );
  }

  Future<void> _confirmLeave(bool isOwner) async {
    final token = ref.read(chatSessionTokenProvider);
    final groupId = _group?['id'] as String?;
    if (token == null || groupId == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.bgSurfaceDark,
        title: const Text('Gruppe verlassen?'),
        content: Text(isOwner
            ? 'Du bist Owner. Übertrage zuerst die Ownership oder lösche die Gruppe.'
            : 'Möchtest du diese Gruppe wirklich verlassen?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Abbrechen')),
          if (!isOwner)
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.statusDanger),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Verlassen'),
            ),
          if (isOwner)
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Trotzdem fortfahren'),
            ),
        ],
      ),
    );
    if (confirmed != true) return;

    final repo = ref.read(chatRepositoryProvider);
    try {
      final needsTransfer = await repo.leaveGroup(token, groupId);
      if (!mounted) return;
      if (needsTransfer) {
        _showCopiedSnackBar('Übertrage zuerst die Ownership (Mitgliederliste) oder lösche die Gruppe.');
      } else {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } catch (_) {
      _showCopiedSnackBar('Verlassen fehlgeschlagen');
    }
  }

  Future<void> _confirmDelete() async {
    final token = ref.read(chatSessionTokenProvider);
    final groupId = _group?['id'] as String?;
    if (token == null || groupId == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.bgSurfaceDark,
        title: const Text('Gruppe löschen?'),
        content: const Text('Alle Nachrichten und Mitglieder werden entfernt. Das kann nicht rückgängig gemacht werden.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Abbrechen')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.statusDanger),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Endgültig löschen'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(chatRepositoryProvider).deleteGroup(token, groupId);
      if (!mounted) return;
      Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (_) {
      _showCopiedSnackBar('Löschen fehlgeschlagen');
    }
  }

  Future<void> _editGroup() async {
    final token = ref.read(chatSessionTokenProvider);
    final groupId = _group?['id'] as String?;
    if (token == null || groupId == null) return;
    final nameController = TextEditingController(text: (_group?['name'] ?? '') as String);
    final descriptionController = TextEditingController(text: (_group?['description'] ?? '') as String);
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.bgSurfaceDark,
        title: const Text('Gruppe bearbeiten'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              maxLength: 60,
              decoration: const InputDecoration(labelText: 'Gruppenname'),
            ),
            TextField(
              controller: descriptionController,
              maxLength: 500,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'Beschreibung'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Abbrechen')),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Speichern'),
          ),
        ],
      ),
    );
    if (saved != true) return;
    try {
      await ref.read(chatRepositoryProvider).updateGroup(
            token,
            groupId,
            name: nameController.text.trim(),
            description: descriptionController.text.trim(),
          );
      await _load();
    } catch (_) {
      _showCopiedSnackBar('Speichern fehlgeschlagen');
    }
  }
}
