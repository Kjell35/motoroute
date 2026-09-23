import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../ride_history/presentation/profile_history_screen.dart';
import '../../chat_providers.dart';
import '../../data/chat_repository.dart';
import 'avatar.dart';
import 'report_sheet.dart';

/// Benutzer-Profilblatt (Abschnitt 3): Antippen eines Nutzers im Chat
/// zeigt Profil + Aktionen (PN, Blockieren, Melden). „Profil ansehen“
/// zeigt dasselbe Blatt - die Trennung in eine separate Profil-Seite
/// folgt mit dem Auth-Feature (TODO).
Future<void> showUserProfileSheet(BuildContext context, WidgetRef ref, ChatUser user) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.bgSurfaceDark,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _UserProfileSheet(user: user, ref: ref),
  );
}

class _UserProfileSheet extends StatelessWidget {
  final ChatUser user;
  final WidgetRef ref;

  const _UserProfileSheet({required this.user, required this.ref});

  @override
  Widget build(BuildContext context) {
    final repo = ref.read(chatRepositoryProvider);
    final token = ref.read(chatSessionTokenProvider);

    Future<void> requireToken(Future<void> Function(String) action) async {
      if (token == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Dafür musst du angemeldet sein.')),
        );
        return;
      }
      try {
        await action(token);
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Fehler: $e')),
          );
        }
      }
    }

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                UserAvatar(avatarUrl: user.avatarUrl, name: user.effectiveName, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user.effectiveName,
                        style: const TextStyle(
                            color: AppColors.textPrimaryDark,
                            fontSize: 18,
                            fontWeight: FontWeight.w700),
                      ),
                      if (user.username != null && user.username!.isNotEmpty)
                        Text('@${user.username}',
                            style: const TextStyle(color: AppColors.textSecondaryDark, fontSize: 13)),
                    ],
                  ),
                ),
              ],
            ),
            if (user.vehicleDesc != null && user.vehicleDesc!.isNotEmpty) ...[
              const SizedBox(height: 12),
              Row(children: [
                const Icon(Icons.two_wheeler, size: 16, color: AppColors.textSecondaryDark),
                const SizedBox(width: 6),
                Text(user.vehicleDesc!,
                    style: const TextStyle(color: AppColors.textSecondaryDark)),
              ]),
            ],
            if (user.bio != null && user.bio!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(user.bio!, style: const TextStyle(color: AppColors.textSecondaryDark)),
            ],
            const SizedBox(height: 20),
            // Fahrhistorie (ÖFFENTLICHes Profil des Nutzers - zeigt nur,
            // was er freigegeben hat; private Profile zeigen das als
            // Hinweis im Screen selbst).
            ListTile(
              leading: const Icon(Icons.route, color: AppColors.accentPrimaryDark),
              title: const Text('Fahrhistorie',
                  style: TextStyle(color: AppColors.textPrimaryDark)),
              subtitle: const Text('Touren & Orte (nur Freigegebenes)',
                  style: TextStyle(color: AppColors.textSecondaryDark, fontSize: 12)),
              onTap: () {
                Navigator.pop(context);
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => ProfileHistoryScreen(userId: user.id),
                  ),
                );
              },
            ),
            // Private Nachricht (Abschnitt 3/4): erstellt/findet den
            // 1:1-Chat und öffnet ihn.
            ListTile(
              leading: const Icon(Icons.chat, color: AppColors.accentPrimaryDark),
              title: const Text('Private Nachricht',
                  style: TextStyle(color: AppColors.textPrimaryDark)),
              onTap: () async {
                Navigator.pop(context);
                await requireToken((t) async {
                  final convId = await repo.startPrivateChat(t, user.id);
                  if (context.mounted) {
                    await Navigator.of(context).pushNamed(
                      '/chat/conversation',
                      arguments: {'conversationId': convId, 'type': 'private'},
                    );
                    ref.read(chatOverviewProvider.notifier).refresh();
                  }
                });
              },
            ),
            ListTile(
              leading: const Icon(Icons.block, color: AppColors.statusDanger),
              title: const Text('Blockieren',
                  style: TextStyle(color: AppColors.textPrimaryDark)),
              onTap: () {
                Navigator.pop(context);
                showDialog<void>(
                  context: context,
                  builder: (dialogContext) => AlertDialog(
                    backgroundColor: AppColors.bgSurfaceDark,
                    title: const Text('Benutzer blockieren?',
                        style: TextStyle(color: AppColors.textPrimaryDark)),
                    content: Text(
                      '${user.effectiveName} kann dir dann keine privaten Nachrichten mehr senden und dich nicht mehr kontaktieren.',
                      style: const TextStyle(color: AppColors.textSecondaryDark),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(dialogContext),
                        child: const Text('Abbrechen'),
                      ),
                      FilledButton(
                        style: FilledButton.styleFrom(backgroundColor: AppColors.statusDanger),
                        onPressed: () {
                          Navigator.pop(dialogContext);
                          requireToken((t) => repo.blockUser(t, user.id));
                        },
                        child: const Text('Blockieren'),
                      ),
                    ],
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.flag_outlined, color: AppColors.statusWarning),
              title: const Text('Melden',
                  style: TextStyle(color: AppColors.textPrimaryDark)),
              onTap: () {
                Navigator.pop(context);
                showReportSheet(
                  context,
                  title: '${user.effectiveName} melden',
                  onSubmit: (reason, details) async {
                    if (token != null) await repo.reportUser(token, user.id, reason, details: details);
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
