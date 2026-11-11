import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/error_reporter.dart';
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
  /// Bis zur ersten Server-Antwort zeigen wir "laedt" statt dreier
  /// "niemand"-Meldungen, die faelschlich nach leerem Ergebnis aussehen.
  bool _firstLoad = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        await ref.read(groupRideProvider(widget.routeId).notifier).load();
      } catch (e) {
        // load() legt Fehler selbst in den State; ein Wurf aus dem Callback
        // waere ein unbehandelter Fehler, den der Screen nie zu sehen bekommt.
        ErrorReporter.instance.report('group_ride.load', e);
      } finally {
        if (mounted) setState(() => _firstLoad = false);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(groupRideProvider(widget.routeId));
    final meId = ref.watch(chatMeProvider).value?.id;

    return Scaffold(
      backgroundColor: context.palette.bgBase,
      appBar: AppBar(
        backgroundColor: context.palette.bgBase,
        title: const Text('👥 Gruppenfahrt'),
      ),
      body: RefreshIndicator(
        color: context.palette.accentPrimary,
        onRefresh: () => ref.read(groupRideProvider(widget.routeId).notifier).refresh(),
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            _sharingCard(state),
            if (state.isStaleSharing) ...[
              const SizedBox(height: AppSpacing.md),
              _staleSharingBanner(),
            ],
            if (state.error != null) ...[
              const SizedBox(height: AppSpacing.md),
              _errorCard(state.error!),
            ],
            const SizedBox(height: AppSpacing.lg),
            if (_isLoading(state))
              _loadingState()
            else if (state.riders.isEmpty)
              _emptyState()
            else ...[
              _section('🏍️', 'Unterwegs', state.onTheRoad, meId,
                  empty: 'Noch ist niemand unterwegs.'),
              const SizedBox(height: AppSpacing.md),
              _section('⏳', 'Noch nicht gestartet', state.notStartedYet, meId,
                  empty: 'Niemand hat die Freigabe aktiv.'),
              const SizedBox(height: AppSpacing.md),
              _section('✔️', 'Fertig', state.finishedRiders, meId,
                  empty: 'Noch niemand am Ziel.'),
            ],
          ],
        ),
      ),
    );
  }

  /// Erststart oder manueller Refresh ohne Daten: Ladezustand.
  bool _isLoading(GroupRideState state) =>
      (_firstLoad || state.isLoading) && state.riders.isEmpty;

  Widget _loadingState() {
    return Semantics(
      liveRegion: true,
      label: 'Fahrer werden geladen',
      child: ExcludeSemantics(
        child: Row(
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: context.palette.accentPrimary),
            ),
            const SizedBox(width: AppSpacing.sm),
            Text('Fahrer werden geladen ...',
                style: TextStyle(
                    color: context.palette.textSecondary, fontSize: 13)),
          ],
        ),
      ),
    );
  }

  /// Kein Fehler, keine Fahrer: ein Hinweis statt drei leerer Abschnitte.
  Widget _emptyState() {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: context.palette.bgSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.palette.borderHairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Niemand teilt gerade',
              style: TextStyle(
                  color: context.palette.textPrimary, fontWeight: FontWeight.w700)),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Sobald ein Mitglied die Freigabe aktiviert, erscheint es hier - '
            'unterwegs, noch nicht gestartet oder am Ziel.',
            style: TextStyle(color: context.palette.textSecondary, fontSize: 12, height: 1.4),
          ),
        ],
      ),
    );
  }

  /// Fehler sichtbar direkt unter der Teilen-Karte, mit Wiederholung -
  /// vorher stand er als nackte Textzeile am Listenende.
  Widget _errorCard(String message) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: context.palette.statusWarning.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.palette.statusWarning.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            liveRegion: true,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.warning_amber_rounded,
                    size: 18, color: context.palette.statusWarning),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(message,
                      style: TextStyle(
                          color: context.palette.textPrimary,
                          fontSize: 12,
                          height: 1.4)),
                ),
              ],
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => ref
                  .read(groupRideProvider(widget.routeId).notifier)
                  .refresh(),
              child: const Text('Erneut versuchen'),
            ),
          ),
        ],
      ),
    );
  }

  /// Hinweis auf eine Freigabe aus einer früheren Sitzung: der Server kennt
  /// die Zeile noch, lokal läuft kein Stream. Ohne Hinweis sähe der Fahrer
  /// nur einen Schalter auf "Teilt" und wüsste nicht, dass nichts ankommt.
  Widget _staleSharingBanner() {
    final controller = ref.read(groupRideProvider(widget.routeId).notifier);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: context.palette.statusWarning.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.palette.statusWarning.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Freigabe aus einer früheren Sitzung',
              style: TextStyle(
                  color: context.palette.textPrimary, fontWeight: FontWeight.w700)),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Dein Eintrag liegt noch auf dem Server, überträgt aber keine Position '
            'mehr. Neu starten überträgt ab jetzt, Löschen entfernt den Eintrag.',
            style: TextStyle(color: context.palette.textSecondary, fontSize: 12, height: 1.4),
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              FilledButton(
                onPressed: controller.restartSharing,
                child: const Text('Neu starten'),
              ),
              const SizedBox(width: AppSpacing.sm),
              TextButton(
                onPressed: controller.disableSharing,
                child: const Text('Löschen'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _sharingCard(GroupRideState state) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: context.palette.bgSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: state.isSharing
              ? context.palette.accentPrimary.withValues(alpha: 0.5)
              : context.palette.borderHairline,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.share_location, color: context.palette.accentPrimary),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: ExcludeSemantics(
                  child: Text('Meine Position teilen',
                      style: TextStyle(
                          color: context.palette.textPrimary, fontWeight: FontWeight.w700)),
                ),
              ),
              // Ohne Label liest der Screenreader nur "Switch, an".
              MergeSemantics(
                child: Semantics(
                  label: 'Meine Position teilen',
                  child: Switch(
                    value: state.isSharing,
                    activeThumbColor: context.palette.accentPrimary,
                    onChanged: (v) {
                      final controller =
                          ref.read(groupRideProvider(widget.routeId).notifier);
                      v ? controller.enableSharing() : controller.disableSharing();
                    },
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            state.isSharing
                ? 'Deine Position wird mit den Mitgliedern dieser Gruppe geteilt, während du fährst. Du kannst sie jederzeit abschalten.'
                : 'Aus. Aktivieren, um Gruppenmitgliedern während der Tour zu zeigen, wo du bist - und zu sehen, wer schon losgefahren ist.',
            style: TextStyle(color: context.palette.textSecondary, fontSize: 12, height: 1.4),
          ),
        ],
      ),
    );
  }

  Widget _section(String emoji, String title, List<LiveRider> riders, String? meId,
      {required String empty}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          header: true,
          // Emoji wuerde als "Motorrad" vorgelesen - nur visuell behalten.
          label: '$title (${riders.length})',
          child: ExcludeSemantics(
            child: Text('$emoji $title (${riders.length})',
                style: TextStyle(
                    color: context.palette.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w700)),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        if (riders.isEmpty)
          Text(empty, style: TextStyle(color: context.palette.textSecondary, fontSize: 13))
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
      leading: ExcludeSemantics(
          child: UserAvatar(avatarUrl: rider.user?.avatarUrl, name: name)),
      title: Row(
        children: [
          Flexible(
            child: Text(
              isMe ? '$name (du)' : name,
              style: TextStyle(color: context.palette.textPrimary),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (rider.finished) ...[
            const SizedBox(width: 6),
            // "Am Ziel" steht schon im Untertitel.
            const ExcludeSemantics(
                child: Text('✔️', style: TextStyle(fontSize: 12))),
          ],
        ],
      ),
      subtitle: Text(
        rider.finished
            ? 'Am Ziel'
            : rider.started
                ? 'Unterwegs · Update vor ${_minutesSince(rider.lastBeatAt)}'
                : 'Bereit · noch nicht gestartet',
        style: TextStyle(color: context.palette.textSecondary, fontSize: 12),
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
