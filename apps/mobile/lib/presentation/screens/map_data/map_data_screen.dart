import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../application/location/location_providers.dart';
import '../../../design/tokens/mr_colors.dart';
import '../../../design/tokens/mr_theme.dart';
import '../../../domain/models/map_item.dart';
import '../../../infrastructure/map_data/http_map_data_repository.dart';

class MapDataScreen extends ConsumerStatefulWidget {
  const MapDataScreen({super.key});
  @override
  ConsumerState<MapDataScreen> createState() => _MapDataScreenState();
}

class _MapDataScreenState extends ConsumerState<MapDataScreen> {
  final HttpMapDataRepository _repository = HttpMapDataRepository();
  Set<PoiCategory> _categories = Set<PoiCategory>.from(PoiCategory.values);
  Future<_MapData>? _data;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() => setState(() => _data = _load());

  Future<_MapData> _load() async {
    final location = await ref.read(locationStreamProvider.future);
    final results = await Future.wait([
      _repository.pois(
        latitude: location.latitude,
        longitude: location.longitude,
        categories: _categories,
      ),
      _repository.traffic(latitude: location.latitude, longitude: location.longitude),
    ]);
    return _MapData(results[0] as List<MapPoi>, results[1] as TrafficFeed);
  }

  @override
  Widget build(BuildContext context) => DefaultTabController(
        length: 2,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Karte & Verkehr'),
            bottom: const TabBar(tabs: [Tab(text: 'Orte'), Tab(text: 'Verkehr')]),
            actions: [IconButton(onPressed: _reload, icon: const Icon(Icons.refresh), tooltip: 'Aktualisieren')],
          ),
          body: FutureBuilder<_MapData>(
            future: _data,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError || !snapshot.hasData) {
                return const Center(child: Text('Kartendaten sind momentan nicht erreichbar.'));
              }
              final data = snapshot.data!;
              return TabBarView(children: [
                _PoiTab(
                  categories: _categories,
                  pois: data.pois,
                  onToggle: (category) {
                    setState(() {
                      _categories.contains(category) ? _categories.remove(category) : _categories.add(category);
                    });
                    _reload();
                  },
                ),
                _TrafficTab(feed: data.traffic),
              ]);
            },
          ),
        ),
      );
}

class _PoiTab extends StatelessWidget {
  const _PoiTab({required this.categories, required this.pois, required this.onToggle});
  final Set<PoiCategory> categories;
  final List<MapPoi> pois;
  final ValueChanged<PoiCategory> onToggle;

  @override
  Widget build(BuildContext context) => Column(children: [
        Padding(
          padding: const EdgeInsets.all(MrSpacing.sm),
          child: Wrap(
            spacing: MrSpacing.xs,
            children: PoiCategory.values.map((category) => FilterChip(
              label: Text(category.label),
              selected: categories.contains(category),
              onSelected: (_) => onToggle(category),
            )).toList(),
          ),
        ),
        Expanded(
          child: pois.isEmpty
              ? const Center(child: Text('Keine Orte im aktuellen Umkreis.'))
              : ListView.separated(
                  itemCount: pois.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, index) => ListTile(
                    leading: const Icon(Icons.place_outlined, color: MrColors.accentSecondary),
                    title: Text(pois[index].name),
                    subtitle: Text(pois[index].category.label),
                  ),
                ),
        ),
      ]);
}

class _TrafficTab extends StatelessWidget {
  const _TrafficTab({required this.feed});
  final TrafficFeed feed;
  @override
  Widget build(BuildContext context) => Column(children: [
        Container(
          width: double.infinity,
          color: feed.realTime ? MrColors.accentSecondary : MrColors.warning,
          padding: const EdgeInsets.all(MrSpacing.sm),
          child: Text(feed.realTime ? 'Live: ${feed.source}' : 'Nicht live: ${feed.source}'),
        ),
        Expanded(
          child: feed.incidents.isEmpty
              ? const Center(child: Text('Keine Meldungen im aktuellen Umkreis.'))
              : ListView.builder(
                  itemCount: feed.incidents.length,
                  itemBuilder: (_, index) => ListTile(
                    leading: const Icon(Icons.warning_amber_rounded, color: MrColors.warning),
                    title: Text(feed.incidents[index].name),
                    subtitle: Text(feed.incidents[index].type),
                  ),
                ),
        ),
      ]);
}

class _MapData {
  const _MapData(this.pois, this.traffic);
  final List<MapPoi> pois;
  final TrafficFeed traffic;
}
