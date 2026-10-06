import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../application/location/location_providers.dart';
import '../../../design/tokens/mr_colors.dart';
import '../../../design/tokens/mr_theme.dart';
import '../../../domain/models/place.dart';
import '../../../infrastructure/geocoding/http_geocoding_repository.dart';

/// M2: Orts-, Adress- und POI-Suche. Das Resultat wird an die Karte zurückgegeben.
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

  @override
  Widget build(BuildContext context) => Scaffold(
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
                        onTap: () => Navigator.of(context).pop(place),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      );
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
