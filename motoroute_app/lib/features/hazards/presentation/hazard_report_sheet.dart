import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../hazard_repository.dart';

/// Gefahrenstelle melden - von unterwegs, mit Handschuhen, in 2 Klicks:
///
///   Klick 1: Typ antippen (Rollsplitt / Sperrung / Baustelle / Ölspur)
///   Klick 2: MELDEN
///
/// Die Position kommt automatisch vom GPS (aktuelle Standort), ein
/// Freitext ist bewusst NICHT Teil des Schnellflows - der kostet beim
/// Fahren Zeit und Aufmerksamkeit. Große Touch-Flächen (>= 56 dp),
/// klare Farben, eine Hand bedienbar.
///
/// Zeigt nach dem Senden ehrlich an, ob die Meldung neu ist oder eine
/// bestehende Gefahr im Umkreis bestätigt hat (Server-Konsolidierung).
Future<void> showHazardReportSheet(BuildContext context) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.bgSurfaceDark,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (context) => const _HazardReportSheet(),
  );
}

class _HazardReportSheet extends ConsumerStatefulWidget {
  const _HazardReportSheet();

  @override
  ConsumerState<_HazardReportSheet> createState() => _HazardReportSheetState();
}

class _HazardReportSheetState extends ConsumerState<_HazardReportSheet> {
  HazardType? _selected;
  bool _sending = false;
  String? _error;

  Future<void> _send() async {
    final type = _selected;
    if (type == null || _sending) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      // Position JETZT holen - der Nutzer meldet, wo er gerade steht/fährt.
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      ).timeout(const Duration(seconds: 8));

      final result = await ref.read(hazardRadarProvider.notifier).reportHere(
            type: type,
            lat: position.latitude,
            lng: position.longitude,
          );

      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.ok
              ? (result.merged
                  ? '${type.label} bestätigt - danke für die Bestätigung!'
                  : '${type.label} gemeldet - danke! Die Meldung ist 24 h aktiv.')
              : 'Meldung fehlgeschlagen - bitte später erneut versuchen'),
        ),
      );
    } catch (_) {
      if (mounted) {
        setState(() {
          _sending = false;
          _error = 'Standort oder Netz nicht verfügbar';
        });
      }
    }
  }

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
                const Icon(Icons.warning_amber_rounded,
                    color: AppColors.accentSecondary, size: 24),
                const SizedBox(width: AppSpacing.sm),
                Text('Gefahrenstelle melden', style: AppTypography.title),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Wird automatisch an deiner aktuellen Position gemeldet.\nGilt 24 Stunden, Bestätigungen verlängern die Gültigkeit.',
              style: AppTypography.caption,
            ),
            const SizedBox(height: AppSpacing.lg),
            // Klick 1: Typ auswählen (4 große Flächen, 2x2-Grid).
            Row(
              children: [
                Expanded(child: _typeTile(HazardType.rollsplitt)),
                const SizedBox(width: AppSpacing.sm),
                Expanded(child: _typeTile(HazardType.sperrung)),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(child: _typeTile(HazardType.baustelle)),
                const SizedBox(width: AppSpacing.sm),
                Expanded(child: _typeTile(HazardType.oelspur)),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(_error!,
                  style: const TextStyle(color: AppColors.statusDanger, fontSize: 13)),
            ],
            const SizedBox(height: AppSpacing.lg),
            // Klick 2: Absenden (erst aktiv, wenn Typ gewählt).
            SizedBox(
              width: double.infinity,
              height: AppSpacing.touchTargetPlanning,
              child: ElevatedButton(
                onPressed: _selected == null || _sending ? null : _send,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.statusDanger,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: AppColors.bgSurfaceRaisedDark,
                ),
                child: _sending
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(
                        _selected == null
                            ? 'Erst Typ wählen'
                            : '${_selected!.label} MELDEN',
                        style: const TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 16),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _typeTile(HazardType type) {
    final selected = _selected == type;
    return GestureDetector(
      onTap: () => setState(() => _selected = type),
      child: Container(
        height: 72,
        decoration: BoxDecoration(
          color: selected ? AppColors.accentPrimaryDark.withValues(alpha: 0.25) : AppColors.bgSurfaceRaisedDark,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? AppColors.accentPrimaryDark : AppColors.borderHairlineDark,
            width: selected ? 2 : 1,
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          type.label,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: selected ? AppColors.textPrimaryDark : AppColors.textSecondaryDark,
            fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
            fontSize: 15,
          ),
        ),
      ),
    );
  }
}
