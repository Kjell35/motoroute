enum PoiCategory { fuel, motoHotel, bikerMeet, campsite, iceCream, speedCamera }

extension PoiCategoryLabel on PoiCategory {
  String get apiValue => switch (this) {
        PoiCategory.fuel => 'fuel',
        PoiCategory.motoHotel => 'moto_hotel',
        PoiCategory.bikerMeet => 'biker_meet',
        PoiCategory.campsite => 'campsite',
        PoiCategory.iceCream => 'ice_cream',
        PoiCategory.speedCamera => 'speed_camera',
      };

  String get label => switch (this) {
        PoiCategory.fuel => 'Tankstellen',
        PoiCategory.motoHotel => 'Motorradhotels',
        PoiCategory.bikerMeet => 'Biker-Treffs',
        PoiCategory.campsite => 'Camping',
        PoiCategory.iceCream => 'Eisdielen',
        PoiCategory.speedCamera => 'Kameras',
      };
}

class MapPoi {
  const MapPoi({
    required this.id,
    required this.category,
    required this.name,
    required this.latitude,
    required this.longitude,
  });
  final String id;
  final PoiCategory category;
  final String name;
  final double latitude;
  final double longitude;

  factory MapPoi.fromJson(Map<String, dynamic> json) => MapPoi(
        id: json['id'] as String,
        category: PoiCategory.values.firstWhere(
          (category) => category.apiValue == json['category'],
        ),
        name: json['name'] as String,
        latitude: (json['lat'] as num).toDouble(),
        longitude: (json['lon'] as num).toDouble(),
      );
}

class TrafficIncident {
  const TrafficIncident({
    required this.id,
    required this.name,
    required this.type,
    required this.latitude,
    required this.longitude,
  });
  final String id;
  final String name;
  final String type;
  final double latitude;
  final double longitude;

  factory TrafficIncident.fromJson(Map<String, dynamic> json) => TrafficIncident(
        id: json['id'].toString(),
        name: json['name'] as String,
        type: json['type'].toString(),
        latitude: (json['lat'] as num).toDouble(),
        longitude: (json['lon'] as num).toDouble(),
      );
}

class TrafficFeed {
  const TrafficFeed({required this.source, required this.realTime, required this.incidents});
  final String source;
  final bool realTime;
  final List<TrafficIncident> incidents;

  factory TrafficFeed.fromJson(Map<String, dynamic> json) => TrafficFeed(
        source: json['source'] as String,
        realTime: json['real_time'] as bool,
        incidents: (json['incidents'] as List<dynamic>)
            .map((item) => TrafficIncident.fromJson(item as Map<String, dynamic>))
            .toList(growable: false),
      );
}
