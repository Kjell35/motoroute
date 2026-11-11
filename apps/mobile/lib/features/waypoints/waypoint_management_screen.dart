import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:motoroute_app/core/state/app_providers.dart';
import 'package:motoroute_app/core/theme/app_colors.dart';
import 'package:motoroute_app/core/theme/app_spacing.dart';
import 'package:motoroute_app/core/theme/app_typography.dart';
import 'package:motoroute_app/features/pairing/data/pairing_repository.dart';
import 'package:motoroute_app/features/pairing/presentation/computer_planning_sheet.dart';

/// Screen 9: Wegpunktverwaltung - arbeitet auf dem echten
/// waypointListProvider: Reihenfolge per Drag, Löschen per Icon.
/// "+ Wegpunkt hinzufügen" öffnet die Suche; das Ergebnis landet als
/// Zwischenziel in der Liste (via arguments-Vertrag in main.dart).
class WaypointManagementScreen extends ConsumerWidget {
  const WaypointManagementScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final waypoints = ref.watch(waypointListProvider);
    final notifier = ref.read(waypointListProvider.notifier);

    final tapMode = ref.watch(mapWaypointTapModeProvider);

    return Scaffold(
      backgroundColor: context.palette.bgBase,
      appBar: AppBar(
        backgroundColor: context.palette.bgBase,
        title: const Text('Routenplanung', style: AppTypography.title),
        actions: [
          // M3-Feature „Route am Computer planen“ (QR + Plan abrufen).
          IconButton(
            tooltip: 'Route am Computer planen',
            icon: Icon(Icons.computer_outlined,
                color: context.palette.textSecondary),
            onPressed: () {
              showModalBottomSheet<void>(
                context: context,
                backgroundColor: context.palette.bgSurface,
                showDragHandle: true,
                isScrollControlled: true,
                builder: (_) =>
                    ComputerPlanningSheet(repository: PairingRepository()),
              );
            },
          ),
          IconButton(
            tooltip: 'GPX importieren',
            icon: Icon(Icons.upload_file_outlined,
                color: context.palette.textSecondary),
            onPressed: () => Navigator.of(context).pushNamed('/tour-import'),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: waypoints.isEmpty
                  ? Center(
                      child: Text(
                        'Noch keine Wegpunkte - suche ein Ziel, um zu starten.',
                        style: AppTypography.body
                            .copyWith(color: context.palette.textSecondary),
                        textAlign: TextAlign.center,
                      ),
                    )
                  : ReorderableListView.builder(
                      padding:
                          const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                      itemCount: waypoints.length,
                      onReorderItem: (oldIndex, newIndex) {
                        final updated = [...waypoints];
                        final item = updated.removeAt(oldIndex);
                        updated.insert(newIndex, item);
                        notifier.state = updated;
                      },
                      itemBuilder: (context, index) {
                        final wp = waypoints[index];
                        final isFirst = index == 0;
                        final isLast = index == waypoints.length - 1;
                        return Container(
                          key: ValueKey('${wp.lat}_${wp.lng}_$index'),
                          margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                          decoration: BoxDecoration(
                            color: context.palette.bgSurface,
                            borderRadius: BorderRadius.circular(12),
                            border:
                                Border.all(color: context.palette.borderHairline),
                          ),
                          child: ListTile(
                            leading: Icon(
                              isFirst
                                  ? Icons.trip_origin
                                  : isLast
                                      ? Icons.flag
                                      : Icons.location_on_outlined,
                              color: isFirst
                                  ? context.palette.accentPrimary
                                  : isLast
                                      ? context.palette.accentSecondary
                                      : context.palette.textSecondary,
                              size: 20,
                            ),
                            title: Text(
                              wp.label ?? 'Wegpunkt ${index + 1}',
                              style: AppTypography.bodyStrong,
                            ),
                            subtitle: Text(
                              '${wp.lat.toStringAsFixed(4)}, ${wp.lng.toStringAsFixed(4)}',
                              style: AppTypography.captionOf(context),
                            ),
                            trailing: IconButton(
                              // Start und Ziel sind im MVP-Flow Fixpunkte -
                              // Zwischenziele dürfen gelöscht werden.
                              onPressed: (!isFirst && !isLast)
                                  ? () {
                                      final updated = [...waypoints]
                                        ..removeAt(index);
                                      notifier.state = updated;
                                    }
                                  : null,
                              icon: Icon(Icons.close,
                                  color: context.palette.textMuted, size: 20),
                            ),
                          ),
                        );
                      },
                    ),
            ),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                children: [
                  SizedBox(
                    width: double.infinity,
                    height: AppSpacing.touchTargetPlanning,
                    child: OutlinedButton.icon(
                      onPressed: () => Navigator.of(context).pushNamed(
                          '/search',
                          arguments: {'addWaypoint': true}),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(
                            color: context.palette.borderHairline),
                        foregroundColor: context.palette.textPrimary,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      icon: const Icon(Icons.add),
                      label: const Text('Wegpunkt suchen'),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  SizedBox(
                    width: double.infinity,
                    height: AppSpacing.touchTargetPlanning,
                    child: OutlinedButton.icon(
                      // Phase 3 Screen 9: "Auf Karte antippen" als
                      // expliziter Modus-Umschalter.
                      onPressed: () {
                        ref.read(mapWaypointTapModeProvider.notifier).state =
                            true;
                        Navigator.of(context).pushNamed('/map');
                      },
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(
                            color: context.palette.borderHairline),
                        foregroundColor: context.palette.textPrimary,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      icon: const Icon(Icons.add_location_alt_outlined),
                      label: Text(tapMode
                          ? 'Kartentap-Modus aktiv'
                          : 'Auf Karte antippen'),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
