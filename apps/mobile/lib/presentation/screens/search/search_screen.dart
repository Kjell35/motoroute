import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../application/location/location_providers.dart';
import '../../../application/route/recent_places_provider.dart';
import '../../../application/route/waypoint_providers.dart';
import '../../../design/tokens/mr_colors.dart';
import '../../../design/tokens/mr_theme.dart';
import '../../../domain/models/place.dart';
import '../../../infrastructure/geocoding/http_geocoding_repository.dart';

/// M2: Orts-, Adress- und POI-Suche.
///
/// Nutzer-Fluss (M3-Komfort): Treffer antippen → Weminü-Auswahl
/// „Ziel · Start · Unterwegs“ – kein Umweg über die Karte nötig.
/// Verlauf (letzte Ziele) erscheint im Leerzustand.
enum _PlaceTarget { destination, start, intermediate }

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final TextEditingController _query = TextEditingController();
  Timer? _debounce;
  List<Place> _places = const [];
  String? _error;
  bool _loading = false;

  /// Vorauswahl aus dem Route-Screen ('start' / 'destination'):
  /// Wird direkt als Standard im Auswahl-Sheet vorbereitet (heetlet: Ziel).
  String? _defaultTargetHint;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final Map<String, String> params = GoRouterState.of(context).uri.queryParameters;
    final String? hint = params['target'];
    if (hint != _defaultTargetHint) {
      _defaultTargetHint = hint;
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  void _onChanged(String query) {
    _debounce?.cancel();
    if (query.trim().length < 2) {
      setState(() {
        _places = const [];
        _error = null;
        _loading = false;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 350), () => _search(query.trim()));
  }

  Future<void> _search(String query) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // Die aktuelle Position ist nur ein flüchtiger Bias für bessere Treffer;
      // sie wird weder gespeichert noch an einen fremden Dienst gesendet.
      final location = ref.read(locationStreamProvider).valueOrNull;
      final places = await ref.read(geocodingRepositoryProvider).search(
            query,
            latitude: location?.latitude,
            longitude: location?.longitude,
          );
      if (!mounted || _query.text.trim() != query) return;
      setState(() => _places = places);
    } on GeocodingException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted && _query.text.trim() == query) setState(() => _loading = false);
    }
  }

  /// Treffer in den Routenentwurf übernehmen.
  ///
  /// Wenn vom Route-Screen mit `?target=start`/`destination` geöffnet, wird
  /// das gewünschte Ziel DIREKT verwendet (Sheet nur bei Mehrdeutigkeit).
  Future<void> _choosePlace(Place place) async {
    _PlaceTarget? directTarget;
    switch (_defaultTargetHint) {
      case 'start':
        directTarget = _PlaceTarget.start;
        break;
      case 'destination':
        directTarget = _PlaceTarget.destination;
        break;
    }
    final _PlaceTarget? target = directTarget ??
        await showModalBottomSheet<_PlaceTarget>(
      context: context,
      backgroundColor: MrColors.card,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.all(MrSpacing.md),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(place.label, style: MrTypography.title),
              if (place.detail != null)
                Text(place.detail!, style: MrTypography.label.copyWith(color: MrColors.textSecondary)),
            ]),
          ),
          ListTile(
            leading: const Icon(Icons.flag_outlined, color: MrColors.accentPrimary),
            title: const Text('Als Ziel'),
            onTap: () => Navigator.of(sheetContext).pop(_PlaceTarget.destination),
          ),
          ListTile(
            leading: const Icon(Icons.trip_origin, color: MrColors.accentPrimary),
            title: const Text('Als Start'),
            onTap: () => Navigator.of(sheetContext).pop(_PlaceTarget.start),
          ),
          ListTile(
            leading: const Icon(Icons.more_vert, color: MrColors.accentPrimary),
            title: const Text('Als Zwischenziel'),
            onTap: () => Navigator.of(sheetContext).pop(_PlaceTarget.intermediate),
          ),
        ]),
      ),
    );
    if (target == null || !mounted) return;
    final notifier = ref.read(waypointsProvider.notifier);
    switch (target) {
      case _PlaceTarget.destination:
        notifier.setDestination(place);
        break;
      case _PlaceTarget.start:
        notifier.setStart(place);
        break;
      case _PlaceTarget.intermediate:
        notifier.addIntermediate(place);
        break;
    }
    await ref.read(recentPlacesProvider.notifier).push(place);
    if (!mounted) return;
    // Wieder auf der Karte landen; dort zeigen die Wegpunkt-CTAs den Entwurf.
    context.go('/');
  }

  @override
  Widget build(BuildContext context) {
    final List<Place> recents = ref.watch(recentPlacesProvider);
    final bool showRecents = _query.text.trim().length < 2 && _places.isEmpty && recents.isNotEmpty;
    return Scaffold(
      appBar: AppBar(title: const Text('Ziel suchen')),
      body: Padding(
        padding: const EdgeInsets.all(MrSpacing.md),
        child: Column(
          children: [
            TextField(
              controller: _query,
              autofocus: true,
              onChanged: _onChanged,
              onSubmitted: (query) {
                _debounce?.cancel();
                if (query.trim().length >= 2) _search(query.trim());
              },
              textInputAction: TextInputAction.search,
              style: MrTypography.body.copyWith(color: MrColors.textPrimary),
              decoration: InputDecoration(
                hintText: 'Ort, Adresse oder POI',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _loading
                    ? const Padding(
                        padding: EdgeInsets.all(14),
                        child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator()),
                      )
                    : null,
                filled: true,
                fillColor: MrColors.raised,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(MrRadii.button),
                  borderSide: const BorderSide(color: MrColors.stroke),
                ),
              ),
            ),
            const SizedBox(height: MrSpacing.md),
            if (_error != null)
              _SearchMessage(icon: Icons.cloud_off_outlined, message: _error!)
            else if (showRecents) ..._recentsSection(recents)
            else if (_query.text.trim().length < 2)
              const _SearchMessage(icon: Icons.route_outlined, message: 'Wohin soll die Tour gehen?')
            else if (!_loading && _places.isEmpty)
              const _SearchMessage(icon: Icons.search_off_outlined, message: 'Keine passenden Orte gefunden.')
            else
              Expanded(
                child: ListView.separated(
                  itemCount: _places.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final place = _places[index];
                    return ListTile(
                      minVerticalPadding: MrSpacing.sm,
                      leading: const CircleAvatar(
                        backgroundColor: MrColors.raised,
                        foregroundColor: MrColors.accentSecondary,
                        child: Icon(Icons.place_outlined),
                      ),
                      title: Text(place.label),
                      subtitle: place.detail == null ? null : Text(place.detail!),
                      onTap: () => _choosePlace(place),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  List<Widget> _recentsSection(List<Place> recents) => [
        Padding(
          padding: const EdgeInsets.only(top: MrSpacing.sm, bottom: MrSpacing.xs),
          child: Row(children: [
            const Expanded(child: Align(
              alignment: Alignment.centerLeft,
              child: Text('Letzte Ziele', style: MrTypography.title),
            )),
            TextButton(
              onPressed: () => ref.read(recentPlacesProvider.notifier).clear(),
              child: const Text('Verlauf löschen'),
            ),
          ]),
        ),
        Expanded(
          child: ListView.separated(
            itemCount: recents.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final place = recents[index];
              return ListTile(
                minVerticalPadding: MrSpacing.sm,
                leading: const CircleAvatar(
                  backgroundColor: MrColors.raised,
                  foregroundColor: MrColors.accentSecondary,
                  child: Icon(Icons.history),
                ),
                title: Text(place.label),
                subtitle: place.detail == null ? null : Text(place.detail!),
                onTap: () => _choosePlace(place),
              );
            },
          ),
        ),
      ];
}

class _SearchMessage extends StatelessWidget {
  const _SearchMessage({required this.icon, required this.message});
  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) => Expanded(
        child: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 42, color: MrColors.textSecondary),
            const SizedBox(height: MrSpacing.sm),
            Text(message, style: MrTypography.body.copyWith(color: MrColors.textSecondary)),
          ]),
        ),
      );
}
