import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:motoroute_app/core/state/app_providers.dart';
import 'package:motoroute_app/core/theme/app_colors.dart';
import 'package:motoroute_app/core/theme/app_spacing.dart';
import 'package:motoroute_app/core/theme/app_typography.dart';
import 'package:motoroute_app/features/routing/domain/route_entities.dart';
import 'package:motoroute_app/features/search/search_providers.dart';

/// Screen 5: Zielsuche. Echt verdrahtet: Eingabe -> SearchController ->
/// Backend /v1/search -> Ergebnisliste. Unterstützt:
/// - Ortsuche nach Name ODER PLZ (nur-Ziffern-Eingabe wird als PLZ
///   interpretiert und so an den Geocoder durchgereicht; PLZ/Ort
///   erscheinen in der Ergebniszeile)
/// - "Als Wegpunkt hinzufügen"-Modus (via Route-Argument `addWaypoint`),
///   z. B. aus der Wegpunktverwaltung - das Ergebnis wird dann als
///   Zwischenziel in die Wegpunktliste eingereiht statt eine neue
///   Route zu starten
/// - Tap auf ein Ergebnis startet den normalen Routing-Flow (Screen 6)
class SearchScreen extends ConsumerStatefulWidget {
  /// Wenn true: Ergebnis als Zwischenziel anhängen statt Routing zu
  /// starten (verdrahtet mit Screen 9 "Wegpunkt hinzufügen").
  final bool addWaypointMode;

  const SearchScreen({super.key, this.addWaypointMode = false});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _queryController = TextEditingController();

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  void _submit(String value) {
    ref.read(searchControllerProvider.notifier).submit(value);
  }

  /// PLZ-Heuristik: 4-5 Ziffern (DE 5-stellig, AT/CH 4-stellig) ohne
  /// sonstige Zeichen -> Ortssuche statt Adressuche. Der Geocoder
  /// (Photon) matcht PLZ nativ über die postcode-Indizes.
  bool _looksLikePostcode(String value) =>
      RegExp(r'^\d{4,5}$').hasMatch(value.trim());

  void _selectResult(SearchResult result) {
    final destination = Waypoint(lat: result.lat, lng: result.lng, label: result.label);

    if (widget.addWaypointMode) {
      final waypoints = [...ref.read(waypointListProvider)];
      if (waypoints.length < 2) {
        // Noch keine Route: wie normales Ziel behandeln.
        waypoints
          ..clear()
          ..addAll([
            const Waypoint(lat: 48.1351, lng: 11.5820, label: 'München'),
            destination,
          ]);
      } else {
        // Als Zwischenziel VOR dem letzten Wegpunkt einreihen.
        waypoints.insert(waypoints.length - 1, destination);
      }
      ref.read(waypointListProvider.notifier).state = waypoints;
      Navigator.of(context).pushNamed('/waypoints');
      return;
    }

    final waypoints = ref.read(waypointListProvider);
    ref.read(waypointListProvider.notifier).state = [
      if (waypoints.isEmpty)
        const Waypoint(lat: 48.1351, lng: 11.5820, label: 'München')
      else
        waypoints.first,
      destination,
    ];
    Navigator.of(context).pushNamed(
      '/route-style',
      arguments: {
        'start': ref.read(waypointListProvider).first,
        'destination': destination,
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(searchControllerProvider);

    return Scaffold(
      backgroundColor: AppColors.bgBaseDark,
      appBar: AppBar(
        backgroundColor: AppColors.bgBaseDark,
        title: Text(
          widget.addWaypointMode ? 'Wegpunkt suchen' : 'Zielsuche',
          style: AppTypography.title,
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md),
              child: Container(
                height: AppSpacing.touchTargetPlanning,
                decoration: BoxDecoration(
                  color: AppColors.bgSurfaceDark,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.borderHairlineDark),
                ),
                child: TextField(
                  controller: _queryController,
                  autofocus: true,
                  keyboardType: TextInputType.streetAddress,
                  textInputAction: TextInputAction.search,
                  onSubmitted: _submit,
                  onChanged: (value) {
                    // Debounce: erst ab 3 Zeichen (oder vollständiger
                    // PLZ) und nach kurzer Tipppause suchen.
                    final v = value.trim();
                    if (v.length >= 3 || _looksLikePostcode(v)) {
                      Future.delayed(const Duration(milliseconds: 400), () {
                        if (mounted && _queryController.text.trim() == v) {
                          _submit(v);
                        }
                      });
                    }
                  },
                  style: AppTypography.body,
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                    prefixIcon:
                        const Icon(Icons.search, color: AppColors.textSecondaryDark),
                    suffixIcon: IconButton(
                      icon:
                          const Icon(Icons.close, color: AppColors.textSecondaryDark),
                      onPressed: () {
                        _queryController.clear();
                        ref.read(searchControllerProvider.notifier).submit('');
                      },
                    ),
                    hintStyle: AppTypography.caption,
                    hintText: 'Ort, PLZ oder POI suchen',
                  ),
                ),
              ),
            ),
            Expanded(
              child: _buildResults(state),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResults(SearchState state) {
    if (state.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off, color: AppColors.textMutedDark, size: 48),
            const SizedBox(height: AppSpacing.md),
            Text(state.error!, style: AppTypography.body),
            const SizedBox(height: AppSpacing.lg),
            OutlinedButton(
              onPressed: () => _submit(_queryController.text),
              child: const Text('Erneut versuchen'),
            ),
          ],
        ),
      );
    }
    if (!state.hasSearched) {
      return ListView(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        children: [
          Text('Zuletzt gesucht', style: AppTypography.caption),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Noch keine Suchanfragen in dieser Sitzung.',
            style:
                AppTypography.body.copyWith(color: AppColors.textSecondaryDark),
          ),
        ],
      );
    }
    if (state.results.isEmpty) {
      return Center(
        child: Text('Keine Treffer',
            style:
                AppTypography.body.copyWith(color: AppColors.textSecondaryDark)),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      itemCount: state.results.length,
      itemBuilder: (context, index) {
        final result = state.results[index];
        return ListTile(
          leading: Icon(
            result.isPoi ? Icons.place : Icons.location_city,
            color: AppColors.accentSecondary,
            size: 24,
          ),
          title: Text(result.label, style: AppTypography.bodyStrong),
          subtitle: Text(_subtitleFor(result), style: AppTypography.caption),
          onTap: () => _selectResult(result),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 0, vertical: AppSpacing.xs),
        );
      },
    );
  }

  String _subtitleFor(SearchResult result) {
    final parts = [
      if (result.postcode != null) result.postcode!,
      if (result.city != null) result.city!,
    ];
    if (parts.isNotEmpty) return parts.join(' ');
    return '${result.lat.toStringAsFixed(4)}, ${result.lng.toStringAsFixed(4)}';
  }
}
