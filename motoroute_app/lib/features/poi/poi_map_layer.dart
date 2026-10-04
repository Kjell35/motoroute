import 'dart:math' as math;
import 'dart:ui' show Offset;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:motoroute_app/core/state/app_providers.dart';
import 'package:motoroute_app/features/poi/biker_poi_sync.dart';
import 'package:motoroute_app/features/poi/poi_offline_cache.dart';
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

  /// Zoom-Gate (Anforderung "Punkte nur bei Nahsicht"): POI-Dots erscheinen
  /// erst, wenn der sichtbare Längengrad-Bereich schmal genug ist (~12 km
  /// breit, entspricht Zoom ~13.5-14 in DE). Auf Landes-/Regionsebene ist
  /// die Karte poi-frei - erst reinschwenken zeigt sie.
  static const _showSpanDeg = 0.12;

  final Map<String, Circle> _circles = {};
  final Map<String, Symbol> _labels = {};
  final Map<String, Poi> _poisById = {};
  LatLngBounds? _lastLoadedBounds;
  DateTime _lastLoad = DateTime.fromMillisecondsSinceEpoch(0);
  Set<PoiCategory> _lastCategories = {};
  bool _rendered = false;

  PoiMapLayer(this._controllerGetter);

  void dispose() {
    _circles.clear();
    _labels.clear();
    _poisById.clear();
    _lastLoadedBounds = null;
  }

  /// Sichtbarer Längengrad-Bereich in Grad (Näherung für das Zoom-Gate).
  static double _spanOf(LatLngBounds bounds) {
    var span = bounds.northeast.longitude - bounds.southwest.longitude;
    if (span < 0) span += 360; // Datumsgrenze-Fallback
    return span;
  }

  /// Epsilon-Toleranz für den Grenzfall (Float-Arithmetik: 11.62 - 11.50
  /// ist nicht exakt 0.12).
  static const _spanEpsilon = 1e-9;

  static bool _isCloseUp(LatLngBounds bounds) =>
      _spanOf(bounds) <= _showSpanDeg + _spanEpsilon;

  /// Test-Brücke: das Zoom-Gate ist rein statisch - so lässt es sich
  /// ohne maplibre-Controller prüfen.
  static bool isCloseUpForTest(LatLngBounds bounds) => _isCloseUp(bounds);

  /// Wird vom Kartenscreen nach Karten-Bewegung aufgerufen.
  Future<void> onCameraIdle(WidgetRef ref) async {
    final controller = _controllerGetter();
    if (controller == null) return;
    try {
      final bounds = await controller.getVisibleRegion();
      // Zoom-Gate: Rein-/Rauszoomen entscheidet über Dot-Sichtbarkeit.
      // War der Layer in derselben Nahsicht schon gerendert, ist nur das
      // Nachladen gedrosselt - das Sichtbar-/Unsichtbarmachen selbst
      // passiert in jedem Fall sofort (kein 5-s-Wait beim Zoomen).
      if (_isCloseUp(bounds)) {
        if (!_rendered) {
          await refresh(ref, bounds);
        } else {
          final tooSoon = DateTime.now().difference(_lastLoad) < const Duration(seconds: 5);
          if (!tooSoon) await refresh(ref, bounds);
        }
      } else if (_rendered) {
        _rendered = false; // Beim Wiedereinzoomen sofort wieder rendern.
        await _clear();
      }
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

    await _loadAndRender(ref, bounds);
  }

  /// Gemeinsamer Kern von refresh() und refreshIgnoringThrottle():
  /// Viewport-Abfrage + Biker-Merge + Render. Fehler landen im Layer-
  /// Controller, statt den Layer zu töten.
  Future<void> _loadAndRender(WidgetRef ref, LatLngBounds bounds) async {
    final categories = ref.read(activePoiCategoriesProvider);
    if (categories.isEmpty) {
      await _clear();
      return;
    }
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
    } catch (_) {
      // Funkloch-Fallback: OSM/BFF nicht erreichbar → kuratierte POIs
      // aus der lokalen SQLite-DB zeigen (Offline-Verfügbarkeit). Kein
      // Fehlerzustand - das ist der planmäßige Offline-Modus.
      try {
        final offlinePois = await ref
            .read(bikerPoiSyncProvider.notifier)
            .offline
            .database
            .inBounds(
              minLat: bounds.southwest.latitude,
              minLng: bounds.southwest.longitude,
              maxLat: bounds.northeast.latitude,
              maxLng: bounds.northeast.longitude,
              appCategories: categories.map((c) => c.apiValue).toSet(),
            );
        final fallback = offlinePois.map(_bikerPoiFromCache).toList();
        _poisById
          ..clear()
          ..addEntries(fallback.map((p) => MapEntry(p.id, p)));
        ref.read(poiLayerControllerProvider.notifier).adoptMerged(
              osmPois: const [],
              bikerPois: fallback,
            );
        await _render(fallback);
      } catch (_) {
        ref
            .read(poiLayerControllerProvider.notifier)
            .reportError('POIs nicht verfügbar');
      }
    }
  }

  /// SQLite-Zeile → BikerPoi für den Offline-Fallback im Karten-Layer.
  static BikerPoi _bikerPoiFromCache(CachedBikerPoi row) => BikerPoi(
        id: row.id,
        category: BikerPoi.categoryOfWire(row.appCategory),
        name: row.name,
        lat: row.lat,
        lng: row.lng,
        source: 'BIKER_SERVICE',
        bikerScore: row.bikerScore,
        motorcycleParking: row.motorcycleParking,
        meetingPoint: row.meetingPoint,
        sourceCategory: row.sourceCategory,
      );

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

  /// Ob schon ein Viewport geladen wurde (für den Sofort-Filter:
  /// Toggles vor dem ersten Kamera-Idle können nur leeren).
  bool get hasLastBounds => _lastLoadedBounds != null;

  /// Sofortiges Neuladen nach Kategorie-Toggle - bewusst OHNE die 5-s-
  /// Drosselung und OHNE sameArea-Skip: Der Filter muss sich sofort
  /// spürbar ändern (POI verschwindet in der Sekunde des Toggles),
  /// nicht beim nächsten Kartenschubsen. Nur in der Nahsicht wird
  /// nachgeladen (außerhalb ist der Layer ohnehin leer).
  Future<void> refreshIgnoringThrottle(WidgetRef ref) async {
    final bounds = _lastLoadedBounds;
    if (bounds == null || !_isCloseUp(bounds)) {
      _rendered = false;
      await _clear();
      return;
    }
    _lastLoad = DateTime.now();
    await _loadAndRender(ref, bounds);
  }

  /// Harte Leerung ohne Nachladen (z. B. Toggle bevor die Karte bereit
  /// ist) - der nächste Kamera-Idle lädt konsistent nach.
  Future<void> clearNow() => _clear();

  bool _inBounds(Poi p, LatLngBounds bounds) {
    return p.lat >= bounds.southwest.latitude &&
        p.lat <= bounds.northeast.latitude &&
        p.lng >= bounds.southwest.longitude &&
        p.lng <= bounds.northeast.longitude;
  }

  Future<void> _render(List<Poi> pois) async {
    final controller = _controllerGetter();
    if (controller == null) return;

    final bounds = _lastLoadedBounds;
    // Zoom-Gate: außerhalb der Nahsicht KEINE Dots rendern (Daten sind
    // trotzdem geladen - beim Reinschwenken erscheinen sie sofort).
    if (bounds == null || !_isCloseUp(bounds)) {
      await _clear();
      _rendered = false;
      return;
    }

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

        // Namens-Label UNTER dem Dot ("Shell Tankstelle"): nur sinnvoll,
        // wenn der POI einen Namen hat. Halo hält den Text auf jeder
        // Kachel lesbar.
        if (poi.name.isNotEmpty) {
          final symbol = await controller.addSymbol(
            SymbolOptions(
              geometry: LatLng(poi.lat, poi.lng),
              textField: poi.name.length > 24 ? '${poi.name.substring(0, 24)}…' : poi.name,
              textSize: 11,
              textColor: '#FFFFFF',
              textHaloColor: '#0B0E11',
              textHaloWidth: 1.5,
              textOffset: const Offset(0, 1.4),
              textAnchor: 'top',
            ),
          );
          _labels[poi.id] = symbol;
        }
      } catch (_) {
        // Einzelner Kreis darf scheitern, ohne den Layer zu töten.
      }
    }
    _rendered = true;
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
    for (final symbol in _labels.values) {
      try {
        await controller.removeSymbol(symbol);
      } catch (_) {}
    }
    _labels.clear();
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
    // 28 m Treffertoleranz: Dot ist 7 px, das Label erweitert das
    // Touch-Ziel - zusammen mit der Label-Sichtbarkeit trifft man auch
    // auf kleinen Zoomstufen zuverlässig (48-dp-Richtlinie).
    return best != null && bestDist <= 28 ? best : null;
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
