import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/config/env.dart';
import '../../domain/models/map_item.dart';
import '../../domain/repositories/map_data_repository.dart';

class MapDataException implements Exception {
  const MapDataException(this.message);
  final String message;
}

class HttpMapDataRepository implements MapDataRepository {
  HttpMapDataRepository({http.Client? client}) : _client = client ?? http.Client();
  final http.Client _client;

  @override
  Future<List<MapPoi>> pois({
    required double latitude,
    required double longitude,
    required Set<PoiCategory> categories,
  }) async {
    final Map<String, List<String>> query = {
      'bbox': [_bbox(latitude, longitude)],
      'categories': categories.map((category) => category.apiValue).toList(),
    };
    final Object body = await _get('/api/v1/pois', query);
    return (body as List<dynamic>)
        .map((item) => MapPoi.fromJson(item as Map<String, dynamic>))
        .toList(growable: false);
  }

  @override
  Future<TrafficFeed> traffic({required double latitude, required double longitude}) async {
    final Object body = await _get('/api/v1/traffic/incidents', {
      'bbox': [_bbox(latitude, longitude)],
    });
    return TrafficFeed.fromJson(body as Map<String, dynamic>);
  }

  Future<Object> _get(String path, Map<String, List<String>> query) async {
    final Uri uri = Uri.parse('${Env.apiBaseUrl}$path').replace(queryParametersAll: query);
    try {
      final response = await _client.get(uri).timeout(const Duration(seconds: 12));
      if (response.statusCode != 200) throw const MapDataException('Kartendaten sind nicht erreichbar.');
      return jsonDecode(response.body);
    } on MapDataException {
      rethrow;
    } catch (_) {
      throw const MapDataException('Kartendaten sind nicht erreichbar.');
    }
  }

  String _bbox(double latitude, double longitude) {
    const delta = 0.12;
    return '${longitude - delta},${latitude - delta},${longitude + delta},${latitude + delta}';
  }
}
