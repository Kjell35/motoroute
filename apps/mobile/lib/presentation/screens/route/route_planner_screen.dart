import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

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
import '../../../domain/models/place.dart';
import '../../../infrastructure/pairing/http_pairing_repository.dart';
import '../../../infrastructure/pois/http_poi_repository.dart';
import 'computer_planning_sheet.dart';

/// Zentraler, nicht während der Fahrt bedienbarer Routen-Entwurf.
///
/// M3-Komfort: Start → Ziel als direkte, antippbare Zeile (Trennung + Swap) —
/// der häufigste Fall ist Start/Ziel setzen, nicht Umwege pflegen. Waypoints
/// darunter als kompakte Chips. „Route berechnen“-Ergebnis zeigt direkt den
/// nächsten Schritt („Route zeigen“ zurück zur Karte).
class RoutePlannerScreen extends ConsumerWidget {
  const RoutePlannerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preferences = ref.watch(routePreferencesProvider);
    final waypoints = ref.watch(waypointsProvider);
    final quote = ref.watch(routeQuoteProvider);
    final double directKm = _directDistanceKm(waypoints);
    final Waypoint? start = waypoints.isNotEmpty ? waypoints.first : null;
    final Waypoint? destination =
        waypoints.length >= 2 ? waypoints.last : null;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Route planen'),
        actions: [
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
        _EndpointRow(
          start: start,
          destination: destination,
          canSwap: waypoints.length >= 2,
          onSwap: () => ref.read(waypointsProvider.notifier).swapStartDestination(),
          onStartTap: () => context.push('/search?target=start'),
          onDestinationTap: () => context.push('/search?target=destination'),
          onRemoveStart: () => ref.read(waypointsProvider.notifier).removeAt(0),
          onRemoveDestination: () =>
              ref.read(waypointsProvider.notifier).removeAt(waypoints.length - 1),
        ),
        if (waypoints.length > 2) ...[
          const SizedBox(height: MrSpacing.lg),
          const _SectionTitle('Unterwegs'),
          _WaypointChips(
            waypoints: waypoints.sublist(1, waypoints.length - 1),
            onRemove: (int index) =>
                ref.read(waypointsProvider.notifier).removeAt(index),
          ),
        ],
        const SizedBox(height: MrSpacing.lg),
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
        // Stopps bequem einfügen: Tankstelle, Motorradhotel, Camping, Eis.
        // Sucht POIs entlang der direkten Linie Start↔Ziel (±4 km) und fügt
        // per Auswahl als nächsten freien Zwischenpunkt ein.
        _StopsSection(hasStartAndEnd: waypoints.length >= 2),
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
        const SizedBox(height: MrSpacing.sm),
        // Nach einer erfolgreichen Berechnung ist der logische nächste Schritt
        // die Vorschau auf der Karte — nicht ein leerer Screen.
        if (quote.valueOrNull != null)
          FilledButton.tonalIcon(
            onPressed: () => context.go('/'),
            icon: const Icon(Icons.map_outlined),
            label: const Text('Route auf Karte ansehen'),
          ),
      ]),
    );
  }

  /// „Route am Computer planen“: Token holen, QR-Code+Link im Dialog zeigen,
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

/// Start → Ziel als antippbare Doppelzeile. Leere Seiten laden die Suche;
/// gefüllte zeigen Name + Detail + plumpe Löschen-Aktion.
class _EndpointRow extends StatelessWidget {
  const _EndpointRow({
    required this.start,
    required this.destination,
    required this.canSwap,
    required this.onSwap,
    required this.onStartTap,
    required this.onDestinationTap,
    required this.onRemoveStart,
    required this.onRemoveDestination,
  });

  final Waypoint? start;
  final Waypoint? destination;
  final bool canSwap;
  final VoidCallback onSwap;
  final VoidCallback onStartTap;
  final VoidCallback onDestinationTap;
  final VoidCallback onRemoveStart;
  final VoidCallback onRemoveDestination;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(MrSpacing.md),
          child: Column(children: [
            _EndpointTile(
              icon: Icons.trip_origin,
              placeholder: 'Start setzen',
              waypoint: start,
              onTap: onStartTap,
              onClear: start == null ? null : onRemoveStart,
            ),
            _SwapDivider(canSwap: canSwap, onSwap: onSwap),
            _EndpointTile(
              icon: Icons.flag_outlined,
              placeholder: 'Ziel setzen',
              waypoint: destination,
              onTap: onDestinationTap,
              onClear: destination == null ? null : onRemoveDestination,
            ),
          ]),
        ),
      );
}

class _EndpointTile extends StatelessWidget {
  const _EndpointTile({
    required this.icon,
    required this.placeholder,
    required this.waypoint,
    required this.onTap,
    required this.onClear,
  });

  final IconData icon;
  final String placeholder;
  final Waypoint? waypoint;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final bool filled = waypoint != null;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      onTap: onTap,
      leading: Icon(icon, color: filled ? MrColors.accentPrimary : MrColors.textSecondary),
      title: Text(
        filled ? waypoint!.label : placeholder,
        style: MrTypography.body.copyWith(
          color: filled ? MrColors.textPrimary : MrColors.textSecondary,
        ),
      ),
      subtitle: filled ? Text(waypoint!.detail ?? '', maxLines: 1, overflow: TextOverflow.ellipsis) : null,
      trailing: onClear == null
          ? const Icon(Icons.edit, size: 18, color: MrColors.textSecondary)
          : IconButton(icon: const Icon(Icons.close, size: 18), onPressed: onClear, tooltip: 'Entfernen'),
    );
  }
}

class _SwapDivider extends StatelessWidget {
  const _SwapDivider({required this.canSwap, required this.onSwap});
  final bool canSwap;
  final VoidCallback onSwap;

  @override
  Widget build(BuildContext context) => Row(children: [
        const Expanded(child: Divider()),
        IconButton(
          tooltip: 'Start und Ziel tauschen',
          onPressed: canSwap ? onSwap : null,
          icon: const Icon(Icons.swap_vert),
        ),
        const Expanded(child: Divider()),
      ]);
}

class _WaypointChips extends StatelessWidget {
  const _WaypointChips({required this.waypoints, required this.onRemove});
  final List<Waypoint> waypoints;
  final ValueChanged<int> onRemove;

  @override
  Widget build(BuildContext context) => Wrap(
        spacing: MrSpacing.sm,
        runSpacing: MrSpacing.sm,
        children: [
          for (int index = 0; index < waypoints.length; index += 1)
            InputChip(
              avatar: Text('${index + 1}'),
              label: Text(waypoints[index].label),
              onDeleted: () => onRemove(index + 1), // +1: Start ist 0
            ),
        ],
      );
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
              ? const Text('Setze Start und Ziel — hier oder auf der Karte (Langes Tippen).')
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


/// POI-Zwischenstopp-Sektion: Kategorie wählen → Liste laden → antippen fügt
/// den Stopp in den Routenentwurf. Aktiver Radius ist die BBox um Start+Ziel.
class _StopsSection extends StatelessWidget {
  const _StopsSection({required this.hasStartAndEnd});
  final bool hasStartAndEnd;

  static final PoiRepository _repository = PoiRepository();

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const _SectionTitle('Zwischenstopp einfügen'),
        Wrap(
          spacing: MrSpacing.sm,
          runSpacing: MrSpacing.sm,
          children: [
            for (final StopCategory category in StopCategory.values)
              ActionChip(
                avatar: const Icon(Icons.local_convenience_store_outlined, size: 18),
                label: Text(category.label),
                onPressed: !hasStartAndEnd
                    ? null
                    : () => _pickStop(context, category),
              ),
          ],
        ),
        if (!hasStartAndEnd)
          const Padding(
            padding: EdgeInsets.only(top: MrSpacing.xs),
            child: Text('Setze erst Start und Ziel, dann suche ich Stopps dazwischen.',
                style: MrTypography.label),
          ),
      ]);

  Future<void> _pickStop(BuildContext context, StopCategory category) async {
    final List<Waypoint> waypoints = ProviderScope.containerOf(context).read(waypointsProvider);
    if (waypoints.length < 2) return;
    final double south = waypoints.map((p) => p.latitude).reduce((a, b) => a < b ? a : b);
    final double north = waypoints.map((p) => p.latitude).reduce((a, b) => a > b ? a : b);
    final double west = waypoints.map((p) => p.longitude).reduce((a, b) => a < b ? a : b);
    final double east = waypoints.map((p) => p.longitude).reduce((a, b) => a > b ? a : b);

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: MrColors.card,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => _StopPickerSheet(
        category: category,
        repository: _repository,
        south: south, west: west, north: north, east: east,
      ),
    );
  }
}

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
