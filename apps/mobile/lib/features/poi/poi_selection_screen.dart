import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:motoroute_app/core/state/app_providers.dart';
import 'package:motoroute_app/core/theme/app_colors.dart';
import 'package:motoroute_app/core/theme/app_spacing.dart';
import 'package:motoroute_app/core/theme/app_typography.dart';

/// Screen 10: POI-Auswahl - kompakter Bottom Sheet. Kategorie-Toggles
/// schreiben sofort in activePoiCategoriesProvider; die Karte liest
/// denselben State (ein Tap schaltet die Sichtbarkeit um - kein
/// "Anwenden"-Button laut Phase 3, Teil C.10).
class PoiSelectionScreen extends ConsumerWidget {
  const PoiSelectionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref.watch(activePoiCategoriesProvider);

    return Scaffold(
      backgroundColor: AppColors.bgBaseDark,
      appBar: AppBar(
        backgroundColor: AppColors.bgBaseDark,
        title: Text('POIs auf Karte', style: AppTypography.title),
      ),
      body: SafeArea(
        child: ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          itemCount: PoiCategory.values.length,
          itemBuilder: (context, index) {
            final category = PoiCategory.values[index];
            final isActive = active.contains(category);
            return Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.bgSurfaceDark,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isActive ? AppColors.accentSecondary : AppColors.borderHairlineDark,
                  ),
                ),
                child: ListTile(
                  leading: Icon(
                    _iconFor(category),
                    color: isActive ? AppColors.accentSecondary : AppColors.textMutedDark,
                    size: 24,
                  ),
                  title: Text(category.label, style: AppTypography.bodyStrong),
                  trailing: Switch(
                    value: isActive,
                    onChanged: (value) {
                      final updated = {...ref.read(activePoiCategoriesProvider)};
                      value ? updated.add(category) : updated.remove(category);
                      ref.read(activePoiCategoriesProvider.notifier).state = updated;
                    },
                    activeColor: AppColors.accentSecondary,
                    inactiveThumbColor: AppColors.textMutedDark,
                    inactiveTrackColor: AppColors.bgSurfaceRaisedDark,
                  ),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  IconData _iconFor(PoiCategory category) => switch (category) {
        PoiCategory.fuel => Icons.local_gas_station,
        PoiCategory.motoHotel => Icons.hotel,
        PoiCategory.bikerMeetup => Icons.local_bar,
        PoiCategory.campsite => Icons.forest,
        PoiCategory.iceCream => Icons.icecream,
        PoiCategory.speedCamera => Icons.camera_alt,
        PoiCategory.restaurant => Icons.restaurant,
        PoiCategory.pub => Icons.sports_bar,
        PoiCategory.snack => Icons.fastfood,
      };
}
