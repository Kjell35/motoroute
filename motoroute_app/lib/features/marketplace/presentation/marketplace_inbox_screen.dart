import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../marketplace_notifications.dart';
import '../marketplace_repository.dart';

/// Inbox für In-App-Benachrichtigungen (Favorit/Meldung/Review am eigenen
/// Angebot). Öffnet über das Glocken-Icon am Marktplatz.
class MarketplaceInboxScreen extends ConsumerStatefulWidget {
  const MarketplaceInboxScreen({super.key});

  @override
  ConsumerState<MarketplaceInboxScreen> createState() => _MarketplaceInboxScreenState();
}

class _MarketplaceInboxScreenState extends ConsumerState<MarketplaceInboxScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final token = ref.read(marketplaceTokenProvider);
      if (token != null) {
        ref.read(marketplaceNotificationsProvider.notifier).refresh(token);
        // Beim Öffnen als gelesen markieren (Badge verschwindet).
        ref.read(marketplaceNotificationsProvider.notifier).markAllRead();
      }
    });
  }

  String _typeLabel(String type) => switch (type) {
        'favorite' => '❤️ Angebot gemerkt',
        'report' => '🚩 Angebot gemeldet',
        'review' => '⭐ Neue Bewertung',
        _ => '🔔 Aktivität',
      };

  String _body(MpNotification n) {
    final who = n.actor ?? 'Jemand';
    final what = n.listingTitle ?? 'dein Angebot';
    return switch (n.type) {
      'favorite' => '$who hat \"$what\" gemerkt.',
      'report' => '$who hat \"$what\" gemeldet - Admins prüfen das.',
      'review' => '$who hat \"$what\" bewertet.',
      _ => n.body,
    };
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final notifications = ref.watch(marketplaceNotificationsProvider);

    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        backgroundColor: scheme.surface,
        title: const Text('🔔 Aktivität', style: TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: notifications.items.isEmpty
          ? Center(
              child: Text(
                'Noch keine Aktivität an deinen Angeboten.',
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: notifications.items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, i) {
                final n = notifications.items[i];
                return Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: n.readAt == null
                          ? AppColors.accentPrimaryDark.withValues(alpha: 0.5)
                          : scheme.outlineVariant,
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(_typeLabel(n.type),
                                style: const TextStyle(fontWeight: FontWeight.w700)),
                            const SizedBox(height: 4),
                            Text(_body(n), style: const TextStyle(fontSize: 13)),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}
