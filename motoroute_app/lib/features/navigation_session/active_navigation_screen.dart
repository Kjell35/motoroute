import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:motoroute_app/core/state/app_providers.dart';
import 'package:motoroute_app/core/theme/app_colors.dart';
import 'package:motoroute_app/core/theme/app_spacing.dart';
import 'package:motoroute_app/core/theme/app_typography.dart';
import 'package:motoroute_app/core/utils/formatters.dart';
import 'package:motoroute_app/features/navigation_session/navigation_providers.dart';
import 'package:motoroute_app/features/traffic/traffic_providers.dart';
import 'package:motoroute_app/features/weather/route_weather_providers.dart';
import 'package:motoroute_app/features/weather/route_weather_widget.dart';

/// Screen 8: Aktive Navigation - der sicherheitskritischste Screen.
/// Echt verdrahtet: Start schreibt die aktive Route in den Navigation-
/// Controller (GPS-Stream, Off-Route-Erkennung, Rerouting), die untere
/// Zone zeigt live Restdistanz/ETA/Geschwindigkeit.
class ActiveNavigationScreen extends ConsumerStatefulWidget {
  const ActiveNavigationScreen({super.key});

  @override
  ConsumerState<ActiveNavigationScreen> createState() => _ActiveNavigationScreenState();
}

class _ActiveNavigationScreenState extends ConsumerState<ActiveNavigationScreen> {
  MaplibreMapController? _mapController;
  bool _routeDrawn = false;
  Set<String> _drawnIncidentIds = {};
  final List<Circle> _incidentCircles = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final route = ref.read(activeRouteProvider);
      if (route != null) {
        ref.read(navigationControllerProvider.notifier).start(route);
      }
    });
  }

  @override
  void dispose() {
    // Wichtig: GPS-Stream stoppen, wenn der Screen verlassen wird -
    // sonst läuft Standort-Abfrage im Hintergrund weiter (Akkueffizienz).
    ref.read(navigationControllerProvider.notifier).stop();
    ref.read(routeWeatherControllerProvider.notifier).stop();
    super.dispose();
  }

  /// Vorfälle als Kreise auf der Karte (rot = blocking/HIGH, orange =
  /// sonst). Kreise statt Linien: für "wo ist es kritisch" ist der
  /// Punkt entscheidend, und Circles sind ohne Layer-DSL robust.
  Future<void> _drawIncidents(List<TrafficIncident> incidents) async {
    final controller = _mapController;
    if (controller == null) return;

    final currentIds = incidents.map((i) => i.id).toSet();
    if (currentIds == _drawnIncidentIds) return;
    _drawnIncidentIds = currentIds;

    for (final c in _incidentCircles) {
      try {
        await controller.removeCircle(c);
      } catch (_) {}
    }
    _incidentCircles.clear();

    for (final incident in incidents.take(50)) {
      if (incident.geometry.isEmpty) continue;
      final point = incident.geometry.first;
      try {
        final circle = await controller.addCircle(
          CircleOptions(
            geometry: LatLng(point[1], point[0]),
            circleRadius: incident.isBlocking ? 10 : 7,
            circleColor: incident.isBlocking ? '#E5484D' : '#F5A623',
            circleStrokeWidth: 2,
            circleStrokeColor: '#0B0E11',
            circleOpacity: 0.85,
          ),
          {'incidentId': incident.id},
        );
        _incidentCircles.add(circle);
      } catch (_) {}
    }
  }

  Future<void> _drawRoute(ComputedRoute route) async {
    final controller = _mapController;
    if (controller == null || _routeDrawn) return;
    _routeDrawn = true;
    // maplibre_gl 0.20: addLine nimmt LineOptions inkl. Geometrie.
    await controller.addLine(
      LineOptions(
        geometry: route.geometry.map((p) => LatLng(p[1], p[0])).toList(),
        lineColor: '#FF5A1F',
        lineWidth: 6.0,
        lineOpacity: 0.9,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(navigationControllerProvider);
    final traffic = ref.watch(trafficControllerProvider);
    final unit = ref.watch(distanceUnitProvider);
    final route = state.route;

    if (route != null) {
      _drawRoute(route);
    }
    _drawIncidents(traffic.incidents);

    return Scaffold(
      backgroundColor: AppColors.bgBaseDark,
      body: SafeArea(
        child: Column(
          children: [
            _buildTopZone(route, state),
            const RouteWeatherWidget(),
            if (state.energySaverCritical) _buildEnergySaverWarning(),
            if (state.isRerouting || state.error != null || state.rerouteReason != null)
              _buildReroutingBanner(state),
            Expanded(
              child: Stack(
                children: [
                  MaplibreMap(
                    styleString: String.fromEnvironment('MAP_STYLE_URL', defaultValue: ''),
                    initialCameraPosition: CameraPosition(
                      target: route == null || route.geometry.isEmpty
                          ? const LatLng(48.1351, 11.5820)
                          : LatLng(route.geometry.first[1], route.geometry.first[0]),
                      zoom: 14,
                    ),
                    myLocationEnabled: true,
                    myLocationTrackingMode: MyLocationTrackingMode.tracking,
                    onMapCreated: (controller) {
                      _mapController = controller;
                      if (route != null) _drawRoute(route);
                    },
                  ),
                  if (state.isOffRoute)
                    const Positioned(
                      top: AppSpacing.md,
                      left: AppSpacing.lg,
                      right: AppSpacing.lg,
                      child: _OffRouteBadge(),
                    ),
                ],
              ),
            ),
            _buildBottomZone(state, unit),
            _buildControlButtons(context),
          ],
        ),
      ),
    );
  }

  Widget _buildTopZone(ComputedRoute? route, NavigationState state) {
    final nextInstruction = (route != null && route.segments.isNotEmpty)
        ? route.segments.first.instruction
        : 'Route folgen';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md),
      decoration: const BoxDecoration(
        color: AppColors.bgSurfaceDark,
        border: Border(bottom: BorderSide(color: AppColors.borderHairlineDark)),
      ),
      child: Row(
        children: [
          const Icon(Icons.turn_left, color: AppColors.accentPrimaryDark, size: 32),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(nextInstruction, style: AppTypography.navInstruction),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Sicherheitshinweis bei kritischem Akku: GPS ist dann so weit
  /// gedrosselt, dass Off-Route-Erkennung deutlich später (oder gar
  /// nicht) greift - das muss der Fahrer wissen, nicht überraschen
  /// werden (Phase 3 Teil B.10: keine stillen Verschlechterungen).
  Widget _buildEnergySaverWarning() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.xs),
      color: AppColors.statusDanger.withValues(alpha: 0.2),
      child: const Row(
        children: [
          Icon(Icons.battery_alert, color: AppColors.statusDanger, size: 16),
          SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              'Kritischer Akku - GPS gedrosselt, Off-Route-Warnung verzögert',
              style: AppTypography.caption,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReroutingBanner(NavigationState state) {
    // Drei Zustände: laufende Anpassung (orange), abgeschlossene
    // proaktive Umleitung mit Grund (grünlich, auto-vergehend), Fehler
    // (rot). Phase 3 B.10: nie modal, immer als schmaler Banner.
    final Color bg;
    final Color fg;
    final IconData icon;
    final String text;
    if (state.isRerouting) {
      bg = AppColors.statusWarning.withValues(alpha: 0.15);
      fg = AppColors.statusWarning;
      icon = Icons.refresh;
      text = 'Route wird angepasst…';
    } else if (state.rerouteReason != null) {
      bg = AppColors.accentSecondary.withValues(alpha: 0.15);
      fg = AppColors.accentSecondary;
      icon = Icons.alt_route;
      text = 'Umleitung: ${state.rerouteReason}';
    } else {
      bg = AppColors.statusDanger.withValues(alpha: 0.15);
      fg = AppColors.statusDanger;
      icon = Icons.error_outline;
      text = state.error ?? '';
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
      color: bg,
      child: Row(
        children: [
          Icon(icon, color: fg, size: 16),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(text, style: AppTypography.caption)),
        ],
      ),
    );
  }

  Widget _buildBottomZone(NavigationState state, dynamic unit) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md),
      decoration: const BoxDecoration(
        color: AppColors.bgSurfaceDark,
        border: Border(top: BorderSide(color: AppColors.borderHairlineDark)),
      ),
      child: Row(
        children: [
          Expanded(
            child: _ValueItem(
              icon: Icons.speed,
              value: formatSpeedMps(state.speedMps, unit: unit),
            ),
          ),
          Expanded(
            child: _ValueItem(
              icon: Icons.straighten,
              value: formatDistanceMeters(state.remainingMeters, unit: unit),
            ),
          ),
          Expanded(
            child: _ValueItem(
              icon: Icons.access_time,
              value: formatEta(DateTime.now(), state.remainingSeconds),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControlButtons(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        children: [
          Expanded(
            child: _CircleButton(
              icon: Icons.stop,
              label: 'Beenden',
              onTap: () {
                ref.read(navigationControllerProvider.notifier).stop();
                Navigator.of(context).popUntil((r) => r.settings.name == '/map' || r.isFirst);
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _OffRouteBadge extends StatelessWidget {
  const _OffRouteBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.statusWarning.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.route, color: AppColors.textPrimaryDark, size: 18),
          SizedBox(width: AppSpacing.sm),
          Text('Von der Route abgewichen', style: AppTypography.caption),
        ],
      ),
    );
  }
}

class _ValueItem extends StatelessWidget {
  final IconData icon;
  final String value;

  const _ValueItem({required this.icon, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: AppColors.textSecondaryDark, size: 18),
        Text(value, style: AppTypography.bodyStrong),
      ],
    );
  }
}

class _CircleButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _CircleButton({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.bgSurfaceRaisedDark.withValues(alpha: 0.7),
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Container(
          width: AppSpacing.touchTargetDriving,
          height: AppSpacing.touchTargetDriving,
          alignment: Alignment.center,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: AppColors.textPrimaryDark, size: 24),
              Text(label, style: AppTypography.caption),
            ],
          ),
        ),
      ),
    );
  }
}
