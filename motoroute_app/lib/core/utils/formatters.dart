/// Zentrale Formatierung von Routenwerten. Bewusst als reine Funktionen
/// (kein Widget-Bezug), damit sie unit-testbar sind und überall dasselbe
/// Format erzeugen - nichts wirkt irritierender während der Fahrt als
/// dieselbe Distanz, die auf zwei Screens unterschiedlich angezeigt wird.
library;

enum DistanceUnit { kilometers, miles }

extension DistanceUnitApi on DistanceUnit {
  String get apiValue => switch (this) {
        DistanceUnit.kilometers => 'KM',
        DistanceUnit.miles => 'MI',
      };
}

String formatDistanceMeters(double meters, {DistanceUnit unit = DistanceUnit.kilometers}) {
  if (unit == DistanceUnit.miles) {
    final miles = meters / 1609.344;
    if (miles < 0.1) return '${(meters * 3.28084).round()} ft';
    return '${miles.toStringAsFixed(miles < 10 ? 1 : 0)} mi';
  }
  if (meters < 1000) return '${meters.round()} m';
  final km = meters / 1000;
  return '${km.toStringAsFixed(km < 10 ? 1 : 0)} km'.replaceAll('.', ',');
}

String formatDurationSeconds(double seconds) {
  // Auf die nächste Minute runden; unter 45 s ist "<1 min" ehrlicher
  // als "1 min" (60 s wären gerundet falsch dargestellt).
  if (seconds < 45) return '<1 min';
  final totalMinutes = (seconds / 60).round();
  if (totalMinutes < 60) return '$totalMinutes min';
  final hours = totalMinutes ~/ 60;
  final minutes = totalMinutes % 60;
  return '$hours h ${minutes.toString().padLeft(2, '0')} min';
}

/// ETA relativ zu [now] - z. B. "14:30" (24h-Format, deutsch).
String formatEta(DateTime now, double remainingSeconds) {
  final eta = now.add(Duration(seconds: remainingSeconds.round()));
  return '${eta.hour.toString().padLeft(2, '0')}:${eta.minute.toString().padLeft(2, '0')}';
}

String formatSpeedMps(double metersPerSecond, {DistanceUnit unit = DistanceUnit.kilometers}) {
  if (unit == DistanceUnit.miles) {
    return '${(metersPerSecond * 2.23694).round()} mph';
  }
  return '${(metersPerSecond * 3.6).round()} km/h';
}
