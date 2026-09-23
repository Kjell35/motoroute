import 'package:flutter_test/flutter_test.dart';

import 'package:motoroute_app/features/tour_diary/data/gpx_service.dart';
import 'package:motoroute_app/features/tour_diary/domain/tour_entities.dart';

void main() {
  const sampleGpx = '''<?xml version="1.0" encoding="UTF-8"?>
<gpx version="1.1" creator="Calimoto" xmlns="http://www.topografix.com/GPX/1/1">
  <metadata><name>Alpenrunde</name></metadata>
  <wpt lat="47.558400" lon="10.749800"><name>Oberjoch Pass</name></wpt>
  <trk>
    <name>Alpenrunde</name>
    <trkseg>
      <trkpt lat="47.561000" lon="10.746000"><ele>1100.0</ele><time>2026-09-20T09:00:00Z</time></trkpt>
      <trkpt lat="47.562500" lon="10.748500"><ele>1120.5</ele><time>2026-09-20T09:01:00Z</time></trkpt>
      <trkpt lat="47.564000" lon="10.751000"><ele>1115.0</ele><time>2026-09-20T09:02:00Z</time></trkpt>
    </trkseg>
  </trk>
</gpx>''';

  group('GpxParser', () {
    test('parst trk/trkpt mit Titel, Zeitgrenzen, Ele-Metern', () {
      final tour = GpxParser().parse(sampleGpx);

      expect(tour.title, 'Alpenrunde');
      expect(tour.track.length, 3);
      expect(tour.startedAt!.toUtc().hour, 9);
      expect(tour.endedAt!.toUtc().hour, 9);
      // Höhengewinn: 1100 -> 1120.5 (+20.5), 1120.5 -> 1115 (kein Gewinn).
      expect(tour.elevationGainMeters, closeTo(20.5, 0.1));
      // Distanz > 0 und grob plausibel (zwei Segmente à ~300 m).
      expect(tour.distanceMeters, greaterThan(400));
      expect(tour.distanceMeters, lessThan(1000));
      // Dauer 2 min.
      expect(tour.durationSeconds, closeTo(120, 0.5));
    });

    test('liest verknüpfte POIs aus wpt, wenn ein Track existiert', () {
      final tour = GpxParser().parse(sampleGpx);
      expect(tour.pois.length, 1);
      expect(tour.pois.first.label, 'Oberjoch Pass');
      expect(tour.pois.first.lat, closeTo(47.5584, 0.0001));
    });

    test('fallback auf rte/rtept (Kurviger-Style Route)', () {
      const routeGpx = '''<gpx version="1.1" creator="Kurviger">
  <rte><name>Schwarzwald</name>
    <rtept lat="48.0" lon="8.0"/><rtept lat="48.01" lon="8.01"/>
  </rte>
</gpx>''';
      final tour = GpxParser().parse(routeGpx);
      expect(tour.title, 'Schwarzwald');
      expect(tour.track.length, 2);
      // Keine Zeitstempel -> Dauer 0, Start jetzt.
      expect(tour.durationSeconds, 0);
    });

    test('fehlerhafte Koordinaten werden übersprungen', () {
      const mixed = '''<gpx version="1.1">
  <trk><trkseg>
    <trkpt lat="99.0" lon="10.0"/>
    <trkpt lat="47.5" lon="200.0"/>
    <trkpt lat="47.561" lon="10.746"/>
    <trkpt lat="n/a" lon="10.7"/>
  </trkseg></trk>
</gpx>''';
      final tour = GpxParser().parse(mixed);
      expect(tour.track.length, 1);
      expect(tour.track.first.lat, closeTo(47.561, 0.0001));
    });

    test('GpxException bei keinem XML', () {
      expect(() => GpxParser().parse('kein xml'), throwsA(isA<GpxException>()));
      expect(() => GpxParser().parse('<html/>'), throwsA(isA<GpxException>()));
      expect(
        () => GpxParser().parse('<gpx version="1.1"></gpx>'),
        throwsA(isA<GpxException>()),
      );
    });
  });

  group('GpxGenerator', () {
    test('Round-Trip: Export -> Import erhält Kern-Daten', () {
      const points = [
        TrackPoint(lat: 47.561, lng: 10.746, elevationMeters: 1100, secondsSinceStart: 0),
        TrackPoint(lat: 47.5625, lng: 10.7485, elevationMeters: 1120, secondsSinceStart: 60),
        TrackPoint(lat: 47.564, lng: 10.751, elevationMeters: 1115, secondsSinceStart: 120),
      ];
      final original = RecordedTour(
        title: 'Meine Tour',
        startedAt: DateTime.utc(2026, 9, 20, 9, 0, 0),
        endedAt: DateTime.utc(2026, 9, 20, 9, 2, 0),
        distanceMeters: 500,
        elevationGainMeters: 20,
        durationSeconds: 120,
        track: points,
        pois: const [TourPoiRef(label: 'Gasthaus', lat: 47.56, lng: 10.74)],
      );

      final xml = GpxGenerator().generate(original);
      expect(xml, contains('<name>Meine Tour</name>'));

      final reimported = GpxParser().parse(xml);
      expect(reimported.title, 'Meine Tour');
      expect(reimported.track.length, 3);
      expect(reimported.track.first.lat, closeTo(47.561, 0.0001));
      expect(reimported.track.last.lng, closeTo(10.751, 0.0001));
      expect(reimported.startedAt!.toUtc(), DateTime.utc(2026, 9, 20, 9, 0, 0));
      expect(reimported.durationSeconds, closeTo(120, 0.5));
      expect(reimported.pois.length, 1);
      expect(reimported.pois.first.label, 'Gasthaus');
    });

    test('erzeugt valides XML mit korrektem Escaping', () {
      const points = [
        TrackPoint(lat: 1, lng: 2, secondsSinceStart: 0),
        TrackPoint(lat: 3, lng: 4, secondsSinceStart: 10),
      ];
      final tour = RecordedTour(
        title: 'Bär & Co <Test>',
        startedAt: DateTime.utc(2026),
        endedAt: DateTime.utc(2026),
        distanceMeters: 1,
        elevationGainMeters: 0,
        durationSeconds: 10,
        track: points,
      );
      final xml = GpxGenerator().generate(tour);
      // XML-Entities - direkt <name>Bär & Co <Test></name> wäre invalide.
      expect(xml, contains('&amp;'));
      expect(xml, contains('&lt;'));
      // Der entscheidende Beweis: Der Round-Trip erhält den Titel exakt.
      expect(GpxParser().parse(xml).title, 'Bär & Co <Test>');
    });
  });
}
