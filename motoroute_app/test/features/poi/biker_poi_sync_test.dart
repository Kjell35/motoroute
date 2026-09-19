import 'package:flutter_test/flutter_test.dart';
import 'package:motoroute_app/core/state/app_providers.dart';
import 'package:motoroute_app/features/poi/biker_poi_sync.dart';
import 'package:motoroute_app/features/poi/poi_providers.dart';

void main() {
  group('BikerPoi.fromJson', () {
    test('parst Biker-Score und Amenities, setzt BIKER_SERVICE-Quelle', () {
      final p = BikerPoi.fromJson({
        'id': 'abc-123',
        'name': 'Biergarten am See',
        'category': 'BIKER_MEETUP',
        'lat': 48.14,
        'lon': 11.58,
        'bikerScore': 85,
        'amenities': {'motorcycle_parking': true, 'meeting_point': true},
      });
      expect(p.bikerScore, 85);
      expect(p.motorcycleParking, isTrue);
      expect(p.meetingPoint, isTrue);
      expect(p.source, 'BIKER_SERVICE');
      expect(p.category, PoiCategory.bikerMeetup);
    });

    test('fehlende Amenities: defensiv false statt Exception', () {
      final p = BikerPoi.fromJson({
        'id': 'x',
        'name': 'Gasthaus',
        'category': 'RESTAURANT',
        'lat': 1,
        'lon': 2,
        'bikerScore': 40,
      });
      expect(p.motorcycleParking, isFalse);
      expect(p.meetingPoint, isFalse);
    });
  });

  group('PoiCategory: Biker-Service-Kategorien (App-Brücke)', () {
    test('die 3 neuen Kategorien existieren mit korrekten API-Werten', () {
      expect(PoiCategory.restaurant.apiValue, 'RESTAURANT');
      expect(PoiCategory.pub.apiValue, 'PUB');
      expect(PoiCategory.snack.apiValue, 'SNACK');
      expect(PoiCategory.pub.label, 'Kneipen & Bars');
    });

    test('bikerServiceCategories deckt alle syncbaren Kategorien ab', () {
      // GARTENLOKAL/PENSION werden beim BFF auf BIKER_MEETUP/MOTO_HOTEL
      // gemappt - die App-Brücke braucht daher genau diese 6.
      expect(PoiCategoryApi.bikerServiceCategories, {
        PoiCategory.restaurant,
        PoiCategory.pub,
        PoiCategory.snack,
        PoiCategory.bikerMeetup,
        PoiCategory.motoHotel,
        PoiCategory.campsite,
      });
    });
  });

  group('BikerPoiSyncState', () {
    test('Default: kein Cursor, keine POIs, kein Fehler', () {
      const s = BikerPoiSyncState();
      expect(s.cursor, isNull);
      expect(s.pois, isEmpty);
      expect(s.isSyncing, isFalse);
      expect(s.error, isNull);
    });

    test('copyWith behält Cursor (Persistenz-Vertrag)', () {
      const s = BikerPoiSyncState(cursor: '2026-09-18T10:00:00.000Z');
      final s2 = s.copyWith(isSyncing: true);
      expect(s2.cursor, '2026-09-18T10:00:00.000Z');
      expect(s2.isSyncing, isTrue);
    });
  });

  group('PoiLayerController.adoptMerged', () {
    late PoiLayerController controller;

    setUp(() {
      controller = PoiLayerController(_FakeRepo());
    });

    test('OSM- und Biker-POIs werden zusammengeführt, Biker-Präfix schützt vor Kollision', () {
      const osm = [
        Poi(id: 'uuid-1', category: PoiCategory.fuel, name: 'Shell', lat: 48, lng: 11, source: 'OSM'),
      ];
      const biker = [
        BikerPoi(
          id: 'biker-uuid-1',
          category: PoiCategory.pub,
          name: 'Kurvenkönig',
          lat: 48.1,
          lng: 11.1,
          source: 'BIKER_SERVICE',
          bikerScore: 90,
          motorcycleParking: true,
          meetingPoint: true,
        ),
      ];

      controller.adoptMerged(osmPois: osm, bikerPois: biker);
      expect(controller.state.pois, hasLength(2));
      expect(controller.state.pois.any((p) => p.id == 'biker-uuid-1'), isTrue);
    });

    test('gleiche Id aus beiden Quellen: OSM gewinnt nicht (Biker zuerst, OSM überschreibt)', () {
      // Dokumentiert die Merge-Reihenfolge: OSM-POIs sind die live
      // abgefragte Quelle und haben Vorrang bei identischer Id (sollte
      // wegen Präfix-Konvention nie passieren - aber dann deterministisch).
      const osm = [Poi(id: 'x', category: PoiCategory.fuel, name: 'OSM-Version', lat: 48, lng: 11, source: 'OSM')];
      const biker = [
        BikerPoi(id: 'x', category: PoiCategory.pub, name: 'Biker-Version', lat: 48, lng: 11, source: 'BIKER_SERVICE', bikerScore: 50, motorcycleParking: false, meetingPoint: false),
      ];
      controller.adoptMerged(osmPois: osm, bikerPois: biker);
      expect(controller.state.pois.single.name, 'OSM-Version');
    });
  });
}

class _FakeRepo implements PoiRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}
