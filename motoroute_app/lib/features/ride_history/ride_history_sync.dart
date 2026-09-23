import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_providers.dart';
import '../tour_diary/domain/tour_entities.dart';
import 'ride_history_repository.dart';

/// Brücke Tour-Aufzeichnung -> Backend. Nach JEDER abgeschlossenen
/// Navigation (Recorder-Stop) wird die Tour best-effort synchronisiert:
///
/// - Nur mit gültiger Anmeldung (Token); sonst übersprungen - die Tour
///   bleibt lokal im Tagebuch.
/// - Serverseitig entscheidet `ride_history_enabled` (aus), ob überhaupt
///   gespeichert wird, und die Privacy-Flags, ob sie öffentlich ist.
///   Die App schickt die Daten nur an das eigene Backend - welche Teile
///   davon öffentlich sichtbar werden, entscheidet ausschließlich die
///   serverseitige Konfiguration des Nutzers.
/// - Fehler (Server weg, Migration fehlt) werden geschluckt: Das
///   Navigation-Beenden darf nie an einem Sync hängen.
class RideHistorySync {
  RideHistorySync(this._ref);
  final Ref _ref;

  Future<void> syncFinishedTour(RecordedTour tour, {String? description}) async {
    final state = _ref.read(authControllerProvider);
    final token = _ref.read(authControllerProvider.notifier).accessToken;
    if (token == null || state.user == null) return; // nicht angemeldet

    final start = tour.track.isEmpty ? null : tour.track.first;
    final end = tour.track.isEmpty ? null : tour.track.last;

    final payload = <String, dynamic>{
      'externalId': 'tour-${tour.startedAt.toUtc().millisecondsSinceEpoch}',
      'title': tour.title,
      'startedAt': tour.startedAt.toUtc().toIso8601String(),
      'endedAt': tour.endedAt.toUtc().toIso8601String(),
      'distanceMeters': tour.distanceMeters,
      'durationSeconds': tour.durationSeconds,
      'elevationGainMeters': tour.elevationGainMeters,
      'track': tour.track
          .map((p) => {
                'lat': p.lat,
                'lng': p.lng,
                'elevationMeters': p.elevationMeters,
                'secondsSinceStart': p.secondsSinceStart,
              })
          .toList(),
      'pois': tour.pois
          .map((p) => {
                'externalId':
                    'poi-${p.lat.toStringAsFixed(4)}_${p.lng.toStringAsFixed(4)}',
                'category': 'other',
                'label': p.label,
                'lat': p.lat,
                'lng': p.lng,
              })
          .toList(),
      'startLat': start?.lat,
      'startLng': start?.lng,
      'endLat': end?.lat,
      'endLng': end?.lng,
      if (description != null && description.isNotEmpty) 'description': description,
    };

    try {
      await _ref.read(rideHistoryRepositoryProvider).syncRide(token, payload);
    } catch (_) {
      // Best-effort - lokal bleibt die Tour im Tagebuch.
    }
  }
}

final rideHistorySyncProvider = Provider<RideHistorySync>((ref) {
  return RideHistorySync(ref);
});
