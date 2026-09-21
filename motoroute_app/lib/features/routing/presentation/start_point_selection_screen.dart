import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:motoroute_app/core/error/failure.dart';
import 'package:motoroute_app/core/i18n/i18n.dart';
import 'package:motoroute_app/core/state/app_providers.dart';
import 'package:motoroute_app/core/theme/app_colors.dart';
import 'package:motoroute_app/core/theme/app_spacing.dart';
import 'package:motoroute_app/core/theme/app_typography.dart';
import 'package:motoroute_app/features/map/data/location_repository.dart';
import 'package:motoroute_app/features/routing/domain/route_entities.dart';
import 'package:motoroute_app/features/search/search_providers.dart';

/// Schritt 1 des Routen-Starts: Wo beginnt die Fahrt? Zwei Wege -
/// 1) aktueller Standort (GPS-Fix, direkt losfahren) oder
/// 2) Adresse/Ort als Startpunkt (Tourenstart unterwegs/von zuhause).
/// Danach geht es in die Fahrstil-Wahl mit vollständigem Start-Ziel-
/// Paar; die Route selbst zeigt die Übersicht mit Karte.
class StartPointSelectionScreen extends ConsumerStatefulWidget {
  final Waypoint destination;

  const StartPointSelectionScreen({super.key, required this.destination});

  @override
  ConsumerState<StartPointSelectionScreen> createState() =>
      _StartPointSelectionScreenState();
}

class _StartPointSelectionScreenState
    extends ConsumerState<StartPointSelectionScreen> {
  bool _locating = false;

  I18n get _i18n => ref.read(i18nProvider);

  Future<void> _useCurrentLocation() async {
    setState(() => _locating = true);
    try {
      final position = await LocationRepository().getCurrentPosition();
      if (!mounted) return;
      _continueWithStart(Waypoint(
        lat: position.latitude,
        lng: position.longitude,
        label: _i18n.tr('route.chooseStart.gps'),
      ));
    } on Failure {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_i18n.tr('route.chooseStart.noFix'))),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_i18n.tr('route.chooseStart.noFix'))),
      );
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _pickAddress() async {
    final result = await Navigator.of(context).pushNamed(
      '/search',
      arguments: {'returnResult': true},
    );
    if (!mounted || result is! SearchResult) return;
    _continueWithStart(Waypoint(
      lat: result.lat,
      lng: result.lng,
      label: result.label,
    ));
  }

  void _continueWithStart(Waypoint start) {
    ref.read(waypointListProvider.notifier).state = [start, widget.destination];
    Navigator.of(context).pushReplacementNamed('/route-style', arguments: {
      'start': start,
      'destination': widget.destination,
    });
  }

  @override
  Widget build(BuildContext context) {
    final i18n = ref.watch(i18nProvider);

    return Scaffold(
      backgroundColor: AppColors.bgBaseDark,
      appBar: AppBar(
        backgroundColor: AppColors.bgBaseDark,
        title: Text(i18n.tr('route.chooseStart.title'), style: AppTypography.title),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '${widget.destination.label ?? i18n.tr('route.overview')}',
                style: AppTypography.caption,
              ),
              const SizedBox(height: AppSpacing.lg),
              _StartOptionCard(
                icon: Icons.my_location,
                title: i18n.tr('route.chooseStart.gps'),
                subtitle: i18n.tr('route.chooseStart.gpsSub'),
                busy: _locating,
                onTap: _locating ? null : _useCurrentLocation,
              ),
              const SizedBox(height: AppSpacing.md),
              _StartOptionCard(
                icon: Icons.edit_location_alt,
                title: i18n.tr('route.chooseStart.address'),
                subtitle: i18n.tr('route.chooseStart.addressSub'),
                onTap: _locating ? null : _pickAddress,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StartOptionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool busy;
  final VoidCallback? onTap;

  const _StartOptionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.busy = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      color: AppColors.bgSurfaceDark,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.borderHairlineDark),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Row(
            children: [
              busy
                  ? const SizedBox(
                      width: 28,
                      height: 28,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(icon, color: AppColors.accentPrimaryDark, size: 28),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: AppTypography.bodyStrong),
                    const SizedBox(height: AppSpacing.xs),
                    Text(subtitle, style: AppTypography.caption),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: AppColors.textSecondaryDark),
            ],
          ),
        ),
      ),
    );
  }
}
