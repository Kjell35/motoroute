import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:motoroute_app/core/state/app_providers.dart';
import 'package:motoroute_app/core/utils/geo.dart';
import 'package:motoroute_app/features/map/data/location_repository.dart';
import 'package:motoroute_app/features/routing/data/routing_providers.dart';
import 'package:motoroute_app/features/routing/domain/route_entities.dart';
import 'package:motoroute_app/features/settings/energy_saver.dart'
    show EnergySaverMode, energySaverControllerProvider;
import 'package:motoroute_app/features/traffic/traffic_providers.dart';
import 'package:motoroute_app/features/weather/route_weather_providers.dart';
import 'dart:async' show StreamSubscription;

/// Ab der diese Distanz zur Routen-Geometrie eine Abweichung gilt
/// (GPS-Ungenauigkeit + Karten-Generalisierung einpreisen). Bewusst
/// konservativ: falsches Rerouting ist ärgerlicher als spätes Rerouting.
const double kOffRouteThresholdMeters = 60;

class NavigationState {
  final bool isNavigating;
  final ComputedRoute? route;

  /// Bisher zurückgelegte Distanz entlang der Route (Meter).
  final double traveledMeters;

  /// Aktuelle Geschwindigkeit (m/s, von GPS gemeldet).
  final double speedMps;

  final bool isOffRoute;
  final bool isRerouting;
  final String? error;

  /// Energiesparmodus-Warnung für den Screen: kritischer Akku
  /// degradiert die Off-Route-Erkennung - das MUSS sichtbar sein,
  /// sonst sieht ein spätes Rerouting wie ein Bug aus.
  final bool energySaverCritical;

  /// Grund der letzten proaktiven Umleitung (z. B. "Sperrung auf der
  /// Route") - erscheint im Rerouting-Banner (Phase 3 B.10: kein
  /// modal erzwungenes Bestätigen während der Fahrt).
  final String? rerouteReason;

  const NavigationState({
    this.isNavigating = false,
    this.route,
    this.traveledMeters = 0,
    this.speedMps = 0,
    this.isOffRoute = false,
    this.isRerouting = false,
    this.error,
    this.energySaverCritical = false,
    this.rerouteReason,
  });

  double get remainingMeters =>
      route == null ? 0 : (route!.distanceMeters - traveledMeters).clamp(0, route!.distanceMeters);

  double get remainingSeconds =>
      route == null ? 0 : (route!.durationSeconds * (remainingMeters / route!.distanceMeters));

  NavigationState copyWith({
    bool? isNavigating,
    ComputedRoute? route,
    double? traveledMeters,
    double? speedMps,
    bool? isOffRoute,
    bool? isRerouting,
    String? error,
    bool? energySaverCritical,
    String? rerouteReason,
  }) =>
      NavigationState(
        isNavigating: isNavigating ?? this.isNavigating,
        route: route ?? this.route,
        traveledMeters: traveledMeters ?? this.traveledMeters,
        speedMps: speedMps ?? this.speedMps,
        isOffRoute: isOffRoute ?? this.isOffRoute,
        isRerouting: isRerouting ?? this.isRerouting,
        error: error,
        energySaverCritical: energySaverCritical ?? this.energySaverCritical,
        rerouteReason: rerouteReason,
      );
}

/// Steuert die aktive Navigation (Screen 8):
/// - GPS-Stream -> Fortschritt entlang der Route
/// - Off-Route-Erkennung -> automatisches Rerouting über das Backend,
///   das die ursprüngliche Präferenz (Fahrstil/Vermeiden) erneut
///   anwendet - siehe routing.controller.ts im Backend, Abschnitt
///   "reroute respektiert die Original-Präferenz".
class NavigationController extends StateNotifier<NavigationState> {
  final Ref _ref;
  final LocationRepository _locationRepository;
  StreamSubscription<Position>? _positionSubscription;
  Position? _lastPosition;
  int? _lastPositionIndex;
  List<double> _cumulative = const [];

  NavigationController(this._ref, this._locationRepository) : super(const NavigationState()) {
    _watchEnergySaver();
  }

  void start(ComputedRoute route) {
    _cumulative = cumulativeDistances(route.geometry);
    state = NavigationState(
      isNavigating: true,
      route: route,
      energySaverCritical:
          _ref.read(energySaverControllerProvider).mode == EnergySaverMode.critical,
    );
    _subscribeToPositions();
    _watchEnergySaver();
    // Echtzeitverkehr: alle 30 s Vorfälle rund um die Reststrecke laden
    // und auf BLOCKIERENDE Vorfälle prüfen -> proaktives Rerouting.
    _ref.read(trafficControllerProvider.notifier).startNavigationMonitoring(route.geometry);
    _watchBlockingIncidents();
    // Wetter-Radar: Sturm-Frühwarnung entlang der Route (15-min-Refresh
    // im Controller). Stop passiert im Screen-dispose wie beim GPS.
    _ref
        .read(routeWeatherControllerProvider.notifier)
        .startForRoute(
          geometry: route.geometry,
          durationSeconds: route.durationSeconds,
        );
  }

  /// Proaktive Umleitung: lauscht auf Traffic-Refreshes und leitet um,
  /// BEVOR der Fahrer im Stau steht. Reagiert nur auf blockierende
  /// Kategorien (Sperrung/Unfall/Stau) mit HIGH-Severity - sonst würde
  /// jeder Zufalls-Stau die Kurvenroute zerschießen.
  void _watchBlockingIncidents() {
    _trafficSub?.close();
    _trafficSub = _ref.listen(
      trafficControllerProvider,
      (previous, next) {
        if (!state.isNavigating || state.isRerouting || next.incidents.isEmpty) return;
        final route = state.route;
        if (route == null) return;

        final blocking = _ref
            .read(trafficControllerProvider.notifier)
            .findBlockingIncidentNearRoute(routeGeometry: route.geometry);
        if (blocking == null) return;

        // Nur umleiten, wenn der Vorfall VOR uns liegt (auf der Rest-
        // strecke) - ein Stau HINTER uns ist irrelevant.
        if (!_incidentIsAhead(blocking, route)) return;

        final reason = switch (blocking.category) {
          IncidentCategory.roadClosed => 'Sperrung auf der Route',
          IncidentCategory.accident => 'Unfall auf der Route',
          IncidentCategory.jam => 'Stau auf der Route',
          IncidentCategory.laneClosed => 'Fahrstreifen gesperrt',
          IncidentCategory.roadWorks => 'Baustelle auf der Route',
          IncidentCategory.brokenDownVehicle => 'Liegender Fahrzeuge',
          _ => 'Verkehrsstörung auf der Route',
        };
        _rerouteProactively(reason);
      },
    );
  }

  bool _incidentIsAhead(TrafficIncident incident, ComputedRoute route) {
    // Ein Vorfall liegt "vor uns", wenn sein nächstgelegener Geometrie-
    // Punkt weiter vorn auf der Route liegt als unsere Position.
    if (incident.geometry.isEmpty) return false;

    // Position des Vorfalls auf der Route (nächstliegender Punkt).
    double bestIncidentDist = double.infinity;
    int incidentIdx = 0;
    for (final p in incident.geometry) {
      for (var i = 0; i < route.geometry.length; i++) {
        final d = haversineMeters(p[1], p[0], route.geometry[i][1], route.geometry[i][0]);
        if (d < bestIncidentDist) {
          bestIncidentDist = d;
          incidentIdx = i;
        }
      }
    }
    // Unser Fortschritt-Index ist der letzte bestandene Punkt; grob:
    // Vorfall liegt vor uns, wenn sein Index >= unserem entspricht.
    final traveledIdx = _lastPositionIndex ?? 0;
    return incidentIdx >= traveledIdx;
  }

  ProviderSubscription<TrafficState>? _trafficSub;

  /// Umleitung aus Anlass (Proaktiv statt off-route): dieselbe Präferenz,
  /// dieselbe Mechanik wie off-route - nur der Banner-Text unterscheidet
  /// sich ("Sperrung auf der Route" statt "Von Route abgewichen").
  Future<void> _rerouteProactively(String reason) async {
    final route = state.route;
    if (route == null || state.isRerouting) return;
    state = state.copyWith(isRerouting: true, rerouteReason: reason);

    final waypoints = <Waypoint>[
      if (_lastPosition != null)
        Waypoint(lat: _lastPosition!.latitude, lng: _lastPosition!.longitude, label: 'Aktuelle Position')
      else
        route.waypoints.first,
      ...route.waypoints.skip(1),
    ];

    try {
      final result = await _ref.read(routingRepositoryProvider).reroute(
            waypoints: waypoints,
            preference: route.preference,
          );
      result.fold(
        (failure) {
          state = state.copyWith(
            isRerouting: false,
            error: 'Umleitung fehlgeschlagen - alte Route bleibt aktiv',
          );
        },
        (newRoute) {
          final computed = ComputedRoute.fromDomain(newRoute);
          _cumulative = cumulativeDistances(computed.geometry);
          state = NavigationState(
            isNavigating: true,
            route: computed,
            isRerouting: false,
            rerouteReason: reason,
          );
        },
      );
    } catch (_) {
      state = state.copyWith(isRerouting: false, error: 'Umleitung fehlgeschlagen');
    }
  }

  /// GPS-Stream mit dem aktuellen Energiesparmodus-Tuning aufbauen.
  /// Bei Modus-Wechsel während der Fahrt wird reabonniert (der
  /// geolocator-Stream kennt keine Live-Parameter-Änderung).
  void _subscribeToPositions() {
    _positionSubscription?.cancel();
    final tuning = _ref.read(energySaverControllerProvider.notifier).locationTuning;
    _positionSubscription = _locationRepository.watchPosition(tuning: tuning).listen(
          _onPosition,
          onError: (Object e) => state = state.copyWith(error: 'GPS-Signal verloren'),
        );
  }

  void _onPosition(Position position) {
    if (!state.isNavigating || state.route == null) return;

    // Fortschritt: nächstliegender Geometrie-Punkt + dessen kumulierte
    // Distanz. Für die MVP-Genauigkeit reicht das; ein echtes Map-
    // Matching entlang von Segmenten ist eine spätere Verfeinerung.
    double bestDist = double.infinity;
    int bestIndex = 0;
    final geometry = state.route!.geometry;
    for (var i = 0; i < geometry.length; i++) {
      final d = haversineMeters(
        position.latitude,
        position.longitude,
        geometry[i][1],
        geometry[i][0],
      );
      if (d < bestDist) {
        bestDist = d;
        bestIndex = i;
      }
    }

    final traveled = bestIndex < _cumulative.length ? _cumulative[bestIndex] : 0.0;
    final offRoute = bestDist > kOffRouteThresholdMeters;

    _lastPosition = position;
    _lastPositionIndex = bestIndex;

    state = state.copyWith(
      traveledMeters: traveled,
      speedMps: position.speed.isNegative ? 0 : position.speed,
      isOffRoute: offRoute,
      error: null,
    );

    if (offRoute && !state.isRerouting) {
      _reroute(position);
    }
  }

  /// Neuberechnung ab aktueller Position - mit DERSELBEN Präferenz wie
  /// die ursprüngliche Route. Genau das ist der Vertrag zwischen App
  /// und Backend: Rerouting darf den Fahrstil niemals "verlieren".
  Future<void> _reroute(Position position) async {
    final route = state.route;
    if (route == null) return;

    state = state.copyWith(isRerouting: true);

    final waypoints = <Waypoint>[
      Waypoint(lat: position.latitude, lng: position.longitude, label: 'Aktuelle Position'),
      ...route.waypoints.skip(1),
    ];

    try {
      final result = await _ref.read(routingRepositoryProvider).reroute(
            waypoints: waypoints,
            preference: route.preference,
          );

      result.fold(
        (failure) {
          // Rerouting-Fehler NIEMALS die aktive Navigation abbrechen -
          // der Fahrer braucht die letzte gültige Route weiter.
          state = state.copyWith(
            isRerouting: false,
            error: 'Neuberechnung fehlgeschlagen - alte Route bleibt aktiv',
          );
        },
        (newRoute) {
          final computed = ComputedRoute.fromDomain(newRoute);
          _cumulative = cumulativeDistances(computed.geometry);
          state = NavigationState(isNavigating: true, route: computed, isRerouting: false);
        },
      );
    } catch (_) {
      state = state.copyWith(isRerouting: false, error: 'Neuberechnung fehlgeschlagen');
    }
  }

  void stop() {
    _positionSubscription?.cancel();
    _positionSubscription = null;
    _energySaverSub?.cancel();
    _energySaverSub = null;
    _trafficSub?.close();
    _trafficSub = null;
    _ref.read(trafficControllerProvider.notifier).stopNavigationMonitoring();
    state = const NavigationState();
  }

  /// Lauscht auf EnergieSparmodus-Änderungen WÄHREND der Navigation
  /// (Broadcast-Stream des EnergySaverControllers - riverpod 2.x Ref
  /// hat kein listenManual) und drosselt/entdrosselt den GPS-Stream
  /// live.
  StreamSubscription<EnergySaverMode>? _energySaverSub;

  void _watchEnergySaver() {
    _energySaverSub?.cancel();
    _energySaverSub = _ref
        .read(energySaverControllerProvider.notifier)
        .modeChanges
        .listen((mode) {
      state = state.copyWith(
        energySaverCritical: mode == EnergySaverMode.critical,
      );
      if (state.isNavigating) _subscribeToPositions();
    });
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    super.dispose();
  }
}

final navigationControllerProvider =
    StateNotifierProvider<NavigationController, NavigationState>((ref) {
  return NavigationController(ref, LocationRepository());
});
