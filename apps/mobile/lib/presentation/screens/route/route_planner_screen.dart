import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../application/route/route_preferences_provider.dart';
import '../../../application/route/route_quote_provider.dart';
import '../../../application/route/waypoint_providers.dart';
import '../../../application/settings/saver_mode_provider.dart';
import '../../../design/tokens/mr_colors.dart';
import '../../../design/tokens/mr_theme.dart';
import '../../../domain/models/route_preferences.dart';
import '../../../domain/models/route_quote.dart';
import '../../../domain/models/waypoint.dart';
import '../../../domain/value_objects/app_location.dart';

/// Zentraler, nicht während der Fahrt bedienbarer Routen-Entwurf.
class RoutePlannerScreen extends ConsumerWidget {
  const RoutePlannerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preferences = ref.watch(routePreferencesProvider);
    final waypoints = ref.watch(waypointsProvider);
    final quote = ref.watch(routeQuoteProvider);
    final double directKm = _directDistanceKm(waypoints);
    return Scaffold(
      appBar: AppBar(title: const Text('Route planen')),
      body: ListView(padding: const EdgeInsets.all(MrSpacing.md), children: [
        const _SectionTitle('Fahrzeug'),
        Wrap(
          spacing: MrSpacing.sm,
          children: VehicleType.values.map((value) => ChoiceChip(
            label: Text(value.label),
            selected: preferences.vehicle == value,
            onSelected: (_) => ref.read(routePreferencesProvider.notifier).setVehicle(value),
          )).toList(),
        ),
        const SizedBox(height: MrSpacing.lg),
        const _SectionTitle('Streckencharakter'),
        Wrap(
          spacing: MrSpacing.sm,
          runSpacing: MrSpacing.sm,
          children: RideStyle.values.map((value) => ChoiceChip(
            label: Text(value.label),
            selected: preferences.rideStyle == value,
            onSelected: (_) => ref.read(routePreferencesProvider.notifier).setRideStyle(value),
          )).toList(),
        ),
        const SizedBox(height: MrSpacing.lg),
        const _SectionTitle('Vermeiden'),
        Wrap(
          spacing: MrSpacing.sm,
          runSpacing: MrSpacing.sm,
          children: RouteAvoidance.values.map((value) => FilterChip(
            label: Text(value.label),
            selected: preferences.avoidances.contains(value),
            onSelected: (_) => ref.read(routePreferencesProvider.notifier).toggleAvoidance(value),
          )).toList(),
        ),
        const SizedBox(height: MrSpacing.lg),
        const _SectionTitle('Route'),
        _RouteSummary(
          waypointCount: waypoints.length,
          directKm: directKm,
          quote: quote.valueOrNull,
          isLoading: quote.isLoading,
          failed: quote.hasError,
        ),
        const SizedBox(height: MrSpacing.lg),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Energiesparmodus'),
          subtitle: const Text('Reduziert Kartenbewegung und spätere Aktualisierungen in der Navigation.'),
          value: ref.watch(saverModeProvider),
          onChanged: ref.read(saverModeProvider.notifier).setEnabled,
        ),
        const SizedBox(height: MrSpacing.md),
        FilledButton.icon(
          onPressed: waypoints.length < 2 || quote.isLoading
              ? null
              : () => ref.read(routeQuoteProvider.notifier).calculate(waypoints, preferences),
          icon: const Icon(Icons.alt_route),
          label: const Text('Route berechnen'),
        ),
      ]),
    );
  }

  static double _directDistanceKm(List<Waypoint> points) {
    if (points.length < 2) return 0;
    double meters = 0;
    for (int index = 1; index < points.length; index += 1) {
      final previous = points[index - 1];
      final current = points[index];
      meters += AppLocation(latitude: previous.latitude, longitude: previous.longitude)
          .distanceToMeters(AppLocation(latitude: current.latitude, longitude: current.longitude));
    }
    return meters / 1000;
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: MrSpacing.sm),
        child: Text(text, style: MrTypography.title),
      );
}

class _RouteSummary extends StatelessWidget {
  const _RouteSummary({
    required this.waypointCount,
    required this.directKm,
    required this.quote,
    required this.isLoading,
    required this.failed,
  });
  final int waypointCount;
  final double directKm;
  final RouteQuote? quote;
  final bool isLoading;
  final bool failed;
  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(MrSpacing.md),
          child: waypointCount < 2
              ? const Text('Setze mindestens Start und Ziel auf der Karte.')
              : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('$waypointCount Wegpunkte', style: MrTypography.body),
                  const SizedBox(height: MrSpacing.xs),
                  Text(quote == null
                      ? '${directKm.toStringAsFixed(1)} km Luftlinie'
                      : '${(quote!.distanceMeters / 1000).toStringAsFixed(1)} km Fahrstrecke',
                      style: MrTypography.label.copyWith(color: MrColors.textSecondary)),
                  const SizedBox(height: MrSpacing.xs),
                  if (isLoading) const LinearProgressIndicator(),
                  if (quote != null)
                    Text(_duration(quote!.durationSeconds), style: MrTypography.label),
                  if (quote == null && !isLoading && !failed)
                    const Text('Fahrstrecke und Dauer erscheinen nach der Routing-Berechnung.',
                        style: MrTypography.label),
                  if (failed)
                    const Text('Routing-Dienst ist nicht erreichbar.',
                        style: TextStyle(color: MrColors.danger)),
                ]),
        ),
      );

  static String _duration(int seconds) {
    final int minutes = (seconds / 60).round();
    return minutes >= 60 ? '${minutes ~/ 60} h ${minutes % 60} min' : '$minutes min';
  }
}
