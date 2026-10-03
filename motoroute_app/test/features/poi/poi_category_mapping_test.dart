// Regression: Poi.fromJson mapppte RESTAURANT/PUB/SNACK fälschlich auf
// PoiCategory.fuel - die Punkte wurden dann als Tankstellen gefärbt und
// der Kategorie-Filter verglich die falschen Enums (Audit-Fund 03.10.).
import 'package:flutter_test/flutter_test.dart';
import 'package:motoroute_app/core/state/app_providers.dart';
import 'package:motoroute_app/features/poi/poi_providers.dart';

void main() {
  Poi poiOf(String apiCategory) => Poi.fromJson({
        'id': 'osm-node-1',
        'category': apiCategory,
        'name': 'Test-POI',
        'lat': 48.1,
        'lng': 11.4,
        'source': 'OSM',
      });

  test('RESTAURANT mappt auf PoiCategory.restaurant (nicht fuel)', () {
    expect(poiOf('RESTAURANT').category, PoiCategory.restaurant);
  });

  test('PUB mappt auf PoiCategory.pub', () {
    expect(poiOf('PUB').category, PoiCategory.pub);
  });

  test('SNACK mappt auf PoiCategory.snack', () {
    expect(poiOf('SNACK').category, PoiCategory.snack);
  });

  test('bekannte Kategorien bleiben unverändert', () {
    expect(poiOf('FUEL').category, PoiCategory.fuel);
    expect(poiOf('MOTO_HOTEL').category, PoiCategory.motoHotel);
    expect(poiOf('BIKER_MEETUP').category, PoiCategory.bikerMeetup);
    expect(poiOf('CAMPSITE').category, PoiCategory.campsite);
    expect(poiOf('ICE_CREAM').category, PoiCategory.iceCream);
    expect(poiOf('SPEED_CAMERA').category, PoiCategory.speedCamera);
  });
}
