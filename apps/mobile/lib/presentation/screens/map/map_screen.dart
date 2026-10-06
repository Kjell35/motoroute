import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../../../application/location/location_providers.dart';
import '../../../application/route/waypoint_providers.dart';
import '../../../application/settings/saver_mode_provider.dart';
import '../../../design/tokens/mr_colors.dart';
import '../../../design/tokens/mr_theme.dart';
import '../../../domain/models/place.dart';
import '../../../domain/models/waypoint.dart';
import '../../../domain/models/map_item.dart';
import '../../../infrastructure/map_data/http_map_data_repository.dart';
import '../../../domain/repositories/location_repository.dart';
import '../../../domain/services/camera_policy.dart';
import '../../../domain/value_objects/app_location.dart';
import 'widgets/grant_banner.dart';

/// Screen 4 (docs/06-ux-safety.md): Karte mit GPS-Follow (M1-Umfang).
///
/// M1-DoD (docs/09-mvp-plan.md): Position flüssig, Kamera folgt,
/// manueller Modus per Karte-Pan, Recenter-FAB.
class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key});

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> {
  static const double _followZoom = 15.5;

  MaplibreMapController? _controller;
  bool _styleLoaded = false;
  bool _pointerDown = false;
  double _panAccumulatedPx = 0;
  DateTime? _lastSaverCameraUpdate;
  final HttpMapDataRepository _mapDataRepository = HttpMapDataRepository();
  final List<Circle> _mapDataMarkers = [];
  DateTime? _lastMapDataLoad;

  @override
  Widget build(BuildContext context) {
    final CameraMode mode = ref.watch(cameraModeProvider);
    final LocationGrant? grant = ref.watch(locationGrantProvider);

    ref.listen<AsyncValue<AppLocation>>(locationStreamProvider,
        (AsyncValue<AppLocation>? _, AsyncValue<AppLocation> next) {
      next.whenData(_onLocation);
    });

    return Scaffold(
      backgroundColor: MrColors.base,
      body: Stack(
        children: [
          // Listener liegt ÜBER der Karte, konsumiert aber nichts:
          // Er misst Nutzer-Pans für die Kamera-Policy (docs/02-architecture.md §5).
          Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: (_) {
              _pointerDown = true;
              _panAccumulatedPx = 0;
            },
            onPointerMove: (PointerMoveEvent e) {
              if (_pointerDown) _panAccumulatedPx += e.delta.distance;
            },
            onPointerUp: (_) => _onPointerReleased(context),
            onPointerCancel: (_) => _onPointerReleased(context),
            child: MaplibreMap(
            styleString: 'assets/map-style/midnight-asphalt.json',
            initialCameraPosition: const CameraPosition(
              target: LatLng(48.1375, 11.5755),
              zoom: 10,
            ),
            // Der GPS-Fix steuert in M1 die Kamera. Ein Symbol-Layer für den
            // Positionspfeil folgt mit dem Navigationskern in M3.
            myLocationEnabled: false,
            compassEnabled: false,
            trackCameraPosition: true,
            onMapLongClick: (_, LatLng coordinates) => _addMapPin(coordinates),
            onMapCreated: (MaplibreMapController c) => _controller = c,
            onStyleLoadedCallback: () => setState(() => _styleLoaded = true),
          ),
          ),
          if (!_styleLoaded)
            const ColoredBox(
              color: MrColors.base,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: MrColors.accentPrimary),
                    SizedBox(height: MrSpacing.md),
                    Text('Karte wird geladen…', style: MrTypography.body),
                  ],
                ),
              ),
            ),
          Positioned(
            left: MrSpacing.md,
            right: MrSpacing.md,
            top: MediaQuery.paddingOf(context).top + MrSpacing.sm,
            child: _SearchButton(onTap: _openSearch),
          ),
          Positioned(
            right: MrSpacing.md,
            top: MediaQuery.paddingOf(context).top + 72,
            child: FloatingActionButton.small(
              heroTag: 'map-data',
              tooltip: 'Orte und Verkehr',
              backgroundColor: MrColors.card,
              foregroundColor: MrColors.textPrimary,
              onPressed: () => context.push('/map-data'),
              child: const Icon(Icons.layers_outlined),
            ),
          ),
          Positioned(
            right: MrSpacing.md,
            bottom: MrSpacing.xl,
            child: _RecenterFab(mode: mode, onTap: _onRecenterTap),
          ),
          if (ref.watch(waypointsProvider).isNotEmpty)
            Positioned(
              left: MrSpacing.md,
              bottom: MrSpacing.xl,
              child: _WaypointCountButton(
                count: ref.watch(waypointsProvider).length,
                onTap: () => _showWaypoints(context),
              ),
            ),
          if (ref.watch(waypointsProvider).length >= 2)
            Positioned(
              left: MrSpacing.md,
              right: MrSpacing.md,
              bottom: 104,
              child: FilledButton.icon(
                onPressed: () => context.push('/route'),
                icon: const Icon(Icons.alt_route),
                label: const Text('Route planen'),
              ),
            ),
          if (grant != null && grant != LocationGrant.granted)
            Positioned(
              left: MrSpacing.md,
              right: MrSpacing.md,
              top: MediaQuery.paddingOf(context).top + 72,
              child: GrantBanner(grant: grant),
            ),
        ],
      ),
    );
  }

  /// Nutzer-Geste beendet: Ab welcher Pan-Distanz gehen wir in den
  /// manuellen Modus? (CameraPolicy, domain-getrieben)
  void _onPointerReleased(BuildContext context) {
    _pointerDown = false;
    final double dpr = MediaQuery.devicePixelRatioOf(context);
    final double metersPerPixel =
        _approxMetersPerPixel(15.5) * dpr; // grob, reicht für Threshold
    final double panMeters = _panAccumulatedPx * metersPerPixel;
    final CameraDecision d = ref
        .read(cameraPolicyProvider)
        .onUserPan(panDistanceMeters: panMeters);
    ref.read(cameraModeProvider.notifier).apply(d);
  }

  /// Web-Mercator: Meter pro physikalischem Pixel bei gegebenem Zoom.
  static double _approxMetersPerPixel(double zoom) {
    const double earthCircumference = 40075016.686;
    const double tileSize = 512.0; // MapLibre nutzt 512er Tiles
    return earthCircumference / tileSize / _pow2(zoom);
  }

  static double _pow2(double x) => math.pow(2, x).toDouble();

  /// Kamera-Update pro Fix: folgt Position + geglätteter Richtung.
  void _onLocation(AppLocation loc) {
    if (!_styleLoaded ||
        _pointerDown || // während aktiver Geste nicht gegensteuern
        ref.read(cameraModeProvider) != CameraMode.follow) {
      return;
    }
    final MaplibreMapController? c = _controller;
    if (c == null) return;
    final DateTime now = DateTime.now();
    if (_lastMapDataLoad == null ||
        now.difference(_lastMapDataLoad!) > const Duration(minutes: 5)) {
      _lastMapDataLoad = now;
      unawaited(_refreshMapData(loc));
    }
    // Im Sparmodus wird die Karte maximal alle zwei Sekunden nachgeführt.
    // Die GPS-Daten selbst bleiben unverändert; nur Renderarbeit sinkt.
    if (ref.read(saverModeProvider) &&
        _lastSaverCameraUpdate != null &&
        now.difference(_lastSaverCameraUpdate!) < const Duration(seconds: 2)) {
      return;
    }
    _lastSaverCameraUpdate = now;

    final double? heading =
        ref.read(headingFilterProvider).push(loc.headingDegrees);

    c.moveCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: LatLng(loc.latitude, loc.longitude),
          zoom: _followZoom,
          bearing: heading ?? 0,
        ),
      ),
    );
  }

  Future<void> _refreshMapData(AppLocation location) async {
    try {
      final results = await Future.wait<Object>([
        _mapDataRepository.pois(
          latitude: location.latitude,
          longitude: location.longitude,
          categories: Set<PoiCategory>.from(PoiCategory.values),
        ),
        _mapDataRepository.traffic(
          latitude: location.latitude,
          longitude: location.longitude,
        ),
      ]);
      if (!mounted || _controller == null) return;
      final controller = _controller!;
      for (final marker in _mapDataMarkers) {
        await controller.removeCircle(marker);
      }
      _mapDataMarkers.clear();
      for (final poi in results[0] as List<MapPoi>) {
        _mapDataMarkers.add(await controller.addCircle(CircleOptions(
          geometry: LatLng(poi.latitude, poi.longitude),
          circleRadius: poi.category == PoiCategory.speedCamera ? 7 : 6,
          circleColor: poi.category == PoiCategory.speedCamera ? '#FF3B30' : '#3DD6C3',
          circleStrokeColor: '#0E1116',
          circleStrokeWidth: 2,
        )));
      }
      final traffic = results[1] as TrafficFeed;
      for (final incident in traffic.incidents) {
        _mapDataMarkers.add(await controller.addCircle(CircleOptions(
          geometry: LatLng(incident.latitude, incident.longitude),
          circleRadius: 8,
          circleColor: '#FFC53D',
          circleStrokeColor: '#0E1116',
          circleStrokeWidth: 2,
        )));
      }
    } catch (_) {
      // Die Karte bleibt voll nutzbar, wenn Datenanbieter temporär ausfallen.
    }
  }

  void _onRecenterTap() {
    final CameraDecision d = ref.read(cameraPolicyProvider).onRecenterTap();
    ref.read(cameraModeProvider.notifier).apply(d);
    ref.read(locationStreamProvider).whenData(_onLocation);
  }

  Future<void> _openSearch() async {
    final Place? place = await context.push<Place>('/search');
    if (place == null || !mounted) return;
    ref.read(waypointsProvider.notifier).addPlace(place);
    _controller?.animateCamera(
      CameraUpdate.newLatLngZoom(LatLng(place.latitude, place.longitude), 14),
    );
  }

  Future<void> _addMapPin(LatLng coordinates) async {
    Place place = Place(
      id: 'pin:${coordinates.latitude.toStringAsFixed(6)},${coordinates.longitude.toStringAsFixed(6)}',
      label: 'Karten-Pin',
      detail: '${coordinates.latitude.toStringAsFixed(5)}, ${coordinates.longitude.toStringAsFixed(5)}',
      latitude: coordinates.latitude,
      longitude: coordinates.longitude,
    );
    try {
      final Place? reverse = await ref
          .read(geocodingRepositoryProvider)
          .reverse(coordinates.latitude, coordinates.longitude);
      if (reverse != null) place = reverse;
    } catch (_) {
      // Der Pin bleibt auch ohne Netz nutzbar; das Label ist dann die Koordinate.
    }
    if (!mounted) return;
    final bool? add = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: MrColors.card,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(MrSpacing.md),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Route hierher?', style: MrTypography.title),
            const SizedBox(height: MrSpacing.sm),
            Text(place.label, style: MrTypography.body),
            if (place.detail != null) Text(place.detail!, style: MrTypography.label),
            const SizedBox(height: MrSpacing.md),
            FilledButton.icon(
              onPressed: () => Navigator.of(context).pop(true),
              icon: const Icon(Icons.add_location_alt_outlined),
              label: const Text('Als Wegpunkt hinzufügen'),
            ),
          ]),
        ),
      ),
    );
    if (add == true && mounted) ref.read(waypointsProvider.notifier).addPlace(place);
  }

  void _showWaypoints(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: MrColors.card,
      showDragHandle: true,
      builder: (_) => Consumer(
        builder: (context, ref, _) {
          final List<Waypoint> waypoints = ref.watch(waypointsProvider);
          return SafeArea(
            child: SizedBox(
              height: 360,
              child: Column(children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(MrSpacing.md, 0, MrSpacing.md, MrSpacing.sm),
                  child: Align(alignment: Alignment.centerLeft, child: Text('Routenentwurf', style: MrTypography.title)),
                ),
                Expanded(
                  child: ReorderableListView.builder(
                    itemCount: waypoints.length,
                    onReorder: (oldIndex, newIndex) {
                      if (newIndex > oldIndex) newIndex -= 1;
                      ref.read(waypointsProvider.notifier).move(oldIndex, newIndex);
                    },
                    itemBuilder: (context, index) {
                      final waypoint = waypoints[index];
                      return ListTile(
                        key: ValueKey(waypoint.id),
                        leading: CircleAvatar(
                          backgroundColor: MrColors.accentSecondary,
                          foregroundColor: MrColors.base,
                          child: Text('${index + 1}'),
                        ),
                        title: Text(waypoint.label),
                        subtitle: waypoint.detail == null ? null : Text(waypoint.detail!),
                        trailing: IconButton(
                          tooltip: 'Wegpunkt entfernen',
                          icon: const Icon(Icons.close),
                          onPressed: () => ref.read(waypointsProvider.notifier).removeAt(index),
                        ),
                      );
                    },
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.all(MrSpacing.md),
                  child: Text('Route über „Route planen“ berechnen.', style: MrTypography.label),
                ),
              ]),
            ),
          );
        },
      ),
    );
  }
}

class _SearchButton extends StatelessWidget {
  const _SearchButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: 'Ziel suchen',
        child: Material(
          color: MrColors.card,
          borderRadius: BorderRadius.circular(MrRadii.button),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(MrRadii.button),
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: MrSpacing.md, vertical: 16),
              child: Row(children: [
                Icon(Icons.search, color: MrColors.accentPrimary),
                SizedBox(width: MrSpacing.sm),
                Text('Ziel suchen', style: MrTypography.body),
              ]),
            ),
          ),
        ),
      );
}

class _WaypointCountButton extends StatelessWidget {
  const _WaypointCountButton({required this.count, required this.onTap});
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => FilledButton.icon(
        onPressed: onTap,
        icon: const Icon(Icons.alt_route),
        label: Text('$count ${count == 1 ? 'Wegpunkt' : 'Wegpunkte'}'),
      );
}

class _RecenterFab extends StatelessWidget {
  const _RecenterFab({required this.mode, required this.onTap});

  final CameraMode mode;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bool following = mode == CameraMode.follow;
    return FloatingActionButton.large(
      heroTag: 'recenter',
      backgroundColor: following ? MrColors.accentPrimary : MrColors.raised,
      foregroundColor: following ? MrColors.base : MrColors.textPrimary,
      shape: const CircleBorder(),
      onPressed: onTap,
      child: Icon(following ? Icons.gps_fixed : Icons.gps_not_fixed, size: 32),
    );
  }
}
