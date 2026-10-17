import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/models/place.dart';

/// Letzte Ziele (lokal auf dem Gerät, DSGVO-freundlich — docs/06 §5).
/// Erste App-Nutzung: leere Liste; Write-Last läuft bewusst fire-and-forget.
const String _storageKey = 'mr.recent_places_v1';
const int _maxEntries = 8;

final NotifierProvider<RecentPlacesController, List<Place>>
    recentPlacesProvider =
    NotifierProvider<RecentPlacesController, List<Place>>(
        RecentPlacesController.new);

class RecentPlacesController extends Notifier<List<Place>> {
  @override
  List<Place> build() {
    _load();
    return const [];
  }

  Future<void> _load() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String? raw = prefs.getString(_storageKey);
      if (raw == null) return;
      final List<dynamic> decoded = jsonDecode(raw) as List<dynamic>;
      final List<Place> places = decoded
          .map((entry) => Place.fromJson(entry as Map<String, dynamic>))
          .toList();
      state = places;
    } catch (_) {
      // Kaputter Speicherstand soll die App nicht lahmlegen: Liste bleibt leer.
    }
  }

  /// Neue Suche/Place oben einreihen; Duplikate wandern nach vorne statt
  /// doppelt zu stehen. Kappen auf [_maxEntries] Einträge.
  Future<void> push(Place place) async {
    final List<Place> withoutDuplicate = state
        .where((Place item) => item.id != place.id)
        .toList(growable: false);
    state = <Place>[place, ...withoutDuplicate].take(_maxEntries).toList();
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _storageKey,
        jsonEncode(state.map((Place item) => item.toJson()).toList()),
      );
    } catch (_) {
      // In-Memory-Liste ist trotzdem nutzbar (z. B. Speicher voll).
    }
  }

  Future<void> clear() async {
    state = const [];
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.remove(_storageKey);
    } catch (_) {
      // Siehe push(): In-Memory bleibt führend.
    }
  }
}
