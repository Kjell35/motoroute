import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/route_enums.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/state/app_providers.dart'
    show activeRouteProvider, ComputedRoute;
import '../../chat/chat_providers.dart';
import '../../routing/domain/route_entities.dart';
import '../../routing/data/routing_providers.dart';
import '../group_route_repository.dart';

/// Übergibt die gemeinsame Route an die NORMALE Navigation (Abschnitt 17):
/// Start → Stopps → Ziel mit gespeicherter Präferenz werden über das
/// bestehende Routing-Repository berechnet und in activeRouteProvider
/// gelegt - danach läuft der Standard-Flow (Übersicht → aktive Navigation).
class GroupRouteStartScreen extends ConsumerStatefulWidget {
  final String routeId;
  const GroupRouteStartScreen({super.key, required this.routeId});

  @override
  ConsumerState<GroupRouteStartScreen> createState() => _GroupRouteStartScreenState();
}

class _GroupRouteStartScreenState extends ConsumerState<GroupRouteStartScreen> {
  bool _starting = false;
  String? _error;

  RouteStyle _styleFrom(String raw) => switch (raw) {
        'FAST' => RouteStyle.fast,
        'EXTRA_CURVY' => RouteStyle.extraCurvy,
        'FAST_AND_CURVY' => RouteStyle.fastAndCurvy,
        'UNPAVED' => RouteStyle.unpaved,
        _ => RouteStyle.curvy,
      };

  VehicleType _vehicleFrom(String raw) => switch (raw) {
        'CAR' => VehicleType.car,
        'BICYCLE' => VehicleType.bicycle,
        _ => VehicleType.motorcycle,
      };

  Future<void> _start() async {
    if (_starting) return;
    setState(() {
      _starting = true;
      _error = null;
    });
    try {
      final token = ref.read(chatSessionTokenProvider)!;
      final detail = await ref.read(groupRouteRepositoryProvider).get(token, widget.routeId);
      final route = detail.route;

      final waypoints = <Waypoint>[
        Waypoint(lat: route.startLat, lng: route.startLng, label: route.startName),
        ...detail.stops.map((s) => Waypoint(lat: s.lat, lng: s.lng, label: s.name)),
        Waypoint(lat: route.destLat, lng: route.destLng, label: route.destName),
      ];

      final preference = RoutePreference(
        style: _styleFrom(route.routingStyle),
        vehicleType: _vehicleFrom(route.vehicleType),
        avoid: {
          if (route.avoidHighways) AvoidOption.highway,
          if (route.avoidFerries) AvoidOption.ferry,
          if (route.avoidTolls) AvoidOption.toll,
        },
      );

      // Echte Berechnung über das bestehende Routing-Repository (dieselbe
      // Engine wie der normale Planer - Profil/Overrides stimmen exakt).
      final result = await ref
          .read(routingRepositoryProvider)
          .createRoute(waypoints: waypoints, preference: preference);
      final computed = result.fold(
        (failure) => throw Exception(failure.message),
        (route) => route,
      );

      // In den globalen Flow legen und Status 'riding' markieren.
      ref.read(activeRouteProvider.notifier).state = ComputedRoute.fromDomain(computed);
      await ref
          .read(groupRouteRepositoryProvider)
          .setStatus(token, widget.routeId, GroupRouteStatus.riding);

      if (!mounted) return;
      Navigator.of(context).pushNamedAndRemoveUntil('/route-overview', (r) => r.isFirst);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _starting = false;
        _error = 'Route konnte nicht gestartet werden';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgBaseDark,
      appBar: AppBar(backgroundColor: AppColors.bgBaseDark, title: const Text('Route starten')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.motorcycle, size: 64, color: AppColors.accentPrimaryDark),
              const SizedBox(height: AppSpacing.lg),
              const Text('Bereit für die gemeinsame Tour?',
                  style: TextStyle(
                      color: AppColors.textPrimaryDark, fontSize: 20, fontWeight: FontWeight.w700)),
              const SizedBox(height: AppSpacing.sm),
              const Text(
                'Die Route wird mit den gespeicherten Einstellungen\n(Fahrstil, Vermeidungen, Stopps) an die Navigation übergeben.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSecondaryDark),
              ),
              if (_error != null) ...[
                const SizedBox(height: AppSpacing.md),
                Text(_error!, style: const TextStyle(color: AppColors.statusDanger)),
              ],
              const SizedBox(height: AppSpacing.xl),
              _starting
                  ? const CircularProgressIndicator(color: AppColors.accentPrimaryDark)
                  : FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.accentPrimaryDark,
                        foregroundColor: AppColors.textPrimaryDark,
                        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                      ),
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('NAVIGATION STARTEN', style: TextStyle(fontWeight: FontWeight.w700)),
                      onPressed: _start,
                    ),
            ],
          ),
        ),
      ),
    );
  }
}
