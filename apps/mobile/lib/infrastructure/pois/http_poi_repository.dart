import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/config/env.dart';
import '../../domain/models/place.dart';

/// POI-Zwischenstopps: Tankstellen, Motorradhotels etc. über den Backend-/pois
/// Endpoint (Overpass). Die Kategorie ist bewusst klein und Fahrt-relevant.
enum StopCategory { fuel, motoHotel, campsite, iceCream }

extension StopCategoryLabel on StopCategory {
  String get label => switch (this) {
        StopCategory.fuel => 'Tankstelle',
        StopCategory.motoHotel => 'Motorradhotel',
        StopCategory.campsite => 'Camping',
        StopCategory.iceCream => 'Eis',
      };

  String get apiValue => switch (this) {
        StopCategory.fuel => 'fuel',
        StopCategory.motoHotel => 'moto_hotel',
        StopCategory.campsite => 'campsite',
        StopCategory.iceCream => 'ice_cream',
      };
}

class PoiException implements Exception {
  const PoiException(this.message);
  final String message;
}

class PoiRepository {
  PoiRepository({http.Client? client}) : _client = client ?? http.Client();
  final http.Client _client;

  /// POIs in der Bounding-Box um einen Bereich (der Route folgend).
  Future<List<Place>> nearby({
    required double south,
    required double west,
    required double north,
    required double east,
    Set<StopCategory> categories = const {StopCategory.fuel},
  }) async {
    final Uri uri = Uri.parse('${Env.apiBaseUrl}/api/v1/pois').replace(queryParameters: {
      'bbox': '${west.toStringAsFixed(4)},${south.toStringAsFixed(4)},'
          '${east.toStringAsFixed(4)},${north.toStringAsFixed(4)}',
      'categories': [for (final StopCategory category in categories) category.apiValue],
    });
    final http.Response response;
    try {
      response = await _client.get(uri).timeout(const Duration(seconds: 15));
    } catch (_) {
      throw const PoiException('POI-Dienst nicht erreichbar.');
    }
    if (response.statusCode != 200) {
      throw const PoiException('Tankstellen & Co. sind gerade nicht verfügbar.');
    }
    final List<dynamic> payload = jsonDecode(response.body) as List<dynamic>;
    return [
      for (final Map<String, dynamic> element in payload.cast<Map<String, dynamic>>())
        Place(
          id: element['id'] as String,
          label: element['name'] as String,
          detail: element['category'] as String?,
          latitude: (element['lat'] as num).toDouble(),
          longitude: (element['lon'] as num).toDouble(),
        ),
    ];
  }
}
