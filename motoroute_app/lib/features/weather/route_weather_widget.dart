import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:motoroute_app/core/theme/app_colors.dart';
import 'package:motoroute_app/core/theme/app_spacing.dart';
import 'package:motoroute_app/core/theme/app_typography.dart';
import 'package:motoroute_app/core/utils/formatters.dart';
import 'package:motoroute_app/features/weather/route_weather_providers.dart';

/// Dezent Normalfall, laut im Ernstfall - das Wetter-Widget des
/// Navigations-Screens:
/// - Unauffällig: eine Zeile, Icon + Temperatur + Kurztext.
/// - Unwetter: roter Alarm-Streifen mit der Fahrtrichtungs-Meldung des
///   Backends, tap öffnet das Schutz-POI-Sheet.
/// Abgeleitet aus Phase 3 B.10: während der Fahrt nie modal erzeugen,
/// keine Sound-Überraschungen - der Streifen ist sichtbar, aber der
/// Fahrer entscheidet, wann er hinschaut.
class RouteWeatherWidget extends ConsumerWidget {
  const RouteWeatherWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(routeWeatherControllerProvider);
    final report = state.report;

    // Feature aus (kein OPENWEATHER_API_KEY) oder nichts geladen:
    // gar nichts rendern - keine Leiste für nichts.
    if (report == null || !report.isEnabled) return const SizedBox.shrink();

    if (report.hasAlert) {
      return _StormAlertBar(
        message: report.alertMessage!,
        onTap: () => _showShelterSheet(context, report),
      );
    }

    final dest = report.destinationSegment;
    if (dest == null) return const SizedBox.shrink();

    return _QuietWeatherRow(
      icon: _iconForCondition(dest.conditionCode),
      tempText: '${dest.tempC.round()}°',
      detailText: _quietDetail(dest),
    );
  }

  static IconData _iconForCondition(int code) {
    if (code >= 200 && code < 300) return Icons.flash_on;
    if (code >= 500 && code < 600) return Icons.umbrella;
    if (code >= 600 && code < 700) return Icons.ac_unit;
    if (code >= 801 && code < 900) return Icons.cloud;
    return Icons.wb_sunny;
  }

  static String _quietDetail(RouteWeatherSegment dest) {
    if (dest.precipitationMmH >= 0.5) return 'leichter Regen am Ziel';
    if (dest.tempC <= 5) return 'kalt am Ziel';
    return 'gute Fahrt';
  }

  static void _showShelterSheet(BuildContext context, RouteWeatherReport report) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.bgSurfaceDark,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _ShelterSheet(
        message: report.alertMessage ?? 'Unwetter unterwegs',
        severity: report.alertSeverity,
        shelters: report.shelters,
      ),
    );
  }
}

class _StormAlertBar extends StatelessWidget {
  final String message;
  final VoidCallback onTap;

  const _StormAlertBar({required this.message, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.statusDanger.withValues(alpha: 0.85),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.sm,
          ),
          child: Row(
            children: [
              const Icon(Icons.warning_amber_rounded,
                  color: AppColors.textPrimaryDark, size: 20),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  message,
                  style: AppTypography.bodyStrong,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const Icon(Icons.chevron_right, color: AppColors.textPrimaryDark),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuietWeatherRow extends StatelessWidget {
  final IconData icon;
  final String tempText;
  final String detailText;

  const _QuietWeatherRow({
    required this.icon,
    required this.tempText,
    required this.detailText,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.xs,
      ),
      child: Row(
        children: [
          Icon(icon, color: AppColors.textSecondaryDark, size: 18),
          const SizedBox(width: AppSpacing.sm),
          Text(
            '$tempText · $detailText',
            style: AppTypography.caption,
          ),
        ],
      ),
    );
  }
}

class _ShelterSheet extends StatelessWidget {
  final String message;
  final StormSeverity severity;
  final List<ShelterPoi> shelters;

  const _ShelterSheet({
    required this.message,
    required this.severity,
    required this.shelters,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  color: severity == StormSeverity.danger
                      ? AppColors.statusDanger
                      : AppColors.statusWarning,
                  size: 22,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(child: Text(message, style: AppTypography.bodyStrong)),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            if (shelters.isEmpty)
              Text(
                'Keine Schutz-POIs in der Nähe des kritischen Abschnitts '
                'gefunden. Suche selbst nach Tankstellen oder Überdachungen '
                'auf der Karte.',
                style: AppTypography.body,
              )
            else
              ...shelters.map((s) => _ShelterTile(shelter: s)),
            const SizedBox(height: AppSpacing.md),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Verstanden'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ShelterTile extends StatelessWidget {
  final ShelterPoi shelter;

  const _ShelterTile({required this.shelter});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        children: [
          const Icon(Icons.night_shelter, color: AppColors.accentSecondary, size: 20),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(shelter.name, style: AppTypography.bodyStrong),
                Text(
                  '${shelter.categoryLabel} · '
                  '${formatDistanceMeters(shelter.distanceFromRouteM)} vom Abschnitt',
                  style: AppTypography.caption,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
