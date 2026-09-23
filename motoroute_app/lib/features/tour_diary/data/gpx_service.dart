import 'dart:math' as math;

import 'package:xml/xml.dart';

import '../domain/tour_entities.dart';

/// GPX 1.1 Parser & Generator - der Austauschstandard für Fahrrad-
/// und Motorrad-Navigation (Calimoto, Kurviger, OsmAnd, Garmin).
///
/// Import-Strategie: Wir lesen `trk` (Track) mit `trkpt`, fallen auf
/// `rte` (Route) mit `rtept` zurück und akzeptieren schließlich
/// freistehende `wpt` (Waypoints). Namen/Zeitstempel werden soweit
/// vorhanden übernommen. Unbekannte Elemente (Extensions wie
/// Calimotos Kurvigkeits-Scores) werden IGNORIERT, nicht als Fehler
/// gewertet - Toleranz ist hier wichtiger als Strenge.
///
/// Export: trk mit trkpt (lat, lon, ele, time) + wpt für verknüpfte
/// POIs - genau die Struktur, die Calimoto/Kurviger selbst schreiben.
class GpxException implements Exception {
  final String message;
  GpxException(this.message);
  @override
  String toString() => message;
}

class GpxParser {
  /// Parst GPX-XML in eine Tour. [fallbackTitle] greift, wenn die Datei
  /// keinen Namen trägt (Metadata oder trk/name).
  RecordedTour parse(String xml, {String? fallbackTitle}) {
    XmlDocument doc;
    try {
      doc = XmlDocument.parse(xml);
    } on XmlException catch (e) {
      throw GpxException('Keine gültige GPX/XML-Datei (${e.message})');
    }

    final root = doc.rootElement;
    if (root.name.local != 'gpx') {
      throw GpxException('Kein GPX-Format: Wurzelelement "${root.name.local}"');
    }

    final points = <TrackPoint>[];
    final pointTimes = <DateTime?>[];

    // 1) trk/trkpt (aufgezeichnete Spur - der Hauptfall).
    for (final trk in root.findElements('trk')) {
      final segs = trk.findElements('trkseg').toList();
      if (segs.isEmpty) {
        // Punkte ohne Segmente direkt unter trk (manche Exporteure).
        _collectPoints(trk, 'trkpt', points, pointTimes);
      }
      for (final trkseg in segs) {
        _collectPoints(trkseg, 'trkpt', points, pointTimes);
      }
    }

    // 2) rte/rtept (geplante Route - z. B. aus Kurviger exportiert).
    if (points.isEmpty) {
      for (final rte in root.findElements('rte')) {
        _collectPoints(rte, 'rtept', points, pointTimes);
      }
    }

    // 3) freistehende wpt (letzter Fallback - Wegpunktliste).
    if (points.isEmpty) {
      _collectPoints(root, 'wpt', points, pointTimes);
    }

    if (points.isEmpty) {
      throw GpxException('GPX enthält keine Punkte (trk/rte/wpt leer)');
    }

    // Zeitstempel: aus den Punkten selbst ableiten, wenn vorhanden.
    final times = pointTimes.whereType<DateTime>().toList()..sort();
    final startedAt = times.isNotEmpty ? times.first : null;
    final endedAt = times.isNotEmpty ? times.last : null;

    // Titel: metadata/name > trk/name > rte/name > Fallback.
    var title = fallbackTitle ?? 'Tour';
    final metaName = _texts(root, ['metadata', 'name']);
    final trkName = _texts(root, ['trk', 'name']);
    final rteName = _texts(root, ['rte', 'name']);
    if (metaName.isNotEmpty) {
      title = metaName.first;
    } else if (trkName.isNotEmpty) {
      title = trkName.first;
    } else if (rteName.isNotEmpty) {
      title = rteName.first;
    }

    // Verknüpfte POIs: wpt als Stopps werten - aber nur, wenn wir einen
    // echten Track haben (sonst SIND die wpt bereits die Route).
    final pois = <TourPoiRef>[];
    if (root.findElements('trk').isNotEmpty) {
      for (final wpt in root.findElements('wpt')) {
        final lat = double.tryParse(wpt.getAttribute('lat') ?? '');
        final lng = double.tryParse(wpt.getAttribute('lon') ?? '');
        if (lat == null || lng == null) continue;
        final name = _texts(wpt, ['name']).join(' ');
        pois.add(TourPoiRef(label: name.isEmpty ? 'Wegpunkt' : name, lat: lat, lng: lng));
      }
    }

    return buildFromPoints(
      title: title,
      points: points,
      startedAt: startedAt,
      endedAt: endedAt,
      pois: pois,
    );
  }

  void _collectPoints(
    XmlElement parent,
    String tagName,
    List<TrackPoint> out,
    List<DateTime?> times,
  ) {
    for (final pt in parent.findElements(tagName)) {
      final parsed = _pointFrom(pt);
      if (parsed == null) continue; // ungültige Koordinaten überspringen
      out.add(parsed.$1);
      times.add(parsed.$2);
    }
  }

  /// Punkt + optionaler Zeitstempel (aus dem direkten <time>-Kind);
  /// null bei fehlenden/ungültigen Koordinaten.
  (TrackPoint, DateTime?)? _pointFrom(XmlElement pt) {
    final lat = double.tryParse(pt.getAttribute('lat') ?? '');
    final lng = double.tryParse(pt.getAttribute('lon') ?? '');
    if (lat == null || lng == null) return null;
    if (lat < -90 || lat > 90 || lng < -180 || lng > 180) return null;

    final eleText = pt
        .findElements('ele')
        .map((e) => e.innerText.trim())
        .where((e) => e.isNotEmpty)
        .join();
    final ele = double.tryParse(eleText);

    final timeText = pt
        .findElements('time')
        .map((e) => e.innerText.trim())
        .where((e) => e.isNotEmpty)
        .join();
    DateTime? time;
    if (timeText.isNotEmpty) {
      try {
        time = DateTime.parse(timeText.replaceFirst(' ', 'T'));
      } on FormatException {
        time = null;
      }
    }

    return (
      TrackPoint(lat: lat, lng: lng, elevationMeters: ele, secondsSinceStart: 0),
      time,
    );
  }

  /// Statistiken aus Punkten + relativer Zeitachse ableiten und die
  /// fertige Tour bauen. Öffentlich, damit auch der Recorder (der die
  /// Punkte selbst sammelt) denselben Statistik-Pfad nutzt.
  RecordedTour buildFromPoints({
    required String title,
    required List<TrackPoint> points,
    DateTime? startedAt,
    DateTime? endedAt,
    List<TourPoiRef> pois = const [],
  }) {
    double distance = 0;
    double elevationGain = 0;
    double? lastEle;
    for (var i = 0; i < points.length; i++) {
      if (i > 0) {
        distance += _haversine(
          points[i - 1].lat,
          points[i - 1].lng,
          points[i].lat,
          points[i].lng,
        );
      }
      final ele = points[i].elevationMeters;
      if (ele != null) {
        if (lastEle != null && ele > lastEle) elevationGain += ele - lastEle;
        lastEle = ele;
      }
    }

    final start = startedAt ?? DateTime.now().toUtc();
    final durationSec = (endedAt?.difference(start).inMilliseconds ?? 0) / 1000;

    // Relative Sekunden: ohne echte Zeitstempel gleichmäßig über die
    // Punktreihenfolge verteilen (relevant für den Re-Export).
    final withRelative = <TrackPoint>[];
    final span = durationSec > 0 ? durationSec : 0.0;
    for (var i = 0; i < points.length; i++) {
      final frac = points.length > 1 ? i / (points.length - 1) : 0.0;
      final own = points[i].secondsSinceStart;
      withRelative.add(TrackPoint(
        lat: points[i].lat,
        lng: points[i].lng,
        elevationMeters: points[i].elevationMeters,
        secondsSinceStart: own > 0 ? own : frac * span,
      ));
    }

    return RecordedTour(
      title: title,
      startedAt: start,
      endedAt: endedAt ?? start.add(Duration(milliseconds: (span * 1000).round())),
      distanceMeters: distance,
      elevationGainMeters: elevationGain,
      durationSeconds: span,
      track: withRelative,
      pois: pois,
    );
  }

  List<String> _texts(XmlElement parent, List<String> path) {
    var current = parent.findElements(path.first).toList();
    for (var i = 1; i < path.length; i++) {
      current = current.expand((e) => e.findElements(path[i])).toList();
    }
    return current
        .map((e) => e.innerText.trim())
        .where((t) => t.isNotEmpty)
        .toList(growable: false);
  }

  double _haversine(double lat1, double lng1, double lat2, double lng2) {
    const r = 6371000.0;
    final dLat = _rad(lat2 - lat1);
    final dLng = _rad(lng2 - lng1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_rad(lat1)) * math.cos(_rad(lat2)) * math.sin(dLng / 2) * math.sin(dLng / 2);
    return r * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  double _rad(double deg) => deg * math.pi / 180;
}

/// GPX 1.1 Export: Eine [RecordedTour] als gültiges GPX-Dokument
/// schreiben (trk + trkpt mit ele/time, POIs als wpt).
class GpxGenerator {
  String generate(RecordedTour tour) {
    final builder = XmlBuilder();
    builder.processing('xml', 'version="1.0" encoding="UTF-8"');
    builder.element('gpx', namespaces: {
      'http://www.topografix.com/GPX/1/1': null,
    }, attributes: {
      'version': '1.1',
      'creator': 'MotoRoute',
      'xmlns:xsi': 'http://www.w3.org/2001/XMLSchema-instance',
    }, nest: () {
      builder.element('metadata', nest: () {
        builder.element('name', nest: tour.title);
        builder.element('time', nest: _iso(tour.startedAt));
      });

      // Verknüpfte POIs als Wegpunkte.
      for (final poi in tour.pois) {
        builder.element('wpt', attributes: {
          'lat': poi.lat.toStringAsFixed(6),
          'lon': poi.lng.toStringAsFixed(6),
        }, nest: () {
          builder.element('name', nest: poi.label);
        });
      }

      builder.element('trk', nest: () {
        builder.element('name', nest: tour.title);
        builder.element('trkseg', nest: () {
          for (final p in tour.track) {
            final t = tour.startedAt.add(
              Duration(milliseconds: (p.secondsSinceStart * 1000).round()),
            );
            builder.element('trkpt', attributes: {
              'lat': p.lat.toStringAsFixed(6),
              'lon': p.lng.toStringAsFixed(6),
            }, nest: () {
              if (p.elevationMeters != null) {
                builder.element('ele', nest: p.elevationMeters!.toStringAsFixed(1));
              }
              builder.element('time', nest: _iso(t));
            });
          }
        });
      });
    });

    return builder.buildDocument().toXmlString(pretty: true);
  }

  String _iso(DateTime t) {
    final utc = t.toUtc();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${utc.year.toString().padLeft(4, '0')}-${two(utc.month)}-${two(utc.day)}'
        'T${two(utc.hour)}:${two(utc.minute)}:${two(utc.second)}Z';
  }
}
