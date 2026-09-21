import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:motoroute_app/core/i18n/i18n.dart';
import 'package:motoroute_app/core/state/app_providers.dart';
import 'package:motoroute_app/core/theme/app_colors.dart';
import 'package:motoroute_app/core/theme/app_spacing.dart';
import 'package:motoroute_app/core/theme/app_typography.dart';
import 'package:motoroute_app/core/utils/formatters.dart';
import 'package:motoroute_app/features/map/data/map_style.dart';
import 'package:motoroute_app/features/routing/domain/route_entities.dart';

/// Screen 7: Routenübersicht - zeigt die tatsächlich berechnete Route
/// AUF DER KARTE (Linie + Start-/Ziel-/Wegpunkt-Marker, automatisch
/// passender Ausschnitt) plus Distanz/Fahrzeit/ETA und Segmente.
class RouteOverviewScreen extends ConsumerStatefulWidget {
  const RouteOverviewScreen({super.key});

  @override
  ConsumerState<RouteOverviewScreen> createState() => _RouteOverviewScreenState();
}

class _RouteOverviewScreenState extends ConsumerState<RouteOverviewScreen> {
  MaplibreMapController? _mapController;
  String? _styleString;
  bool _drawn = false;

  @override
  void initState() {
    super.initState();
    _loadStyle();
  }

  Future<void> _loadStyle() async {
    final choice = ref.read(mapStyleChoiceProvider);
    final style = await loadMapStyle(choice);
    if (mounted) setState(() => _styleString = style);
  }

  /// Route + Markierungen zeichnen und den Ausschnitt so wählen, dass
  /// alles sichtbar ist (Start, Ziel, Wegpunkte, komplette Linie).
  Future<void> _drawRoute(ComputedRoute route) async {
    final controller = _mapController;
    if (controller == null || _drawn) return;
    _drawn = true;

    final latLngs = route.geometry.map((p) => LatLng(p[1], p[0])).toList();
    if (latLngs.isEmpty) return;

    await controller.addLine(
      LineOptions(
        geometry: latLngs,
        lineColor: '#FF5A1F',
        lineWidth: 5.0,
        lineOpacity: 0.9,
      ),
    );

    // Marker: Start (grün), Ziel (rot), Wegpunkte/Stopps (orange).
    final waypoints = route.waypoints;
    for (var i = 0; i < waypoints.length; i++) {
      final wp = waypoints[i];
      final isFirst = i == 0;
      final isLast = i == waypoints.length - 1;
      try {
        await controller.addSymbol(SymbolOptions(
          geometry: LatLng(wp.lat, wp.lng),
          iconImage: 'circle-15',
          iconSize: isFirst || isLast ? 1.4 : 1.1,
          iconColor: isFirst
              ? '#3DD68C'
              : isLast
                  ? '#E5484D'
                  : '#FF5A1F',
          textField: wp.label ??
              (isFirst
                  ? 'Start'
                  : isLast
                      ? 'Ziel'
                      : '${i + 1}'),
          textOffset: const Offset(0, 1.2),
          textSize: 12,
          textColor: '#FFFFFF',
          textHaloColor: '#0B0E11',
          textHaloWidth: 1.2,
        ));
      } catch (_) {}
    }

    // Ausschnitt: komplette Route sichtbar, mit Rand.
    final lats = latLngs.map((e) => e.latitude).toList();
    const pad = 0.01;
    await controller.moveCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(lats.reduce((a, b) => a < b ? a : b) - pad,
              latLngs.map((e) => e.longitude).reduce((a, b) => a < b ? a : b) - pad),
          northeast: LatLng(lats.reduce((a, b) => a > b ? a : b) + pad,
              latLngs.map((e) => e.longitude).reduce((a, b) => a > b ? a : b) + pad),
        ),
        left: 48,
        top: 48,
        right: 48,
        bottom: 48,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final route = ref.watch(activeRouteProvider);
    final unit = ref.watch(distanceUnitProvider);
    final i18n = ref.watch(i18nProvider);

    if (route == null) {
      return Scaffold(
        backgroundColor: AppColors.bgBaseDark,
        appBar: AppBar(backgroundColor: AppColors.bgBaseDark),
        body: Center(child: Text(i18n.tr('route.overview'))),
      );
    }

    final now = DateTime.now();

    return Scaffold(
      backgroundColor: AppColors.bgBaseDark,
      appBar: AppBar(
        backgroundColor: AppColors.bgBaseDark,
        title: Text(i18n.tr('route.overview'), style: AppTypography.title),
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
            Expanded(
              child: _styleString == null
                  ? const Center(child: CircularProgressIndicator())
                  : Stack(
                      children: [
                        MaplibreMap(
                          styleString: isPlaceholderStyle(_styleString!)
                              ? emptyMapStyle
                              : _styleString!,
                          initialCameraPosition: CameraPosition(
                            target: LatLng(
                              route.geometry.first[1],
                              route.geometry.first[0],
                            ),
                            zoom: 12,
                          ),
                          onMapCreated: (controller) {
                            _mapController = controller;
                            _drawRoute(route);
                          },
                        ),
                        Positioned(
                          left: AppSpacing.sm,
                          bottom: AppSpacing.xs,
                          child: Text(
                            isPlaceholderStyle(_styleString!)
                                ? i18n.tr('map.offlineNote')
                                : i18n.tr('map.attribution'),
                            style: const TextStyle(
                              color: AppColors.textMutedDark,
                              fontSize: 10,
                            ),
                          ),
                        ),
                      ],
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
                      label: i18n.tr('route.distance'),
                      value: formatDistanceMeters(route.distanceMeters, unit: unit),
                    ),
                  ),
                  Expanded(
                    child: _SummaryItem(
                      icon: Icons.access_time,
                      label: i18n.tr('route.duration'),
                      value: formatDurationSeconds(route.durationSeconds),
                    ),
                  ),
                  Expanded(
                    child: _SummaryItem(
                      icon: Icons.flag,
                      label: i18n.tr('route.eta'),
                      value: formatEta(now, route.durationSeconds),
                    ),
                  ),
                ],
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
                  child: Text(i18n.tr('route.startNavigation'),
                      style: const TextStyle(fontWeight: FontWeight.w600)),
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
