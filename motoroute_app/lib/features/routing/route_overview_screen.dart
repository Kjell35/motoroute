import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:motoroute_app/core/state/app_providers.dart';
import 'package:motoroute_app/core/theme/app_colors.dart';
import 'package:motoroute_app/core/theme/app_spacing.dart';
import 'package:motoroute_app/core/theme/app_typography.dart';
import 'package:motoroute_app/core/utils/formatters.dart';

/// Screen 7: Routenübersicht - zeigt die tatsächlich berechnete Route
/// (Distanz/Zeit/ETA + Segmente), nicht mehr statische Platzhalter.
class RouteOverviewScreen extends ConsumerWidget {
  const RouteOverviewScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final route = ref.watch(activeRouteProvider);
    final unit = ref.watch(distanceUnitProvider);

    if (route == null) {
      return Scaffold(
        backgroundColor: AppColors.bgBaseDark,
        appBar: AppBar(backgroundColor: AppColors.bgBaseDark),
        body: const Center(child: Text('Keine Route berechnet')),
      );
    }

    final now = DateTime.now();

    return Scaffold(
      backgroundColor: AppColors.bgBaseDark,
      appBar: AppBar(
        backgroundColor: AppColors.bgBaseDark,
        title: Text('Routenübersicht', style: AppTypography.title),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '${route.waypoints.first.label ?? 'Start'} → ${route.waypoints.last.label ?? 'Ziel'}',
                  style: AppTypography.caption,
                ),
              ),
            ),
            Container(
              margin: const EdgeInsets.all(AppSpacing.lg),
              padding: const EdgeInsets.all(AppSpacing.lg),
              decoration: BoxDecoration(
                color: AppColors.bgSurfaceDark,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.borderHairlineDark),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: _SummaryItem(
                      icon: Icons.straighten,
                      label: 'Distanz',
                      value: formatDistanceMeters(route.distanceMeters, unit: unit),
                    ),
                  ),
                  Expanded(
                    child: _SummaryItem(
                      icon: Icons.access_time,
                      label: 'Fahrzeit',
                      value: formatDurationSeconds(route.durationSeconds),
                    ),
                  ),
                  Expanded(
                    child: _SummaryItem(
                      icon: Icons.flag,
                      label: 'ETA',
                      value: formatEta(now, route.durationSeconds),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                itemCount: route.segments.length,
                itemBuilder: (context, index) {
                  final segment = route.segments[index];
                  return ListTile(
                    dense: true,
                    leading: Text(
                      '${index + 1}',
                      style: AppTypography.caption.copyWith(color: AppColors.accentPrimaryDark),
                    ),
                    title: Text(segment.instruction, style: AppTypography.body),
                    trailing: Text(
                      formatDistanceMeters(segment.distanceMeters, unit: unit),
                      style: AppTypography.caption,
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 0),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: SizedBox(
                width: double.infinity,
                height: AppSpacing.touchTargetPlanning,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).pushNamed('/navigation'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accentPrimaryDark,
                    foregroundColor: AppColors.textPrimaryLight,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Navigation starten', style: TextStyle(fontWeight: FontWeight.w600)),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
          ],
        ),
      ),
    );
  }
}

class _SummaryItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _SummaryItem({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, color: AppColors.textSecondaryDark, size: 20),
        const SizedBox(height: AppSpacing.xs),
        Text(label, style: AppTypography.caption),
        Text(value, style: AppTypography.bodyStrong),
      ],
    );
  }
}
