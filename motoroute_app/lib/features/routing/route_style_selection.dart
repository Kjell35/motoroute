import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:motoroute_app/core/constants/route_enums.dart';
import 'package:motoroute_app/core/state/app_providers.dart';
import 'package:motoroute_app/features/routing/domain/route_entities.dart';
import 'package:motoroute_app/core/theme/app_colors.dart';
import 'package:motoroute_app/core/theme/app_spacing.dart';
import 'package:motoroute_app/core/theme/app_typography.dart';
import 'package:motoroute_app/features/routing/routing_flow.dart';

/// Screen 6: Routenauswahl - Fahrstil-Kacheln mit echter Backend-
/// Berechnung beim Tap. While-isCalculating zeigen ALLE Kacheln einen
/// Spinner; Fehler erscheinen als SnackBar ohne den Flow zu töten.
class RouteStyleSelectionScreen extends ConsumerStatefulWidget {
  final Waypoint start;
  final Waypoint destination;

  const RouteStyleSelectionScreen({
    super.key,
    required this.start,
    required this.destination,
  });

  @override
  ConsumerState<RouteStyleSelectionScreen> createState() => _RouteStyleSelectionScreenState();
}

class _RouteStyleSelectionScreenState extends ConsumerState<RouteStyleSelectionScreen> {
  final Set<AvoidOption> _avoid = {};

  static final _styles = [
    (RouteStyle.fast, Icons.speed, 'Schnell', 'Kürzeste Zeit'),
    (RouteStyle.curvy, Icons.route, 'Kurvig', 'Schöne Straßen'),
    (RouteStyle.extraCurvy, Icons.alt_route, 'Extra kurvig', 'Abenteuer pur'),
    (RouteStyle.fastAndCurvy, Icons.tune, 'Schnell & kurvig', 'Ausgewogen'),
    (RouteStyle.unpaved, Icons.terrain, 'Unbefestigt', 'Schotter & Natur'),
  ];

  Future<void> _selectStyle(RouteStyle style) async {
    final controller = ref.read(routingFlowProvider.notifier);
    final route = await controller.calculate(
      waypoints: [widget.start, widget.destination],
      preference: RoutePreference(style: style, vehicleType: ref.read(vehicleTypeProvider), avoid: _avoid),
    );

    if (!mounted) return;
    if (route == null) {
      final error = ref.read(routingFlowProvider).error;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error ?? 'Routenberechnung fehlgeschlagen')),
      );
      return;
    }

    ref.read(activeRouteProvider.notifier).state = route;
    Navigator.of(context).pushReplacementNamed('/route-overview');
  }

  @override
  Widget build(BuildContext context) {
    final flow = ref.watch(routingFlowProvider);

    return Scaffold(
      backgroundColor: AppColors.bgBaseDark,
      appBar: AppBar(
        backgroundColor: AppColors.bgBaseDark,
        title: Text('Fahrstil wählen', style: AppTypography.title),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '${widget.start.label ?? 'Start'} → ${widget.destination.label ?? 'Ziel'}',
                  style: AppTypography.caption,
                ),
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                itemCount: _styles.length,
                itemBuilder: (context, index) {
                  final (style, icon, title, description) = _styles[index];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.md),
                    child: _buildStyleCard(style, icon, title, description, flow.isCalculating),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Vermeiden', style: AppTypography.caption),
                  const SizedBox(height: AppSpacing.sm),
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: [
                      for (final option in AvoidOption.values)
                        FilterChip(
                          selected: _avoid.contains(option),
                          label: Text(
                            switch (option) {
                              AvoidOption.highway => 'Autobahn',
                              AvoidOption.ferry => 'Fähre',
                              AvoidOption.toll => 'Maut',
                            },
                            style: AppTypography.caption,
                          ),
                          onSelected: (selected) => setState(() {
                            selected ? _avoid.add(option) : _avoid.remove(option);
                          }),
                          selectedColor: AppColors.accentPrimaryDark.withValues(alpha: 0.2),
                          checkmarkColor: AppColors.accentPrimaryDark,
                          backgroundColor: AppColors.bgSurfaceRaisedDark,
                          shape: const StadiumBorder(),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
          ],
        ),
      ),
    );
  }

  Widget _buildStyleCard(RouteStyle style, IconData icon, String title, String description, bool busy) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.bgSurfaceDark,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borderHairlineDark),
      ),
      child: ListTile(
        leading: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: AppColors.accentPrimaryDark.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(12),
          ),
          child: busy
              ? const Padding(
                  padding: EdgeInsets.all(12),
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(icon, color: AppColors.accentPrimaryDark, size: 24),
        ),
        title: Text(title, style: AppTypography.bodyStrong),
        subtitle: Text(description, style: AppTypography.caption),
        trailing: const Icon(Icons.chevron_right, color: AppColors.textMutedDark),
        onTap: busy ? null : () => _selectStyle(style),
        contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
      ),
    );
  }
}
