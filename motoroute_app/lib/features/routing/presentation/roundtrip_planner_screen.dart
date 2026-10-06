import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:motoroute_app/core/constants/route_enums.dart';
import 'package:motoroute_app/core/error/failure.dart';
import 'package:motoroute_app/core/i18n/i18n.dart';
import 'package:motoroute_app/core/state/app_providers.dart';
import 'package:motoroute_app/core/theme/app_colors.dart';
import 'package:motoroute_app/core/theme/app_spacing.dart';
import 'package:motoroute_app/core/theme/app_typography.dart';
import 'package:motoroute_app/features/map/data/location_repository.dart';
import 'package:motoroute_app/features/routing/data/routing_providers.dart';
import 'package:motoroute_app/features/routing/domain/route_entities.dart';
import 'package:motoroute_app/features/search/search_providers.dart';
import 'package:motoroute_app/core/utils/formatters.dart' show DistanceUnit;

/// Rundtour planen (Feature aus der Konkurrenz-Analyse): Laenge per
/// Slider, Start = aktueller Standort, Routingprofil + Richtung.
/// Das Ergebnis ist eine NORMALE Route - sie landet in
/// [activeRouteProvider] und nutzt Routenuebersicht + Navigation
/// unveraendert mit.
class RoundTripPlannerScreen extends ConsumerStatefulWidget {
  const RoundTripPlannerScreen({super.key});

  @override
  ConsumerState<RoundTripPlannerScreen> createState() => _RoundTripPlannerScreenState();
}

class _RoundTripPlannerScreenState extends ConsumerState<RoundTripPlannerScreen> {
  double _distanceKm = 125;
  RouteStyle _style = RouteStyle.curvy;
  String _direction = 'RANDOM';
  bool _creating = false;
  bool _locating = false;
  Waypoint? _start;

  /// Styles passend zum gewaehlten Fahrzeug (wie im Punkt-zu-Punkt-Flow).
  List<RouteStyle> get _supportedStyles => switch (ref.read(vehicleTypeProvider)) {
        VehicleType.motorcycle => const [
            RouteStyle.fast,
            RouteStyle.curvy,
            RouteStyle.extraCurvy,
            RouteStyle.fastAndCurvy,
            RouteStyle.unpaved,
          ],
        VehicleType.car => const [
            RouteStyle.fast,
            RouteStyle.curvy,
            RouteStyle.fastAndCurvy,
          ],
        VehicleType.bicycle => const [RouteStyle.fast, RouteStyle.curvy],
      };

  String _styleLabel(RouteStyle style, I18n i18n) => switch (style) {
        RouteStyle.fast => i18n.tr('route.style.fast'),
        RouteStyle.curvy => i18n.tr('route.style.curvy'),
        RouteStyle.extraCurvy => i18n.tr('route.style.extraCurvy'),
        RouteStyle.fastAndCurvy => i18n.tr('route.style.fastAndCurvy'),
        RouteStyle.unpaved => i18n.tr('route.style.unpaved'),
      };

  String _directionLabel(String direction, I18n i18n) => switch (direction) {
        'NORTH' => i18n.tr('roundtrip.dir.north'),
        'EAST' => i18n.tr('roundtrip.dir.east'),
        'SOUTH' => i18n.tr('roundtrip.dir.south'),
        'WEST' => i18n.tr('roundtrip.dir.west'),
        _ => i18n.tr('roundtrip.dir.random'),
      };

  /// Start bestimmen: bevorzugt GPS-Fix; ohne Fix erlaubt der Screen
  /// weiterhin Adresswahl ueber die Suche (kein stiller GPS-Zwang).
  Future<void> _ensureStart() async {
    if (_start != null || _locating) return;
    setState(() => _locating = true);
    try {
      final position = await LocationRepository().getCurrentPosition();
      if (!mounted) return;
      setState(() {
        _start = Waypoint(
          lat: position.latitude,
          lng: position.longitude,
          label: ref.read(i18nProvider).tr('route.chooseStart.gps'),
        );
      });
    } catch (_) {
      // Kein GPS-Fix: _start bleibt null, der CTA fragt dann per Suche ab.
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _pickStartViaSearch() async {
    final result = await Navigator.of(context).pushNamed(
      '/search',
      arguments: {'returnResult': true},
    );
    if (!mounted || result is! SearchResult) return;
    setState(() {
      _start = Waypoint(lat: result.lat, lng: result.lng, label: result.label);
    });
  }

  Future<void> _create() async {
    if (_creating) return;

    if (_start == null) {
      await _ensureStart();
      if (!mounted) return;
      if (_start == null) {
        await _pickStartViaSearch();
        if (!mounted || _start == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(ref.read(i18nProvider).tr('route.chooseStart.noFix'))),
          );
          return;
        }
      }
    }

    setState(() => _creating = true);
    final start = _start!;
    final result = await ref.read(routingRepositoryProvider).createRoundTrip(
          start: start,
          targetDistanceKm: _distanceKm,
          style: _style,
          vehicleType: ref.read(vehicleTypeProvider),
          direction: _direction,
        );

    if (!mounted) return;
    setState(() => _creating = false);

    result.fold(
      (failure) {
        final message = switch (failure) {
          NetworkFailure() => ref.read(i18nProvider).errNetwork,
          RoutingFailure(:final message) => message,
          UnexpectedFailure() => ref.read(i18nProvider).errUnknown,
        };
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      },
      (route) {
        final computed = ComputedRoute.fromDomain(route);
        ref.read(activeRouteProvider.notifier).state = computed;
        Navigator.of(context).pushReplacementNamed('/route-overview');
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final i18n = ref.watch(i18nProvider);
    final unit = ref.watch(distanceUnitProvider);
    final distanceText = unit == DistanceUnit.miles
        ? '${(_distanceKm * 0.621371).round()} ${i18n.tr('unit.mi')}'
        : '${_distanceKm.round()} ${i18n.tr('unit.km')}';

    return Scaffold(
      backgroundColor: AppColors.bgBaseDark,
      appBar: AppBar(
        backgroundColor: AppColors.bgBaseDark,
        title: Text(i18n.tr('roundtrip.title'), style: AppTypography.title),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                children: [
                  const SizedBox(height: AppSpacing.xl),
                  Center(
                    child: Text(i18n.tr('roundtrip.length'),
                        style: AppTypography.caption.copyWith(fontSize: 16)),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Center(
                    child: Text(distanceText,
                        style: AppTypography.display.copyWith(fontSize: 56)),
                  ),
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      activeTrackColor: AppColors.statusDanger,
                      inactiveTrackColor: AppColors.bgSurfaceRaisedDark,
                      thumbColor: AppColors.textPrimaryLight,
                      overlayColor: AppColors.statusDanger.withValues(alpha: 0.15),
                    ),
                    child: Slider(
                      value: _distanceKm,
                      min: 10,
                      max: 500,
                      divisions: 49,
                      onChanged: (v) => setState(() => _distanceKm = v),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Container(
                    decoration: BoxDecoration(
                      color: AppColors.bgSurfaceDark,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.borderHairlineDark),
                    ),
                    child: Column(
                      children: [
                        _Row(
                          icon: Icons.near_me,
                          label: i18n.tr('roundtrip.startFrom'),
                          value: _locating
                              ? i18n.tr('roundtrip.locating')
                              : (_start?.label ?? i18n.tr('roundtrip.startAuto')),
                          onTap: _locating ? null : () async {
                            await _ensureStart();
                            if (!mounted || _start != null) return;
                            await _pickStartViaSearch();
                          },
                        ),
                        _Divider(),
                        // Routingprofil: zyklisch durch die unterstuetzten
                        // Styles (kein extra Sheet - ein Tap, klares Feedback).
                        _Row(
                          icon: Icons.route,
                          label: i18n.tr('roundtrip.profile'),
                          value: _styleLabel(_style, i18n),
                          onTap: () {
                            final styles = _supportedStyles;
                            final next = styles[(styles.indexOf(_style) + 1) % styles.length];
                            setState(() => _style = next);
                          },
                        ),
                        _Divider(),
                        // Richtung: RANDOM -> N -> E -> S -> W -> RANDOM.
                        _Row(
                          icon: Icons.explore,
                          label: i18n.tr('roundtrip.direction'),
                          value: _directionLabel(_direction, i18n),
                          onTap: () {
                            const order = ['RANDOM', 'NORTH', 'EAST', 'SOUTH', 'WEST'];
                            final next = order[(order.indexOf(_direction) + 1) % order.length];
                            setState(() => _direction = next);
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: SizedBox(
                width: double.infinity,
                height: AppSpacing.touchTargetPlanning,
                child: ElevatedButton(
                  onPressed: _creating ? null : _create,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.statusDanger,
                    foregroundColor: AppColors.textPrimaryLight,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                  ),
                  child: _creating
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: AppColors.textPrimaryLight,
                          ),
                        )
                      : Text(i18n.tr('roundtrip.create'),
                          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final VoidCallback? onTap;

  const _Row({required this.icon, required this.label, required this.value, this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.lg),
        child: Row(
          children: [
            Icon(icon, color: AppColors.textSecondaryDark, size: 20),
            const SizedBox(width: AppSpacing.md),
            Expanded(child: Text(label, style: AppTypography.bodyStrong)),
            Text(value,
                style: AppTypography.body.copyWith(color: AppColors.textSecondaryDark)),
            const SizedBox(width: AppSpacing.xs),
          ],
        ),
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: Divider(height: 1, color: AppColors.borderHairlineDark),
    );
  }
}
