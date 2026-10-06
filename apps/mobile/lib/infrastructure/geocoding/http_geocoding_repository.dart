import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/config/env.dart';
import '../../domain/models/place.dart';
import '../../domain/repositories/geocoding_repository.dart';

class GeocodingException implements Exception {
  const GeocodingException(this.message);
  final String message;
}

/// HTTP-Adapter für die eigene API; Photon bleibt damit austauschbar.
class HttpGeocodingRepository implements GeocodingRepository {
  HttpGeocodingRepository({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  @override
  Future<List<Place>> search(String query,
      {double? latitude, double? longitude}) async {
    final Map<String, String> params = {'q': query, 'limit': '8'};
    if (latitude != null && longitude != null) {
      params.addAll({'lat': '$latitude', 'lon': '$longitude'});
    }
    return _get('/api/v1/geocode', params);
  }

  @override
  Future<Place?> reverse(double latitude, double longitude) async {
    final List<Place> results = await _get('/api/v1/reverse', {
      'lat': '$latitude',
      'lon': '$longitude',
      'limit': '1',
    });
    return results.isEmpty ? null : results.first;
  }

  Future<List<Place>> _get(String path, Map<String, String> params) async {
    final Uri uri = Uri.parse('${Env.apiBaseUrl}$path').replace(queryParameters: params);
    try {
      final http.Response response = await _client.get(uri).timeout(const Duration(seconds: 7));
      if (response.statusCode != 200) {
        throw GeocodingException('Die Suche ist gerade nicht verfügbar.');
      }
      final List<dynamic> body = jsonDecode(response.body) as List<dynamic>;
      return body
          .map((dynamic item) => Place.fromJson(item as Map<String, dynamic>))
          .toList(growable: false);
    } on GeocodingException {
      rethrow;
    } catch (_) {
      throw const GeocodingException('Keine Verbindung zur Suche.');
    }
  }
}
