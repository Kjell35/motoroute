import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../chat_providers.dart';
import '../data/chat_repository.dart';

/// Gruppe erstellen (Abschnitt 8): Name, Beschreibung, Kategorie.
/// Gruppenbild (Upload) ist Architektur-vorbereitet (imageUrl-Feld),
/// benötigt einen Storage-Bucket - TODO mit dem Storage-Feature.
class GroupCreateScreen extends ConsumerStatefulWidget {
  const GroupCreateScreen({super.key});

  @override
  ConsumerState<GroupCreateScreen> createState() => _GroupCreateScreenState();
}

class _GroupCreateScreenState extends ConsumerState<GroupCreateScreen> {
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  String? _category;
  bool _creating = false;

  static const _categories = ['Tour', 'Club', 'Regional', 'Freunde', 'Sonstiges'];

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final token = ref.read(chatSessionTokenProvider);
    final name = _nameController.text.trim();
    if (token == null || name.isEmpty || _creating) return;
    setState(() => _creating = true);
    try {
      final repo = ref.read(chatRepositoryProvider);
      final groupId = await repo.createGroup(
        token,
        name: name,
        description: _descriptionController.text.trim().isEmpty
            ? null
            : _descriptionController.text.trim(),
        category: _category,
      );
      if (!mounted) return;
      final group = await repo.group(token, groupId);
      if (!mounted) return;
      Navigator.of(context).pushReplacementNamed(
        '/chat/conversation',
        arguments: {
          'conversationId': group['conversation_id'] as String,
          'type': 'group',
          'group': group,
        },
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _creating = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Gruppe konnte nicht erstellt werden')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgBaseDark,
      appBar: AppBar(
        backgroundColor: AppColors.bgBaseDark,
        title: const Text('Gruppe erstellen'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          TextField(
            controller: _nameController,
            maxLength: 60,
            style: const TextStyle(color: AppColors.textPrimaryDark),
            decoration: InputDecoration(
              labelText: 'Gruppenname',
              labelStyle: const TextStyle(color: AppColors.textSecondaryDark),
              hintText: 'z. B. 🏍️ Alpen Tour 2026',
              hintStyle: const TextStyle(color: AppColors.textMutedDark),
              filled: true,
              fillColor: AppColors.bgSurfaceDark,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.borderHairlineDark),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _descriptionController,
            maxLength: 500,
            maxLines: 3,
            style: const TextStyle(color: AppColors.textPrimaryDark),
            decoration: InputDecoration(
              labelText: 'Beschreibung (optional)',
              labelStyle: const TextStyle(color: AppColors.textSecondaryDark),
              hintText: 'Worum gehts in der Gruppe?',
              hintStyle: const TextStyle(color: AppColors.textMutedDark),
              filled: true,
              fillColor: AppColors.bgSurfaceDark,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.borderHairlineDark),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: 8,
            children: _categories
                .map((c) => ChoiceChip(
                      label: Text(c),
                      selected: _category == c,
                      selectedColor: AppColors.accentPrimaryDark.withValues(alpha: 0.3),
                      labelStyle: TextStyle(
                        color: _category == c ? AppColors.textPrimaryDark : AppColors.textSecondaryDark,
                      ),
                      onSelected: (_) => setState(() => _category = c),
                    ))
                .toList(),
          ),
          const SizedBox(height: AppSpacing.xl),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.accentPrimaryDark,
              foregroundColor: AppColors.textPrimaryDark,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            onPressed: _creating ? null : _create,
            child: _creating
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Gruppe erstellen', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}
