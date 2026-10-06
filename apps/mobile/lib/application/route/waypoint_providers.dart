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
