import '../models/map_item.dart';

abstract interface class MapDataRepository {
  Future<List<MapPoi>> pois({
    required double latitude,
    required double longitude,
    required Set<PoiCategory> categories,
  });
  Future<TrafficFeed> traffic({required double latitude, required double longitude});
}
