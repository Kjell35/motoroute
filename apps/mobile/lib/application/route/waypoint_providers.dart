import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/place.dart';
import '../../domain/models/waypoint.dart';

/// Lokaler Routenentwurf. Erst M3 schickt die Waypoints an den Router.
final NotifierProvider<WaypointController, List<Waypoint>> waypointsProvider =
    NotifierProvider<WaypointController, List<Waypoint>>(WaypointController.new);

class WaypointController extends Notifier<List<Waypoint>> {
  @override
  List<Waypoint> build() => const [];

  void addPlace(Place place) => add(Waypoint.fromPlace(place));

  void add(Waypoint waypoint) {
    // Ein identischer Punkt soll nicht versehentlich mehrfach im Entwurf stehen.
    if (state.any((Waypoint item) => item.id == waypoint.id)) return;
    state = [...state, waypoint];
  }

  /// Setzt Anfang (index 0) — ersetzt einen vorhandenen Start.
  void setStart(Place place) => setAt(0, place);

  /// Setzt Ziel (Ende) — ersetzt einen vorhandenen Ziel-Eintrag.
  void setDestination(Place place) => setAt(state.length, place);

  /// Fügt als nächsten freien Wegpunkt ein (nach Start, vor Ziel),
  /// oder am Ende, wenn Start/Ziel noch nicht voll sind.
  void addIntermediate(Place place) {
    final Waypoint waypoint = Waypoint.fromPlace(place);
    // doppelte Points vermeiden
    if (state.any((Waypoint item) => item.id == waypoint.id)) return;
    if (state.length >= 2) {  // Start UND Ziel schon da → zwischen einschieben
      int at = state.length - 1;
      state = [...state]..insert(at, waypoint);
    } else {
      state = [...state, waypoint];
    }
  }

  void setAt(int index, Place place) {
    final Waypoint waypoint = Waypoint.fromPlace(place);
    // Duplikate entfernen, aber NICHT wenn die Position selbst die eigene ist.
    final List<Waypoint> withoutDup = state
        .where((Waypoint item) => item.id != waypoint.id)
        .toList();
    final int target = index.clamp(0, withoutDup.length);
    withoutDup.insert(target, waypoint);
    state = withoutDup;
  }

  /// Start und Ziel tauschen; interne Zwischenhalte bleiben in Reihenfolge.
  void swapStartDestination() {
    if (state.length < 2) return;
    final List<Waypoint> copy = [...state];
    final Waypoint first = copy.first;
    copy[0] = copy.last;
    copy[copy.length - 1] = first;
    state = copy;
  }

  /// Alle Wegpunkte entfernen (Routenentwurf komplett zurücksetzen).
  void clear() {
    state = const [];
  }

  void removeAt(int index) {
    if (index < 0 || index >= state.length) return;
    state = [...state]..removeAt(index);
  }

  void move(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= state.length) return;
    final List<Waypoint> copy = [...state];
    final Waypoint item = copy.removeAt(oldIndex);
    copy.insert(newIndex.clamp(0, copy.length) as int, item);
    state = copy;
  }
}
