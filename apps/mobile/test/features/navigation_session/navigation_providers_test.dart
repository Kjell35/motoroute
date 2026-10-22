import 'dart:async';

import 'package:dartz/dartz.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:mocktail/mocktail.dart';
import 'package:motoroute_app/core/constants/route_enums.dart';
import 'package:motoroute_app/core/error/failure.dart';
import 'package:motoroute_app/core/i18n/i18n.dart';
import 'package:motoroute_app/core/state/app_providers.dart';
import 'package:motoroute_app/features/map/data/location_repository.dart';
import 'package:motoroute_app/features/poi/poi_providers.dart';
import 'package:motoroute_app/features/navigation_session/navigation_providers.dart';
import 'package:motoroute_app/features/routing/data/routing_providers.dart';
import 'package:motoroute_app/features/routing/domain/route_entities.dart';
import 'package:motoroute_app/features/routing/domain/routing_repository.dart';
import 'package:motoroute_app/features/traffic/traffic_providers.dart';
import 'package:motoroute_app/features/weather/route_weather_providers.dart';

class _MockLocationRepository extends Mock implements LocationRepository {}

class _MockRoutingRepository extends Mock implements RoutingRepository {}

class _MockPoiRepository extends Mock implements PoiRepository {}

class _MockTrafficRepository extends Mock implements TrafficRepository {}

class _MockRouteWeatherRepository extends Mock
    implements RouteWeatherRepository {}

Position _position(double lat, double lng, {double speed = 12}) => Position(
      latitude: lat,
      longitude: lng,
      timestamp: DateTime.utc(2025),
      accuracy: 5,
      altitude: 500,
      altitudeAccuracy: 1,
      heading: 0,
      headingAccuracy: 1,
      speed: speed,
      speedAccuracy: 1,
    );

const _preference = RoutePreference(
  style: RouteStyle.curvy,
  vehicleType: VehicleType.motorcycle,
  avoid: {AvoidOption.highway},
);

NavigationRoute _navigationRoute(ComputedRoute route) => NavigationRoute(
      id: route.id,
      waypoints: route.waypoints,
      preference: route.preference,
      geometry: route.geometry,
      distanceMeters: route.distanceMeters,
      durationSeconds: route.durationSeconds,
      segments: route.segments,
    );

ComputedRoute _route({
  String id = 'route-1',
  required List<Waypoint> waypoints,
  List<List<double>>? geometry,
  RoutePreference? preference,
}) =>
    ComputedRoute(
      id: id,
      waypoints: waypoints,
      preference: preference ?? _preference,
      geometry: geometry ??
          const [
            [11.0, 48.0],
            [11.01, 48.0],
          ],
      distanceMeters: 1000,
      durationSeconds: 120,
      segments: const [],
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    registerFallbackValue(_preference);
  });

  late _MockLocationRepository location;
  late _MockRoutingRepository routing;
  late _MockPoiRepository pois;
  late _MockTrafficRepository traffic;
  late _MockRouteWeatherRepository weather;
  late StreamController<Position> positions;
  late ProviderContainer container;
  late List<Waypoint> originalWaypoints;

  setUp(() {
    location = _MockLocationRepository();
    routing = _MockRoutingRepository();
    pois = _MockPoiRepository();
    traffic = _MockTrafficRepository();
    weather = _MockRouteWeatherRepository();
    positions = StreamController<Position>();
    originalWaypoints = const [
      Waypoint(lat: 48.0, lng: 11.0, label: 'Start'),
      Waypoint(lat: 48.1, lng: 11.1, label: 'Ziel'),
    ];

    when(() => location.watchPosition(tuning: any(named: 'tuning')))
        .thenAnswer((_) => positions.stream);
    when(() => routing.reroute(
          waypoints: any(named: 'waypoints'),
          preference: any(named: 'preference'),
        )).thenAnswer((_) async => const Left(RoutingFailure('offline')));
    when(() => pois.fetchInBoundingBox(
          minLng: any(named: 'minLng'),
          minLat: any(named: 'minLat'),
          maxLng: any(named: 'maxLng'),
          maxLat: any(named: 'maxLat'),
          categories: any(named: 'categories'),
        )).thenAnswer((_) async => const []);
    when(() => traffic.fetchInBoundingBox(
          minLng: any(named: 'minLng'),
          minLat: any(named: 'minLat'),
          maxLng: any(named: 'maxLng'),
          maxLat: any(named: 'maxLat'),
        )).thenAnswer((_) async => const []);
    when(() => weather.fetchForRoute(
          geometry: any(named: 'geometry'),
          durationSeconds: any(named: 'durationSeconds'),
        )).thenAnswer((_) async => const RouteWeatherReport(isEnabled: false));

    container = ProviderContainer(overrides: [
      locationRepositoryProvider.overrideWithValue(location),
      routingRepositoryProvider.overrideWithValue(routing),
      poiRepositoryProvider.overrideWithValue(pois),
      trafficRepositoryProvider.overrideWithValue(traffic),
      routeWeatherRepositoryProvider.overrideWithValue(weather),
      voiceAnnouncementsEnabledProvider.overrideWith((ref) => false),
      i18nProvider.overrideWithValue(const I18n(AppLanguage.de)),
    ]);
    // Avoid waking auto-disposed platform channels: start() reads these
    // notifiers, so create safe test implementations via provider overrides.
    addTearDown(() async {
      container.read(navigationControllerProvider.notifier).stop();
      await positions.close();
      container.dispose();
    });
  });

  test('GPS-Stream aktualisiert Position, Tempo und monotonen Fortschritt',
      () async {
    final controller = container.read(navigationControllerProvider.notifier);
    controller.start(_route(waypoints: originalWaypoints));

    positions.add(_position(48.0, 11.002));
    await Future<void>.delayed(Duration.zero);
    final first = container.read(navigationControllerProvider);
    expect(first.isNavigating, isTrue);
    expect(first.position?.longitude, 11.002);
    expect(first.speedMps, 12);
    expect(first.traveledMeters, greaterThan(100));

    positions.add(_position(48.0, 11.001, speed: -1));
    await Future<void>.delayed(Duration.zero);
    final jitter = container.read(navigationControllerProvider);
    expect(jitter.traveledMeters, first.traveledMeters);
    expect(jitter.speedMps, 0);
  });

  test(
      'GPS-Ausreißer löst erst nach zwei Fixes Rerouting aus und bewahrt Präferenz',
      () async {
    final rerouteCompleter = Completer<Either<Failure, NavigationRoute>>();
    var rerouteCalls = 0;
    when(() => routing.reroute(
          waypoints: any(named: 'waypoints'),
          preference: any(named: 'preference'),
        )).thenAnswer((_) {
      rerouteCalls++;
      return rerouteCompleter.future;
    });

    final controller = container.read(navigationControllerProvider.notifier);
    controller.start(_route(waypoints: originalWaypoints));

    positions.add(_position(48.002, 11.005));
    await Future<void>.delayed(Duration.zero);
    expect(container.read(navigationControllerProvider).isOffRoute, isFalse);
    verifyNever(() => routing.reroute(
          waypoints: any(named: 'waypoints'),
          preference: any(named: 'preference'),
        ));

    positions.add(_position(48.002, 11.005));
    await Future<void>.delayed(Duration.zero);
    expect(container.read(navigationControllerProvider).isOffRoute, isTrue);
    expect(container.read(navigationControllerProvider).isRerouting, isTrue);

    final captured = verify(() => routing.reroute(
          waypoints: captureAny(named: 'waypoints'),
          preference: captureAny(named: 'preference'),
        )).captured;
    final requestedWaypoints = captured[0] as List<Waypoint>;
    expect(requestedWaypoints.first.lat, 48.002);
    expect(requestedWaypoints.first.lng, 11.005);
    expect(requestedWaypoints.first.label, 'Aktuelle Position');
    expect(requestedWaypoints.last, same(originalWaypoints.last));
    expect(captured[1], same(_preference));

    rerouteCompleter.complete(const Left(NetworkFailure()));
    await Future<void>.delayed(Duration.zero);
    final failed = container.read(navigationControllerProvider);
    expect(failed.isNavigating, isTrue);
    expect(failed.isRerouting, isFalse);
    expect(failed.route?.id, 'route-1');
    expect(failed.error, contains('alte Route bleibt aktiv'));

    positions.add(_position(48.002, 11.005));
    await Future<void>.delayed(Duration.zero);
    expect(rerouteCalls, 1,
        reason:
            'GPS-Fixes während der Retry-Sperre starten keinen neuen Request');

    controller.stop();
    await positions.close();
    positions = StreamController<Position>();
    controller.start(_route(waypoints: originalWaypoints));
    positions.add(_position(48.002, 11.005));
    await Future<void>.delayed(Duration.zero);
    positions.add(_position(48.002, 11.005));
    await Future<void>.delayed(Duration.zero);
    expect(rerouteCalls, 2,
        reason:
            'eine neue Navigation beginnt mit einem frischen Retry-Fenster');
    // Zweiter Versuch bleibt offen und wird vom teardown sicher invalidiert.
  });

  test('verspätete Reroute-Antwort überschreibt keine neue Navigation',
      () async {
    final staleCompleter = Completer<Either<Failure, NavigationRoute>>();
    when(() => routing.reroute(
          waypoints: any(named: 'waypoints'),
          preference: any(named: 'preference'),
        )).thenAnswer((_) => staleCompleter.future);

    final controller = container.read(navigationControllerProvider.notifier);
    controller.start(_route(waypoints: originalWaypoints));
    positions.add(_position(48.002, 11.005));
    await Future<void>.delayed(Duration.zero);
    positions.add(_position(48.002, 11.005));
    await Future<void>.delayed(Duration.zero);
    expect(container.read(navigationControllerProvider).isRerouting, isTrue);

    controller.stop();
    await positions.close();
    positions = StreamController<Position>();
    final newRoute = _route(
      id: 'route-new-session',
      waypoints: originalWaypoints,
    );
    controller.start(newRoute);

    staleCompleter.complete(Right(_navigationRoute(
      _route(id: 'stale-route', waypoints: originalWaypoints),
    )));
    await Future<void>.delayed(Duration.zero);

    final state = container.read(navigationControllerProvider);
    expect(state.isNavigating, isTrue);
    expect(state.isRerouting, isFalse);
    expect(state.route?.id, 'route-new-session');
  });

  test(
      'erfolgreiches Rerouting aktiviert neue Geometrie und setzt Fortschritt zurück',
      () async {
    final replacementWaypoints = [
      const Waypoint(lat: 48.0, lng: 11.0, label: 'Aktuelle Position'),
      originalWaypoints.last,
    ];
    final replacement = _route(
      id: 'route-2',
      waypoints: replacementWaypoints,
      geometry: const [
        [11.005, 48.002],
        [11.02, 48.0],
      ],
    );
    when(() => routing.reroute(
          waypoints: any(named: 'waypoints'),
          preference: any(named: 'preference'),
        )).thenAnswer((_) async => Right(NavigationRoute(
          id: replacement.id,
          waypoints: replacement.waypoints,
          preference: replacement.preference,
          geometry: replacement.geometry,
          distanceMeters: replacement.distanceMeters,
          durationSeconds: replacement.durationSeconds,
          segments: replacement.segments,
        )));

    final controller = container.read(navigationControllerProvider.notifier);
    controller.start(_route(waypoints: originalWaypoints));
    positions.add(_position(48.002, 11.005));
    await Future<void>.delayed(Duration.zero);
    positions.add(_position(48.002, 11.005));
    await Future<void>.delayed(const Duration(milliseconds: 10));

    final rerouted = container.read(navigationControllerProvider);
    expect(rerouted.route?.id, 'route-2');
    expect(rerouted.isNavigating, isTrue);
    expect(rerouted.isRerouting, isFalse);
    expect(rerouted.traveledMeters, 0);
    expect(rerouted.position, isNull);

    positions.add(_position(48.001, 11.01));
    await Future<void>.delayed(Duration.zero);
    final resumed = container.read(navigationControllerProvider);
    expect(resumed.position?.longitude, 11.01);
    expect(resumed.traveledMeters, greaterThan(0));
  });
}
