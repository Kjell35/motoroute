import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:motoroute_app/core/i18n/i18n.dart';
import 'package:motoroute_app/core/theme/app_colors.dart';
import 'package:motoroute_app/core/theme/app_spacing.dart';
import 'package:motoroute_app/core/theme/app_typography.dart';
import 'package:motoroute_app/core/utils/formatters.dart';
import 'dart:typed_data';

import 'package:share_plus/share_plus.dart';

import '../data/gpx_service.dart';
import '../domain/tour_entities.dart';
import '../tour_diary_providers.dart';
import 'track_thumbnail.dart';

/// Tour-Tagebuch (Touren-Tab): vergangene Fahrten als Liste mit
/// Statistiken + Miniaturkarte der Spur. Jede Tour lässt sich als
/// GPX teilen (Calimoto/Kurviger/OsmAnd-kompatibel) oder löschen.
class TourDiaryScreen extends ConsumerStatefulWidget {
  const TourDiaryScreen({super.key});

  @override
  ConsumerState<TourDiaryScreen> createState() => _TourDiaryScreenState();
}

class _TourDiaryScreenState extends ConsumerState<TourDiaryScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(tourDiaryProvider.notifier).load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(tourDiaryProvider);
    final i18n = ref.watch(i18nProvider);

    return Scaffold(
      backgroundColor: AppColors.bgBaseDark,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(i18n.toursTab, style: AppTypography.title),
      ),
      body: SafeArea(
        child: state.isLoading
            ? const Center(child: CircularProgressIndicator(color: AppColors.accentPrimaryDark))
            : state.error != null
                ? _ErrorView(message: state.error!, onRetry: () => ref.read(tourDiaryProvider.notifier).load())
                : state.tours.isEmpty
                    ? _EmptyView(i18n: i18n)
                    : _TourList(tours: state.tours),
      ),
    );
  }
}

class _EmptyView extends ConsumerWidget {
  final I18n i18n;
  const _EmptyView({required this.i18n});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.route_outlined, size: 64, color: AppColors.textMutedDark),
            const SizedBox(height: AppSpacing.lg),
            Text(
              i18n.tr('tour.empty.title'),
              style: AppTypography.title,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              i18n.tr('tour.empty.sub'),
              style: AppTypography.body.copyWith(color: AppColors.textSecondaryDark),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.lg),
            OutlinedButton.icon(
              onPressed: () => Navigator.of(context).pushNamed('/tour-import'),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: AppColors.accentPrimaryDark),
                foregroundColor: AppColors.accentPrimaryDark,
              ),
              icon: const Icon(Icons.upload_file),
              label: Text(i18n.tr('tour.import.title')),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorView extends ConsumerWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: AppColors.statusDanger),
            const SizedBox(height: AppSpacing.md),
            Text(message, style: AppTypography.caption, textAlign: TextAlign.center),
            const SizedBox(height: AppSpacing.lg),
            OutlinedButton(onPressed: onRetry, child: Text(ref.watch(i18nProvider).tr('common.retry'))),
          ],
        ),
      ),
    );
  }
}

class _TourList extends ConsumerWidget {
  final List<RecordedTour> tours;
  const _TourList({required this.tours});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final i18n = ref.watch(i18nProvider);
    final summary = summarizeTours(tours);

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md),
      children: [
        // Summen-Kopf: die eigene Fahr-Bilanz auf einen Blick.
        Container(
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: BoxDecoration(
            color: AppColors.bgSurfaceDark,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.borderHairlineDark),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.25),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            children: [
              _SummaryCell(value: summary.count.toString(), label: i18n.tr('tour.summary.tours')),
              _SummaryCell(value: summary.totalKm.toStringAsFixed(0), label: i18n.tr('tour.summary.km')),
              _SummaryCell(
                  value: summary.totalHours < 10
                      ? summary.totalHours.toStringAsFixed(1)
                      : summary.totalHours.toStringAsFixed(0),
                  label: i18n.tr('tour.summary.hours')),
              _SummaryCell(
                  value: summary.totalElevationGain.toStringAsFixed(0),
                  label: i18n.tr('tour.summary.elevation')),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        for (final tour in tours)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: _TourCard(tour: tour),
          ),
      ],
    );
  }
}

class _SummaryCell extends StatelessWidget {
  final String value;
  final String label;
  const _SummaryCell({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(value, style: AppTypography.title.copyWith(color: AppColors.accentPrimaryDark)),
          const SizedBox(height: 2),
          Text(label, style: AppTypography.caption, textAlign: TextAlign.center),
        ],
      ),
    );
  }
}

class _TourCard extends ConsumerWidget {
  final RecordedTour tour;
  const _TourCard({required this.tour});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final i18n = ref.watch(i18nProvider);
    return Container(
      decoration: BoxDecoration(
        color: AppColors.bgSurfaceDark,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borderHairlineDark),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => Navigator.of(context).pushNamed('/tour-detail', arguments: tour.id),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Row(
              children: [
                SizedBox(
                  width: 96,
                  height: 96,
                  child: TrackThumbnail(track: tour.track),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tour.title,
                        style: AppTypography.bodyStrong,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _formatDate(tour.startedAt, i18n),
                        style: AppTypography.caption,
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Wrap(
                        spacing: AppSpacing.md,
                        runSpacing: 4,
                        children: [
                          _Stat(
                              icon: Icons.social_distance,
                              text: formatDistanceMeters(tour.distanceMeters)),
                          _Stat(
                              icon: Icons.schedule,
                              text: formatDurationSeconds(tour.durationSeconds)),
                          if (tour.elevationGainMeters >= 10)
                            _Stat(
                                icon: Icons.terrain,
                                text: '↗ ${tour.elevationGainMeters.toStringAsFixed(0)} m'),
                        ],
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: AppColors.textMutedDark),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime d, I18n i18n) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(d.day)}.${two(d.month)}.${d.year} · ${two(d.hour)}:${two(d.minute)}';
  }
}

class _Stat extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Stat({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: AppColors.textMutedDark),
        const SizedBox(width: 4),
        Text(text, style: AppTypography.caption),
      ],
    );
  }
}

/// Detail-Screen einer Tour: große Karte, alle Statistiken, GPX-Export.
class TourDetailScreen extends ConsumerWidget {
  final int tourId;
  const TourDetailScreen({super.key, required this.tourId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tours = ref.watch(tourDiaryProvider).tours;
    final i18n = ref.watch(i18nProvider);
    final tour = tours.where((t) => t.id == tourId).firstOrNull;

    if (tour == null) {
      return Scaffold(
        backgroundColor: AppColors.bgBaseDark,
        appBar: AppBar(backgroundColor: AppColors.bgBaseDark),
        body: const Center(child: CircularProgressIndicator(color: AppColors.accentPrimaryDark)),
      );
    }

    String two(int v) => v.toString().padLeft(2, '0');
    final dateText =
        '${two(tour.startedAt.day)}.${two(tour.startedAt.month)}.${tour.startedAt.year} · '
        '${two(tour.startedAt.hour)}:${two(tour.startedAt.minute)}';

    return Scaffold(
      backgroundColor: AppColors.bgBaseDark,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(tour.title, style: AppTypography.title),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline, color: AppColors.statusDanger),
            tooltip: i18n.tr('tour.delete'),
            onPressed: () async {
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (dialogContext) => AlertDialog(
                  backgroundColor: AppColors.bgSurfaceDark,
                  title: Text(i18n.tr('tour.delete'), style: AppTypography.title),
                  content: Text(i18n.tr('tour.deleteConfirm'), style: AppTypography.caption),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(dialogContext).pop(false),
                      child: Text(i18n.cancel),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.of(dialogContext).pop(true),
                      style: FilledButton.styleFrom(backgroundColor: AppColors.statusDanger),
                      child: Text(i18n.tr('tour.delete')),
                    ),
                  ],
                ),
              );
              if (confirmed == true && tour.id != null) {
                await ref.read(tourDiaryProvider.notifier).deleteTour(tour.id!);
                if (context.mounted) Navigator.of(context).pop();
              }
            },
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            // Große Spur-Karte (statisch gezeichnet, keine Tile-Abhängigkeit
            // - das Tagebuch funktioniert auch offline).
            SizedBox(
              height: 220,
              child: TrackThumbnail(track: tour.track, large: true),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(dateText, style: AppTypography.caption),
            const SizedBox(height: AppSpacing.lg),
            Row(
              children: [
                _DetailCell(
                    label: i18n.tr('route.distance'),
                    value: formatDistanceMeters(tour.distanceMeters)),
                _DetailCell(
                    label: i18n.tr('route.duration'),
                    value: formatDurationSeconds(tour.durationSeconds)),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                _DetailCell(
                    label: i18n.tr('tour.stats.elevation'),
                    value: '${tour.elevationGainMeters.toStringAsFixed(0)} m'),
                _DetailCell(
                    label: i18n.tr('tour.stats.avg'),
                    value: '${tour.avgSpeedKmh.toStringAsFixed(1)} km/h'),
              ],
            ),
            if (tour.pois.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.lg),
              Text(i18n.tr('tour.pois'), style: AppTypography.bodyStrong),
              const SizedBox(height: AppSpacing.sm),
              for (final poi in tour.pois)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                  child: Row(
                    children: [
                      const Icon(Icons.location_on_outlined,
                          size: 16, color: AppColors.accentPrimaryDark),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(child: Text(poi.label, style: AppTypography.body)),
                    ],
                  ),
                ),
            ],
            const SizedBox(height: AppSpacing.xl),
            SizedBox(
              width: double.infinity,
              height: AppSpacing.touchTargetPlanning,
              child: FilledButton.icon(
                onPressed: () => _exportGpx(context, ref, tour),
                style: FilledButton.styleFrom(backgroundColor: AppColors.accentPrimaryDark),
                icon: const Icon(Icons.ios_share),
                label: Text(i18n.tr('tour.export')),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// GPX erzeugen und über den System-Share-Sheet teilen (Speichern in
  /// Dateien/Cloud/WhatsApp - was immer der Nutzer will).
  Future<void> _exportGpx(BuildContext context, WidgetRef ref, RecordedTour tour) async {
    try {
      final gpx = GpxGenerator().generate(tour);
      final safeName = tour.title.replaceAll(RegExp(r'[^\w\- ]'), '').trim();
      final fileName = '${safeName.isEmpty ? 'Tour' : safeName}.gpx';
      await SharePlus.instance.share(
        ShareParams(
          text: 'MotoRoute - ${tour.title}',
          files: [
            XFile.fromData(
              Uint8List.fromList(gpx.codeUnits),
              mimeType: 'application/gpx+xml',
              name: fileName,
            ),
          ],
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ref.read(i18nProvider).tr('tour.exportFailed'))),
      );
    }
  }
}

class _DetailCell extends StatelessWidget {
  final String label;
  final String value;
  const _DetailCell({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        margin: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          color: AppColors.bgSurfaceDark,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.borderHairlineDark),
        ),
        child: Column(
          children: [
            Text(value, style: AppTypography.title.copyWith(fontSize: 18)),
            const SizedBox(height: 2),
            Text(label, style: AppTypography.caption),
          ],
        ),
      ),
    );
  }
}
