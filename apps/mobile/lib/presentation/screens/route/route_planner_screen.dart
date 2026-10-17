import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../application/route/route_preferences_provider.dart';
import '../../../application/route/route_quote_provider.dart';
import '../../../application/route/waypoint_providers.dart';
import '../../../application/settings/saver_mode_provider.dart';
import '../../../design/tokens/mr_colors.dart';
import '../../../design/tokens/mr_theme.dart';
import '../../../domain/models/place.dart';
import '../../../domain/models/route_preferences.dart';
import '../../../domain/models/route_quote.dart';
import '../../../domain/models/waypoint.dart';
import '../../../domain/value_objects/app_location.dart';
import '../../../infrastructure/pairing/http_pairing_repository.dart';
import '../../../infrastructure/pois/http_poi_repository.dart';
import 'computer_planning_sheet.dart';

/// Zentraler, nicht während der Fahrt bedienbarer Routen-Entwurf.
///
/// Optik wie M0–M2 (Chips + Route-Card + „Route berechnen"); die M3-Funktionen
/// (Computer-Planung, POI-Zwischenstopps, Entwurf leeren) sind kompakt in der
/// App-Bar untergebracht, ohne das vertraute Bild zu verändern.
class RoutePlannerScreen extends ConsumerWidget {
  const RoutePlannerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preferences = ref.watch(routePreferencesProvider);
    final waypoints = ref.watch(waypointsProvider);
    final quote = ref.watch(routeQuoteProvider);
    final double directKm = _directDistanceKm(waypoints);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Route planen'),
        actions: [
          IconButton(
            tooltip: 'Zwischenstopp suchen (Tankstelle, Hotel, …)',
            icon: const Icon(Icons.local_convenience_store_outlined),
            onPressed: () => _pickStopCategory(context, ref),
          ),
          IconButton(
            tooltip: 'Route am Computer planen',
            icon: const Icon(Icons.computer_outlined),
            onPressed: () => _showComputerPlanning(context),
          ),
          if (waypoints.isNotEmpty)
            IconButton(
              tooltip: 'Routenentwurf leeren',
              icon: const Icon(Icons.delete_sweep_outlined),
              onPressed: () => _confirmClear(context, ref),
            ),
        ],
      ),
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

  /// „Route am Computer planen": Token holen, QR-Code+Link im Dialog zeigen,
  /// und einen Poll-Button, der den Plan vom Backend übernimmt.
  void _showComputerPlanning(BuildContext context) {
    final PairingRepository repository = PairingRepository();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: MrColors.card,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => ComputerPlanningSheet(repository: repository),
    );
  }

  /// POI-Zwischenstopp: erst Kategorie wählen (App-Bar-Zugang), dann die
  /// Stopps entlang der BBox Start↔Ziel durchsuchen wie in der M3-Version.
  void _pickStopCategory(BuildContext context, WidgetRef ref) {
    if (ref.read(waypointsProvider).length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Setze erst Start und Ziel, dann suche ich Stopps dazwischen.')),
      );
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: MrColors.card,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.all(MrSpacing.md),
            child: Text('Zwischenstopp einfügen', style: MrTypography.title),
          ),
          for (final StopCategory category in StopCategory.values)
            ListTile(
              leading: const Icon(
                Icons.local_convenience_store_outlined,
                color: MrColors.accentSecondary,
              ),
              title: Text(category.label),
              trailing: const Icon(Icons.add),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _pickStop(context, ref, category);
              },
            ),
        ]),
      ),
    );
  }

  Future<void> _pickStop(BuildContext context, WidgetRef ref, StopCategory category) async {
    final List<Waypoint> waypoints = ref.read(waypointsProvider);
    if (waypoints.length < 2) return;
    final double south = waypoints.map((p) => p.latitude).reduce((a, b) => a < b ? a : b);
    final double north = waypoints.map((p) => p.latitude).reduce((a, b) => a > b ? a : b);
    final double west = waypoints.map((p) => p.longitude).reduce((a, b) => a < b ? a : b);
    final double east = waypoints.map((p) => p.longitude).reduce((a, b) => a > b ? a : b);

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: MrColors.card,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => _StopPickerSheet(
        category: category,
        repository: PoiRepository(),
        south: south, west: west, north: north, east: east,
      ),
    );
  }

  void _confirmClear(BuildContext context, WidgetRef ref) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: MrColors.card,
        title: const Text('Routenentwurf leeren?'),
        content: const Text('Alle Start-, Ziel- und Zwischenpunkte werden entfernt.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Abbrechen')),
          FilledButton(
            onPressed: () {
              ref.read(waypointsProvider.notifier).clear();
              Navigator.of(dialogContext).pop();
            },
            child: const Text('Leeren'),
          ),
        ],
      ),
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

/// POI-Stopp-Auswahl (über die App-Bar erreicht): Liste laden → antippen fügt
/// den Stopp in den Routenentwurf. Aktiver Radius ist die BBox um Start+Ziel.
class _StopPickerSheet extends StatefulWidget {
  const _StopPickerSheet({
    required this.category,
    required this.repository,
    required this.south,
    required this.west,
    required this.north,
    required this.east,
  });

  final StopCategory category;
  final PoiRepository repository;
  final double south, west, north, east;

  @override
  State<_StopPickerSheet> createState() => _StopPickerSheetState();
}

class _StopPickerSheetState extends State<_StopPickerSheet> {
  List<Place>? _places;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final places = await widget.repository.nearby(
        south: widget.south, west: widget.west, north: widget.north, east: widget.east,
        categories: {widget.category},
      );
      if (!mounted) return;
      setState(() => _places = places);
    } on PoiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SizedBox(
        height: 420,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.all(MrSpacing.md),
            child: Text('${widget.category.label} als Zwischenstopp', style: MrTypography.title),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(MrSpacing.md),
              child: Text(_error!, style: MrTypography.label.copyWith(color: MrColors.danger)),
            )
          else if (_places == null)
            const Padding(
              padding: EdgeInsets.all(MrSpacing.md),
              child: LinearProgressIndicator(),
            )
          else if (_places!.isEmpty)
            const Padding(
              padding: EdgeInsets.all(MrSpacing.md),
              child: Text('Nichts gefunden — probier eine größere Tour oder eine andere Kategorie.',
                  style: MrTypography.label),
            )
          else
            Expanded(
              child: ListView.builder(
                itemCount: _places!.length,
                itemBuilder: (context, index) {
                  final place = _places![index];
                  return ListTile(
                    leading: const Icon(Icons.local_convenience_store_outlined,
                        color: MrColors.accentSecondary),
                    title: Text(place.label),
                    subtitle: place.detail == null ? null : Text(place.detail!),
                    trailing: const Icon(Icons.add),
                    onTap: () {
                      ProviderScope.containerOf(context)
                          .read(waypointsProvider.notifier)
                          .addIntermediate(place);
                      Navigator.of(context).pop();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('${place.label} als Stopp eingefügt.')),
                      );
                    },
                  );
                },
              ),
            ),
        ]),
      ),
    );
  }
}
