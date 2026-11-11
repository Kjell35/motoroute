import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

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

  Future<void> _scanQr() async {
    final code = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: context.palette.bgSurface,
        title: const Text('Einladungs-QR scannen'),
        content: SizedBox(
          width: 320,
          height: 320,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: MobileScanner(
              onDetect: (capture) {
                for (final barcode in capture.barcodes) {
                  final inviteCode = _inviteCodeFromQr(barcode.rawValue);
                  if (inviteCode != null) {
                    Navigator.of(dialogContext).pop(inviteCode);
                    return;
                  }
                }
              },
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Abbrechen'),
          ),
        ],
      ),
    );
    if (!mounted || code == null) return;
    _codeController.text = code;
    await _lookup();
  }

  String? _inviteCodeFromQr(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final value = raw.trim();
    final uri = Uri.tryParse(value);
    if (uri != null && uri.scheme == 'motoroute' && uri.host == 'group-invite') {
      final code = uri.pathSegments.isEmpty ? '' : uri.pathSegments.last;
      return code.isEmpty ? null : code.toUpperCase();
    }
    if (RegExp(r'^[A-Za-z0-9-]{4,32}$').hasMatch(value)) {
      return value.toUpperCase();
    }
    return null;
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
      backgroundColor: context.palette.bgBase,
      appBar: AppBar(
        backgroundColor: context.palette.bgBase,
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
              style: TextStyle(
                  color: context.palette.textPrimary, fontSize: 18, letterSpacing: 2),
              decoration: InputDecoration(
                hintText: 'MOTO-7K4P92',
                hintStyle: TextStyle(color: context.palette.textSecondary),
                filled: true,
                fillColor: context.palette.bgSurface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: context.palette.borderHairline),
                ),
              ),
              onSubmitted: (_) => _lookup(),
            ),
            const SizedBox(height: AppSpacing.sm),
            OutlinedButton.icon(
              onPressed: _checking ? null : _scanQr,
              icon: const Icon(Icons.qr_code_scanner),
              label: const Text('Einladungs-QR scannen'),
            ),
            const SizedBox(height: AppSpacing.md),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: context.palette.bgSurfaceRaised),
              onPressed: _checking ? null : _lookup,
              child: _checking
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Code prüfen'),
            ),
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.md),
              Text(_error!, style: TextStyle(color: context.palette.statusDanger)),
            ],
            if (_preview != null) ...[
              const SizedBox(height: AppSpacing.xl),
              Container(
                padding: const EdgeInsets.all(AppSpacing.lg),
                decoration: BoxDecoration(
                  color: context.palette.bgSurface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: context.palette.borderHairline),
                ),
                child: Column(
                  children: [
                    Text(name ?? '',
                        style: TextStyle(
                            color: context.palette.textPrimary,
                            fontSize: 20,
                            fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text('$memberCount Mitglieder',
                        style: TextStyle(color: context.palette.textSecondary)),
                    const SizedBox(height: AppSpacing.lg),
                    FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: context.palette.accentPrimary,
                        foregroundColor: context.palette.textPrimary,
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
