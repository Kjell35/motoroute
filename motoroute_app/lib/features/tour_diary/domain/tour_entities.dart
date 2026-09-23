/// Tour-Tagebuch: Domänen-Modelle.
///
/// Eine [RecordedTour] entsteht aus der Aufzeichnung einer aktiven
/// Navigation (GPS-Punkte) und kann als GPX exportiert/importiert
/// werden (kompatibel mit Calimoto, Kurviger, OsmAnd ...). Bewusst
/// frei von Flutter-Imports - alles rein testbar.

/// Ein aufgezeichneter GPS-Punkt während der Fahrt.
class TrackPoint {
  final double lat;
  final double lng;

  /// Meter über NN - von Android-GPS gemeldet (oft nur bei gutem
  /// Empfang gesetzt; fehlende Werte bleiben null und zählen nicht
  /// in die Höhenmeter-Statistik).
  final double? elevationMeters;

  /// Sekunden seit Tour-Start (Monoton steigend, relativ - ein
  /// absoluter Timestamp pro Punkt bläht GPX unnötig auf; die
  /// absoluten Grenzen stehen ja am Track).
  final double secondsSinceStart;

  const TrackPoint({
    required this.lat,
    required this.lng,
    this.elevationMeters,
    required this.secondsSinceStart,
  });
}

/// Ein verknüpfter POI (Stopp unterwegs - Tankstelle, Bikertreff ...).
class TourPoiRef {
  final String label;
  final double lat;
  final double lng;

  const TourPoiRef({required this.label, required this.lat, required this.lng});
}

/// Eine beendete, gespeicherte Tour.
class RecordedTour {
  final int? id;
  final String title;
  final DateTime startedAt;
  final DateTime endedAt;

  /// Gefahrene Distanz (Meter) - Summe der Segmente zwischen den
  /// GPS-Punkten, NICHT die geplante Routenlänge.
  final double distanceMeters;

  /// Summe der positiven Höhenunterschiede (Meter).
  final double elevationGainMeters;

  /// Verstrichene Fahrzeit (Sekunden) - Ende minus Start.
  final double durationSeconds;

  /// Aufgezeichnete GPS-Spur (chronologisch).
  final List<TrackPoint> track;

  /// Verknüpfte POIs (besuchte Stopps).
  final List<TourPoiRef> pois;

  const RecordedTour({
    this.id,
    required this.title,
    required this.startedAt,
    required this.endedAt,
    required this.distanceMeters,
    required this.elevationGainMeters,
    required this.durationSeconds,
    this.track = const [],
    this.pois = const [],
  });

  /// Durchschnittsgeschwindigkeit in km/h (bewegte Zeit = Dauer).
  double get avgSpeedKmh {
    if (durationSeconds <= 0) return 0;
    return (distanceMeters / 1000) / (durationSeconds / 3600);
  }

  RecordedTour copyWith({int? id, String? title}) => RecordedTour(
        id: id ?? this.id,
        title: title ?? this.title,
        startedAt: startedAt,
        endedAt: endedAt,
        distanceMeters: distanceMeters,
        elevationGainMeters: elevationGainMeters,
        durationSeconds: durationSeconds,
        track: track,
        pois: pois,
      );
}
