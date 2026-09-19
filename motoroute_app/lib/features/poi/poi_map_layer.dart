import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:motoroute_app/core/state/app_providers.dart';
import 'package:motoroute_app/features/poi/biker_poi_sync.dart';
import 'package:motoroute_app/features/poi/poi_providers.dart';

/// Rendert POIs als Kreise auf der Karte und lädt den Layer nach, wenn
/// sich der Kartenausschnitt oder die aktiven Kategorien ändern.
///
/// Design-Entscheidungen:
/// - Kreise statt Icons: maplibre_gl braucht für Icons Asset-Bundles;
///   Kreise sind farbcodiert sofort lesbar und brauchen keine Assets
///   (eigener Icon-Satz ist Phase-3-Feinschliff).
/// - Viewport-basiertes Nachladen mit Mindest-Abstand (5 s): ohne
///   Drosselung würde jedes Kartenschubsen einen Backend-/Overpass-
///   Request auslösen.
class PoiMapLayer {
  final MaplibreMapController? Function() _controllerGetter;

  static const _maxCircles = 200;

  final Map<String, Circle> _circles = {};
  final Map<String, Poi> _poisById = {};
  LatLngBounds? _lastLoadedBounds;
  DateTime _lastLoad = DateTime.fromMillisecondsSinceEpoch(0);
  Set<PoiCategory> _lastCategories = {};

  PoiMapLayer(this._controllerGetter);

  void dispose() {
    _circles.clear();
    _poisById.clear();
    _lastLoadedBounds = null;
  }

  /// Wird vom Kartenscreen nach Karten-Bewegung aufgerufen.
  Future<void> onCameraIdle(WidgetRef ref) async {
    final controller = _controllerGetter();
    if (controller == null) return;
    try {
      final bounds = await controller.getVisibleRegion();
      await refresh(ref, bounds);
    } catch (_) {
      // Karte noch nicht bereit - nächster Versuch tut es erneut.
    }
  }

  /// Lädt POIs für den Ausschnitt neu - mit Drosselung.
  Future<void> refresh(WidgetRef ref, LatLngBounds bounds) async {
    final controller = _controllerGetter();
    if (controller == null) return;

    final categories = ref.read(activePoiCategoriesProvider);
    if (categories.isEmpty) {
      await _clear();
      return;
    }

    final now = DateTime.now();
    final sameCategories = categories.difference(_lastCategories).isEmpty &&
        _lastCategories.difference(categories).isEmpty;
    final sameArea =
        _lastLoadedBounds != null && _containsBounds(_lastLoadedBounds!, bounds);
    final tooSoon = now.difference(_lastLoad) < const Duration(seconds: 5);

    if (sameCategories && sameArea && tooSoon) return;

    _lastCategories = Set.of(categories);
    _lastLoad = now;
    _lastLoadedBounds = bounds;

    try {
      final pois = await ref.read(poiRepositoryProvider).fetchInBoundingBox(
            minLng: bounds.southwest.longitude,
            minLat: bounds.southwest.latitude,
            maxLng: bounds.northeast.longitude,
            maxLat: bounds.northeast.latitude,
            categories: categories,
          );
      // MERGE mit dem Biker-POI-Delta-Sync (motoroute_poi_service):
      // gecachte kuratierte POIs im Viewport ergänzen die OSM-Live-
      // Abfrage. Der Sync-Controller liefert eine leere Liste, wenn der
      // Dienst nicht konfiguriert ist - der Merge ist dann ein No-Op.
      final bikerPois = ref
          .read(bikerPoiSyncProvider)
          .pois
          .where((p) => categories.contains(p.category))
          .where((p) => _inBounds(p, bounds))
          .toList();
      final List<Poi> combined = [...bikerPois, ...pois];
      _poisById
        ..clear()
        ..addEntries(combined.map((p) => MapEntry(p.id, p)));
      // Fehler-/Ladezustand auch dem Layer-Controller spiegeln, damit
      // z. B. eine Statusanzeige im Screen darauf reagieren kann.
      ref.read(poiLayerControllerProvider.notifier).adoptMerged(
            osmPois: pois,
            bikerPois: bikerPois,
          );
      await _render(combined);
    } catch (e) {
      ref
          .read(poiLayerControllerProvider.notifier)
          .reportError('POIs nicht verfügbar');
    }
  }

  /// Sofortige Übernahme gepushter Biker-POIs (bikerpoi.batch über die
  /// App-WebSocket): liest den AKTUELLEN Sync-State, merged mit den
  /// bereits geladenen OSM-POIs und zeichnet OHNE Backend-HTTP neu -
  /// der neue Punkt erscheint in der Sekunde des Push, nicht erst bei
  /// der nächsten Kamerabewegung.
  ///
  /// Berührt bewusst NICHT _lastLoadedBounds/_lastLoad: die Drosselung
  /// für die OSM-Viewport-Abfrage bleibt unangetastet; ein späterer
  /// Kamera-Idle im selben Ausschnitt lädt ohnehin konsistent nach.
  /// Wenn noch kein Viewport geladen wurde (Karte frisch), ist es ein
  /// No-Op - der reguläre load() übernimmt die Daten beim ersten Idle.
  Future<void> applyBikerPois(WidgetRef ref) async {
    final controller = _controllerGetter();
    final bounds = _lastLoadedBounds;
    if (controller == null || bounds == null) return;

    final categories = ref.read(activePoiCategoriesProvider);
    final bikerPois = ref
        .read(bikerPoiSyncProvider)
        .pois
        .where((p) => categories.contains(p.category))
        .where((p) => _inBounds(p, bounds))
        .toList();
    final currentOsm =
        _poisById.values.where((p) => p.source != 'BIKER_SERVICE').toList(growable: false);
    final combined = <Poi>[...bikerPois, ...currentOsm];

    _poisById
      ..clear()
      ..addEntries(combined.map((p) => MapEntry(p.id, p)));
    ref.read(poiLayerControllerProvider.notifier).adoptMerged(
          osmPois: currentOsm,
          bikerPois: bikerPois,
        );
    await _render(combined);
  }

  bool _inBounds(Poi p, LatLngBounds bounds) {
    return p.lat >= bounds.southwest.latitude &&
        p.lat <= bounds.northeast.latitude &&
        p.lng >= bounds.southwest.longitude &&
        p.lng <= bounds.northeast.longitude;
  }

  Future<void> _render(List<Poi> pois) async {
    final controller = _controllerGetter();
    if (controller == null) return;

    await _clear();

    // Obergrenze: bei niedrigem Zoom liefern große BBoxes sonst tausende
    // Kreise - Kappung hält das Rendering stabil.
    for (final poi in pois.take(_maxCircles)) {
      try {
        final circle = await controller.addCircle(
          CircleOptions(
            geometry: LatLng(poi.lat, poi.lng),
            circleRadius: 7,
            circleColor: _colorFor(poi.category),
            circleStrokeWidth: 1.5,
            circleStrokeColor: '#0B0E11',
            circleOpacity: 0.9,
          ),
          {'poiId': poi.id},
        );
        _circles[poi.id] = circle;
      } catch (_) {
        // Einzelner Kreis darf scheitern, ohne den Layer zu töten.
      }
    }
  }

  Future<void> _clear() async {
    final controller = _controllerGetter();
    if (controller == null) return;
    for (final circle in _circles.values) {
      try {
        await controller.removeCircle(circle);
      } catch (_) {
        // Kreis war evtl. schon weg (Style-Reload) - weitermachen.
      }
    }
    _circles.clear();
  }

  /// Karten-Tap: nächstgelegenen POI innerhalb der Touch-Toleranz
  /// suchen. Returns null, wenn kein POI getroffen wurde (der Screen
  /// behandelt den Tap dann als Kartentap für Wegpunkte).
  Poi? handleMapTap(LatLng tapped) {
    Poi? best;
    double bestDist = double.infinity;
    for (final poi in _poisById.values) {
      final d = _approxDistanceMeters(tapped, LatLng(poi.lat, poi.lng));
      if (d < bestDist) {
        bestDist = d;
        best = poi;
      }
    }
    // 24 m Treffertoleranz: bei typischen Zoomstufen (14+) entspricht
    // das grob dem 48-dp-Touch-Ziel aus Phase 3 Teil B.3.
    return best != null && bestDist <= 24 ? best : null;
  }

  static String _colorFor(PoiCategory category) => switch (category) {
        PoiCategory.fuel => '#FF5A1F',
        PoiCategory.motoHotel => '#2EC4B6',
        PoiCategory.bikerMeetup => '#2EC4B6',
        PoiCategory.campsite => '#2EC4B6',
        PoiCategory.iceCream => '#2EC4B6',
        PoiCategory.speedCamera => '#E5484D',
        // Biker-POI-Dienst-Kategorien: kräftiges Gelb - hebt die
        // kuratierten TomTom-POIs visuell von den OSM-POIs ab.
        PoiCategory.restaurant => '#F5A623',
        PoiCategory.pub => '#F5A623',
        PoiCategory.snack => '#F5A623',
      };

  /// True, wenn [inner] komplett in [outer] liegt - verhindert das
  /// Nachladen, wenn der Nutzer nur innerhalb des schon geladenen
  /// Ausschnitts geschoben/gezoomt hat.
  static bool _containsBounds(LatLngBounds outer, LatLngBounds inner) {
    return outer.southwest.latitude <= inner.southwest.latitude &&
        outer.southwest.longitude <= inner.southwest.longitude &&
        outer.northeast.latitude >= inner.northeast.latitude &&
        outer.northeast.longitude >= inner.northeast.longitude;
  }

  static double _approxDistanceMeters(LatLng a, LatLng b) {
    final dLat = (a.latitude - b.latitude) * 111320;
    final dLng = (a.longitude - b.longitude) * 111320 * 0.7;
    return math.sqrt(dLat * dLat + dLng * dLng);
  }
}
