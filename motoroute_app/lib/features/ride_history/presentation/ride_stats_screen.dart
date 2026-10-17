import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:motoroute_app/core/i18n/i18n.dart';
import 'package:motoroute_app/core/state/app_providers.dart';
import 'package:motoroute_app/core/theme/app_colors.dart';
import 'package:motoroute_app/core/theme/app_spacing.dart';
import 'package:motoroute_app/core/theme/app_typography.dart';
import 'package:motoroute_app/core/utils/formatters.dart';
import 'package:motoroute_app/core/utils/geo.dart';
import 'package:motoroute_app/features/tour_diary/domain/tour_entities.dart';
import 'package:motoroute_app/features/tour_diary/tour_diary_providers.dart';

/// Statistik-Dashboard über ALLE Touren des Tour-Tagebuchs (Feature aus
/// der Konkurrenz-Analyse "Verfolge deine Fahrten und analysiere
/// Statistiken"):
///
/// - Hero-Kacheln: Top-Speed (aus der GPS-Spur abgeleitet), höchster
///   Punkt (max. elevationMeters), Gesamtdistanz, Gesamtzeit.
/// - Monats-Balkenchart der gefahrenen Kilometer (letzte 6 Monate).
///
/// Bewusst LOKAL gerechnet (Tour-Tagebuch), nicht aus der Server-
/// Historie: funktioniert offline und ohne Anmeldung; die Server-Daten
/// (ride_history) sind die geteilte Sicht, diese hier die persönliche.
class RideStatsScreen extends ConsumerStatefulWidget {
  const RideStatsScreen({super.key});

  @override
  ConsumerState<RideStatsScreen> createState() => _RideStatsScreenState();
}

class _RideStatsScreenState extends ConsumerState<RideStatsScreen> {
  @override
  Widget build(BuildContext context) {
    final i18n = ref.watch(i18nProvider);
    final tours = ref.watch(tourDiaryProvider).tours;

    return Scaffold(
      backgroundColor: AppColors.bgBaseDark,
      appBar: AppBar(
        backgroundColor: AppColors.bgBaseDark,
        title: Text(i18n.tr('stats.title'), style: AppTypography.title),
      ),
      body: tours.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.query_stats, size: 56, color: AppColors.textMutedDark),
                    const SizedBox(height: AppSpacing.md),
                    Text(i18n.tr('stats.empty'), style: AppTypography.body),
                  ],
                ),
              ),
            )
          : RefreshIndicator(
              onRefresh: () async =>
                  ref.read(tourDiaryProvider.notifier).load(),
              child: _RideStatsBody(tours: tours, i18n: i18n),
            ),
    );
  }
}

class _RideStatsBody extends ConsumerWidget {
  final List<RecordedTour> tours;
  final I18n i18n;

  const _RideStatsBody({required this.tours, required this.i18n});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unit = ref.watch(distanceUnitProvider);
    final totalMeters = tours.fold<double>(0, (s, t) => s + t.distanceMeters);
    final totalSeconds = tours.fold<double>(0, (s, t) => s + t.durationSeconds);
    final topSpeed = computeTopSpeedKmh(tours);
    final maxAltitude = computeMaxAltitudeMeters(tours);
    final months = computeMonthlyKm(tours, 6);

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        Row(
          children: [
            Expanded(
              child: _StatCard(
                label: i18n.tr('stats.topSpeed'),
                value: '${topSpeed.round()} ${i18n.tr('unit.kmh')}',
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: _StatCard(
                label: i18n.tr('stats.highestAltitude'),
                value: maxAltitude == null
                    ? '-'
                    : '${maxAltitude.round()} ${i18n.tr('unit.m')}',
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        Row(
          children: [
            Expanded(
              child: _StatCard(
                label: i18n.tr('stats.totalDistance'),
                value: formatDistanceMeters(totalMeters, unit: unit),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: _StatCard(
                label: i18n.tr('stats.totalTime'),
                value: formatDurationSeconds(totalSeconds),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xl),
        Text(i18n.tr('stats.monthlyKm'), style: AppTypography.title),
        const SizedBox(height: AppSpacing.md),
        _MonthlyBarChart(months: months, unit: unit, i18n: i18n),
        const SizedBox(height: AppSpacing.xl),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;

  const _StatCard({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.bgSurfaceDark,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borderHairlineDark),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label.toUpperCase(), style: AppTypography.caption),
          const SizedBox(height: AppSpacing.xs),
          Text(value, style: AppTypography.title),
        ],
      ),
    );
  }
}

class _MonthlyBarChart extends StatelessWidget {
  final List<({String label, double km})> months;
  final DistanceUnit unit;
  final I18n i18n;

  const _MonthlyBarChart({required this.months, required this.unit, required this.i18n});

  @override
  Widget build(BuildContext context) {
    if (months.every((m) => m.km <= 0)) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
        child: Text(
          i18n.tr('stats.noData'),
          style: AppTypography.body,
          textAlign: TextAlign.center,
        ),
      );
    }
    final maxKm = months.map((m) => m.km).reduce((a, b) => a > b ? a : b);
    final unitLabel = unit == DistanceUnit.miles
        ? i18n.tr('unit.mi')
        : i18n.tr('unit.km');
    final factor = unit == DistanceUnit.miles ? 0.621371 : 1.0;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.bgSurfaceDark,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borderHairlineDark),
      ),
      child: Column(
        children: [
          for (final m in months)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
              child: Row(
                children: [
                  SizedBox(
                    width: 36,
                    child: Text(m.label, style: AppTypography.caption),
                  ),
                  Expanded(
                    child: Stack(
                      alignment: Alignment.centerLeft,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: FractionallySizedBox(
                            widthFactor:
                                maxKm <= 0 ? 0 : (m.km / maxKm).clamp(0.02, 1.0),
                            child: Container(
                              height: 18,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    AppColors.accentPrimaryDark.withValues(alpha: 0.55),
                                    AppColors.accentPrimaryDark,
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(left: AppSpacing.sm),
                          child: Text(
                            '${(m.km * factor).round()} $unitLabel',
                            style: AppTypography.caption.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Reine Statistik-Funktionen (unit-testbar, kein Flutter-Bezug)
// ---------------------------------------------------------------------------

/// Höchste gefahrene Geschwindigkeit über alle GPS-Spuren (km/h).
/// Zwei aufeinanderfolgende Punkte mit dt ~ 0 werden ignoriert (GPS-
/// Jitter) und Ausreißer über 400 km/h verworfen.
double computeTopSpeedKmh(List<RecordedTour> tours) {
  var top = 0.0;
  for (final tour in tours) {
    final track = tour.track;
    for (var i = 1; i < track.length; i++) {
      final dt = track[i].secondsSinceStart - track[i - 1].secondsSinceStart;
      if (dt < 1.0) continue; // Jitter-Schutz
      final meters = haversineMeters(
        track[i - 1].lat, track[i - 1].lng, track[i].lat, track[i].lng,
      );
      final kmh = (meters / dt) * 3.6;
      if (kmh <= 400 && kmh > top) top = kmh;
    }
  }
  return top;
}

/// Höchster Punkt (Meter ü. NN) über alle Spuren - nur echte Werte.
double? computeMaxAltitudeMeters(List<RecordedTour> tours) {
  double? max;
  for (final tour in tours) {
    for (final p in tour.track) {
      final e = p.elevationMeters;
      if (e == null) continue;
      if (max == null || e > max) max = e;
    }
  }
  return max;
}

/// Kilometer pro Monat (letzte [count] Monate, ältester zuerst).
List<({String label, double km})> computeMonthlyKm(
  List<RecordedTour> tours,
  int count,
) {
  final now = DateTime.now();
  final buckets = <DateTime, double>{};
  for (var i = count - 1; i >= 0; i--) {
    final m = DateTime(now.year, now.month - i);
    buckets[m] = 0;
  }
  for (final tour in tours) {
    final key = DateTime(tour.startedAt.year, tour.startedAt.month);
    if (buckets.containsKey(key)) {
      buckets[key] = buckets[key]! + tour.distanceMeters;
    }
  }
  final monthNames = DateFormat('MMM').dateSymbols.STANDALONESHORTMONTHS;
  return buckets.entries.map((e) {
    final label = monthNames[e.key.month - 1];
    return (label: _capitalize(label), km: e.value / 1000);
  }).toList();
}

String _capitalize(String s) =>
    s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';
