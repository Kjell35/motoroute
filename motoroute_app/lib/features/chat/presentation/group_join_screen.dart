import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../chat_providers.dart';
import '../data/chat_repository.dart';

/// Gruppe per Einladungscode beitreten (Abschnitt 11/34): Code eingeben,
/// Vorschau (Name, Mitgliederzahl), bestätigen.
class GroupJoinScreen extends ConsumerStatefulWidget {
  const GroupJoinScreen({super.key});

  @override
  ConsumerState<GroupJoinScreen> createState() => _GroupJoinScreenState();
}

class _GroupJoinScreenState extends ConsumerState<GroupJoinScreen> {
  final _codeController = TextEditingController();
  bool _checking = false;
  String? _error;
  Map<String, dynamic>? _preview;

  ChatRepository? _repo;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _lookup() async {
    final token = ref.read(chatSessionTokenProvider);
    final code = _codeController.text.trim().toUpperCase();
    if (token == null || code.isEmpty || _checking) return;
    _repo ??= ref.read(chatRepositoryProvider);
    setState(() {
      _checking = true;
      _error = null;
      _preview = null;
    });
    try {
      final preview = await _repo!.previewByCode(token, code);
      if (!mounted) return;
      setState(() {
        _preview = preview;
        _checking = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Code ungültig oder abgelaufen';
        _checking = false;
      });
    }
  }

  Future<void> _join() async {
    final token = ref.read(chatSessionTokenProvider);
    final code = _codeController.text.trim().toUpperCase();
    if (token == null || code.isEmpty || _preview == null) return;
    try {
      final convId = await _repo!.joinByCode(token, code);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Du bist der Gruppe ${_preview!['name']} beigetreten.')),
      );
      Navigator.of(context)
          .pushNamedAndRemoveUntil('/chat/conversation', (route) => false,
              arguments: {'conversationId': convId, 'type': 'group'});
    } catch (e) {
      if (!mounted) return;
      final blocked = e.toString().contains('BLOCKED');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(blocked ? 'Beitritt nicht möglich (Blockierung)' : 'Beitritt fehlgeschlagen')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = _preview?['name'] as String?;
    final memberCount = _preview?['memberCount'] as int? ?? 0;
    return Scaffold(
      backgroundColor: AppColors.bgBaseDark,
      appBar: AppBar(
        backgroundColor: AppColors.bgBaseDark,
        title: const Text('Gruppe beitreten'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _codeController,
              textCapitalization: TextCapitalization.characters,
              style: const TextStyle(
                  color: AppColors.textPrimaryDark, fontSize: 18, letterSpacing: 2),
              decoration: InputDecoration(
                hintText: 'MOTO-7K4P92',
                hintStyle: const TextStyle(color: AppColors.textMutedDark),
                filled: true,
                fillColor: AppColors.bgSurfaceDark,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppColors.borderHairlineDark),
                ),
              ),
              onSubmitted: (_) => _lookup(),
            ),
            const SizedBox(height: AppSpacing.md),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.bgSurfaceRaisedDark),
              onPressed: _checking ? null : _lookup,
              child: _checking
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Code prüfen'),
            ),
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.md),
              Text(_error!, style: const TextStyle(color: AppColors.statusDanger)),
            ],
            if (_preview != null) ...[
              const SizedBox(height: AppSpacing.xl),
              Container(
                padding: const EdgeInsets.all(AppSpacing.lg),
                decoration: BoxDecoration(
                  color: AppColors.bgSurfaceDark,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.borderHairlineDark),
                ),
                child: Column(
                  children: [
                    Text('🏍️ $name',
                        style: const TextStyle(
                            color: AppColors.textPrimaryDark,
                            fontSize: 20,
                            fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text('$memberCount Mitglieder',
                        style: const TextStyle(color: AppColors.textSecondaryDark)),
                    const SizedBox(height: AppSpacing.lg),
                    FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.accentPrimaryDark,
                        foregroundColor: AppColors.textPrimaryDark,
                        minimumSize: const Size.fromHeight(48),
                      ),
                      onPressed: _join,
                      child: const Text('GRUPPE BEITRETEN',
                          style: TextStyle(fontWeight: FontWeight.w700)),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
