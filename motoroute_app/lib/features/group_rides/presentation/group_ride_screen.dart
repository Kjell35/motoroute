import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../chat/chat_providers.dart';
import '../../chat/presentation/widgets/avatar.dart';
import '../group_ride_providers.dart';
import '../group_ride_repository.dart';

/// 🏍️ Live-Gruppenfahrt (Abschnitt 18): Wer ist unterwegs? Wer hat
/// gestartet? Wer ist fertig? Die eigene Position wird NUR geteilt,
/// wenn der Nutzer den Schalter aktiviert (striktes OPT-IN).
class GroupRideScreen extends ConsumerStatefulWidget {
  final String routeId;
  const GroupRideScreen({super.key, required this.routeId});

  @override
  ConsumerState<GroupRideScreen> createState() => _GroupRideScreenState();
}

class _GroupRideScreenState extends ConsumerState<GroupRideScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(groupRideProvider(widget.routeId).notifier).load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(groupRideProvider(widget.routeId));
    final meId = ref.watch(chatMeProvider).value?.id;

    return Scaffold(
      backgroundColor: AppColors.bgBaseDark,
      appBar: AppBar(
        backgroundColor: AppColors.bgBaseDark,
        title: const Text('👥 Gruppenfahrt'),
      ),
      body: RefreshIndicator(
        color: AppColors.accentPrimaryDark,
        onRefresh: () => ref.read(groupRideProvider(widget.routeId).notifier).refresh(),
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            _sharingCard(state),
            const SizedBox(height: AppSpacing.lg),
            _section('🏍️ Unterwegs', state.onTheRoad, meId, empty: 'Noch ist niemand unterwegs.'),
            const SizedBox(height: AppSpacing.md),
            _section('⏳ Noch nicht gestartet', state.notStartedYet, meId,
                empty: 'Niemand hat die Freigabe aktiv.'),
            const SizedBox(height: AppSpacing.md),
            _section('✔️ Fertig', state.finishedRiders, meId, empty: 'Noch niemand am Ziel.'),
            if (state.error != null) ...[
              const SizedBox(height: AppSpacing.md),
              Text(state.error!, style: const TextStyle(color: AppColors.statusWarning, fontSize: 13)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _sharingCard(GroupRideState state) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.bgSurfaceDark,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: state.isSharing
              ? AppColors.accentPrimaryDark.withValues(alpha: 0.5)
              : AppColors.borderHairlineDark,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.share_location, color: AppColors.accentPrimaryDark),
              const SizedBox(width: AppSpacing.sm),
              const Expanded(
                child: Text('Meine Position teilen',
                    style: TextStyle(
                        color: AppColors.textPrimaryDark, fontWeight: FontWeight.w700)),
              ),
              Switch(
                value: state.isSharing,
                activeColor: AppColors.accentPrimaryDark,
                onChanged: (v) {
                  final controller = ref.read(groupRideProvider(widget.routeId).notifier);
                  v ? controller.enableSharing() : controller.disableSharing();
                },
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            state.isSharing
                ? 'Deine Position wird mit den Mitgliedern dieser Gruppe geteilt, während du fährst. Du kannst sie jederzeit abschalten.'
                : 'Aus. Aktivieren, um Gruppenmitgliedern während der Tour zu zeigen, wo du bist - und zu sehen, wer schon losgefahren ist.',
            style: const TextStyle(color: AppColors.textMutedDark, fontSize: 12, height: 1.4),
          ),
        ],
      ),
    );
  }

  Widget _section(String title, List<LiveRider> riders, String? meId, {required String empty}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$title (${riders.length})',
            style: const TextStyle(
                color: AppColors.textPrimaryDark, fontSize: 15, fontWeight: FontWeight.w700)),
        const SizedBox(height: AppSpacing.sm),
        if (riders.isEmpty)
          Text(empty, style: const TextStyle(color: AppColors.textMutedDark, fontSize: 13))
        else
          ...riders.map((r) => _riderTile(r, meId)),
      ],
    );
  }

  Widget _riderTile(LiveRider rider, String? meId) {
    final isMe = rider.userId == meId;
    final name = rider.user?.effectiveName ?? 'Fahrer';
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: UserAvatar(avatarUrl: rider.user?.avatarUrl, name: name),
      title: Row(
        children: [
          Flexible(
            child: Text(
              isMe ? '$name (du)' : name,
              style: const TextStyle(color: AppColors.textPrimaryDark),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (rider.finished) ...[
            const SizedBox(width: 6),
            const Text('✔️', style: TextStyle(fontSize: 12)),
          ],
        ],
      ),
      subtitle: Text(
        rider.finished
            ? 'Am Ziel'
            : rider.started
                ? 'Unterwegs · Update vor ${_minutesSince(rider.lastBeatAt)}'
                : 'Bereit · noch nicht gestartet',
        style: const TextStyle(color: AppColors.textMutedDark, fontSize: 12),
      ),
    );
  }

  String _minutesSince(String? iso) {
    if (iso == null) return '?';
    final t = DateTime.tryParse(iso);
    if (t == null) return '?';
    final diff = DateTime.now().difference(t);
    if (diff.inSeconds < 60) return 'gerade eben';
    if (diff.inMinutes < 60) return '${diff.inMinutes} Min.';
    return '${diff.inHours} Std.';
  }
}
