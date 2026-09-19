import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../chat_providers.dart';
import '../data/chat_repository.dart';
import 'widgets/avatar.dart';

/// „Neuer Chat“ (Abschnitt 4): Benutzer suchen (Benutzername/Name),
/// antippen -> privater Chat wird erstellt/geöffnet (get_or_create).
class NewChatScreen extends ConsumerStatefulWidget {
  const NewChatScreen({super.key});

  @override
  ConsumerState<NewChatScreen> createState() => _NewChatScreenState();
}

class _NewChatScreenState extends ConsumerState<NewChatScreen> {
  final _searchController = TextEditingController();
  Timer? _debounce;
  bool _searching = false;
  String? _error;
  List<ChatUser> _results = [];

  ChatRepository get _repo => ref.read(chatRepositoryProvider);

  @override
  void dispose() {
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onChanged(String query) {
    _debounce?.cancel();
    if (query.trim().length < 2) {
      setState(() {
        _results = [];
        _error = null;
        _searching = false;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 350), () => _search(query.trim()));
  }

  Future<void> _search(String query) async {
    final token = ref.read(chatSessionTokenProvider);
    if (token == null) {
      setState(() => _error = 'Zum Suchen anmelden');
      return;
    }
    setState(() {
      _searching = true;
      _error = null;
    });
    try {
      final results = await _repo.searchUsers(token, query);
      if (!mounted) return;
      setState(() {
        _results = results;
        _searching = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Suche fehlgeschlagen - bitte Verbindung prüfen';
        _searching = false;
      });
    }
  }

  Future<void> _openChat(ChatUser user) async {
    final token = ref.read(chatSessionTokenProvider);
    if (token == null) return;
    try {
      final convId = await _repo.startPrivateChat(token, user.id);
      if (!mounted) return;
      Navigator.of(context).pushReplacementNamed(
        '/chat/conversation',
        arguments: {'conversationId': convId, 'type': 'private'},
      );
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString().contains('BLOCKED') || e.toString().contains('403')
          ? 'Chat mit diesem Benutzer nicht möglich (Blockierung)'
          : 'Chat konnte nicht erstellt werden';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgBaseDark,
      appBar: AppBar(
        backgroundColor: AppColors.bgBaseDark,
        title: const Text('Neuer Chat'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: TextField(
              controller: _searchController,
              autofocus: true,
              onChanged: _onChanged,
              style: const TextStyle(color: AppColors.textPrimaryDark),
              decoration: InputDecoration(
                hintText: 'Benutzername suchen …',
                hintStyle: const TextStyle(color: AppColors.textMutedDark),
                prefixIcon: const Icon(Icons.search, color: AppColors.textSecondaryDark),
                filled: true,
                fillColor: AppColors.bgSurfaceDark,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppColors.borderHairlineDark),
                ),
              ),
            ),
          ),
          if (_searching) const LinearProgressIndicator(color: AppColors.accentPrimaryDark),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Text(_error!, style: const TextStyle(color: AppColors.statusDanger)),
            ),
          Expanded(
            child: _results.isEmpty
                ? Center(
                    child: Text(
                      _searchController.text.trim().length < 2
                          ? 'Tippe mindestens 2 Zeichen, um Biker zu finden.'
                          : 'Keine Biker gefunden.',
                      style: const TextStyle(color: AppColors.textMutedDark),
                    ),
                  )
                : ListView.builder(
                    itemCount: _results.length,
                    itemBuilder: (context, i) {
                      final user = _results[i];
                      return ListTile(
                        leading: UserAvatar(avatarUrl: user.avatarUrl, name: user.effectiveName),
                        title: Text(user.effectiveName,
                            style: const TextStyle(color: AppColors.textPrimaryDark)),
                        subtitle: user.username != null
                            ? Text('@${user.username}',
                                style: const TextStyle(color: AppColors.textMutedDark))
                            : null,
                        trailing: const Icon(Icons.chat_bubble_outline,
                            color: AppColors.accentPrimaryDark, size: 20),
                        onTap: () => _openChat(user),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
