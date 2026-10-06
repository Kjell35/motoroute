import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:motoroute/application/route/waypoint_providers.dart';
import 'package:motoroute/domain/models/place.dart';

void main() {
  const Place munich = Place(id: 'n:1', label: 'München', latitude: 48.137, longitude: 11.575);
  const Place nuremberg = Place(id: 'n:2', label: 'Nürnberg', latitude: 49.452, longitude: 11.077);

  test('addPlace keeps order and suppresses duplicate places', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final controller = container.read(waypointsProvider.notifier);

    controller.addPlace(munich);
    controller.addPlace(munich);
    controller.addPlace(nuremberg);

    expect(container.read(waypointsProvider).map((item) => item.label), ['München', 'Nürnberg']);
  });

  test('move changes the route order', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final controller = container.read(waypointsProvider.notifier);
    controller.addPlace(munich);
    controller.addPlace(nuremberg);

    controller.move(1, 0);

    expect(container.read(waypointsProvider).first.label, 'Nürnberg');
  });
}
