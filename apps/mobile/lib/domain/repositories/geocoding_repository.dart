import '../models/place.dart';

abstract interface class GeocodingRepository {
  Future<List<Place>> search(String query, {double? latitude, double? longitude});
  Future<Place?> reverse(double latitude, double longitude);
}
