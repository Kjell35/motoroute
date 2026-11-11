import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:motoroute_app/core/constants/route_enums.dart';
import 'package:motoroute_app/core/state/app_providers.dart';
import 'package:motoroute_app/features/routing/domain/route_entities.dart';
import '../../core/network/error_reporter.dart';

/// Version des gespeicherten Formats. Ein Formatwechsel MUSS die Version
/// erhöhen - alte Sitzungen werden dann verworfen statt halb gelesen.
const int kNavigationSessionVersion = 1;

/// Wie lange eine unterbrochene Sitzung nach dem letzten Speichern noch
/// sinnvoll fortgesetzt werden kann. Nach einer Nacht ist die Route in der
/// Regel nicht mehr die, die der Fahrer wollte - dann lieber neu planen.
const Duration kNavigationSessionTtl = Duration(hours: 12);

/// Rohdaten einer Sitzung entschlüsseln -> null bei unbekannter Version,
/// fremden Typen oder fehlenden Pflichtfeldern. Bewusst tolerant gegenüber
/// ZUSÄTZLICHEN Feldern (ältere App-Version liest neuere Datei), streng
/// gegenüber fehlenden.
class NavigationSessionSnapshot {
  final ComputedRoute route;

  /// Bereits zurückgelegte Strecke beim Speichern (Meter).
  final double traveledMeters;

  /// Zeitpunkt des Speicherns (lokal).
  final DateTime savedAt;

  const NavigationSessionSnapshot({
    required this.route,
    required this.traveledMeters,
    required this.savedAt,
  });

  double get remainingMeters =>
      (route.distanceMeters - traveledMeters).clamp(0.0, route.distanceMeters);

  double get progressFraction => route.distanceMeters <= 0
      ? 0
      : (traveledMeters / route.distanceMeters).clamp(0.0, 1.0);

  Map<String, dynamic> toJson() => {
        'version': kNavigationSessionVersion,
        'saved_at': savedAt.toUtc().toIso8601String(),
        'traveled_m': traveledMeters,
        'route': encodeComputedRoute(route),
      };

  static NavigationSessionSnapshot? fromJson(Map<String, dynamic> json) {
    if (json['version'] != kNavigationSessionVersion) return null;
    final rawRoute = json['route'];
    if (rawRoute is! Map) return null;
    final route = decodeComputedRoute(Map<String, dynamic>.from(rawRoute));
    if (route == null) return null;

    final traveled = (json['traveled_m'] as num?)?.toDouble();
    final savedAtRaw = json['saved_at'];
    final savedAt =
        savedAtRaw is String ? DateTime.tryParse(savedAtRaw) : null;
    if (traveled == null || savedAt == null) return null;
    if (traveled.isNaN || traveled.isInfinite || traveled < 0) return null;

    return NavigationSessionSnapshot(
      route: route,
      traveledMeters: traveled.clamp(0.0, route.distanceMeters),
      savedAt: savedAt.toLocal(),
    );
  }
}

/// Route -> JSON. Geometrie bleibt [lng, lat] wie im Backend, Segmente
/// behalten Reihenfolge und Text (daraus entstehen die Ansagen).
Map<String, dynamic> encodeComputedRoute(ComputedRoute route) => {
      'id': route.id,
      'waypoints': route.waypoints
          .map((w) => {
                'lat': w.lat,
                'lng': w.lng,
                if (w.label != null) 'label': w.label,
              })
          .toList(),
      'preference': {
        'style': route.preference.style.apiValue,
        'vehicle': route.preference.vehicleType.apiValue,
        'avoid': route.preference.avoid.map((a) => a.apiValue).toList(),
      },
      'geometry': route.geometry,
      'distance_m': route.distanceMeters,
      'duration_s': route.durationSeconds,
      'segments': route.segments
          .map((s) => {
                'instruction': s.instruction,
                'distance_m': s.distanceMeters,
                'duration_s': s.durationSeconds,
              })
          .toList(),
      if (route.elevationGainMeters != null)
        'elevation_m': route.elevationGainMeters,
      'round_trip': route.isRoundTrip,
      if (route.plannedStart != null)
        'planned_start': route.plannedStart!.toUtc().toIso8601String(),
    };

ComputedRoute? decodeComputedRoute(Map<String, dynamic> json) {
  try {
    final id = json['id'];
    final rawWaypoints = json['waypoints'];
    final rawGeometry = json['geometry'];
    final rawSegments = json['segments'];
    final rawPreference = json['preference'];
    if (id is! String || rawWaypoints is! List || rawGeometry is! List) {
      return null;
    }
    if (rawSegments is! List || rawPreference is! Map) return null;

    final preferenceMap = Map<String, dynamic>.from(rawPreference);
    final style = routeStyleFromApiValue(preferenceMap['style'] as String?);
    final vehicle =
        vehicleTypeFromApiValue(preferenceMap['vehicle'] as String?);
    if (style == null || vehicle == null) return null;

    final avoid = <AvoidOption>{};
    final rawAvoid = preferenceMap['avoid'];
    if (rawAvoid is List) {
      for (final entry in rawAvoid) {
        final option = avoidOptionFromApiValue(entry as String?);
        // Unbekannte Vermeidungen (neuere Backend-Version) ignorieren -
        // die Route selbst bleibt gültig, nur die Präferenz ist schmaler.
        if (option != null) avoid.add(option);
      }
    }

    final waypoints = <Waypoint>[];
    for (final entry in rawWaypoints) {
      if (entry is! Map) return null;
      final map = Map<String, dynamic>.from(entry);
      final lat = (map['lat'] as num?)?.toDouble();
      final lng = (map['lng'] as num?)?.toDouble();
      if (lat == null || lng == null) return null;
      waypoints.add(Waypoint(
        lat: lat,
        lng: lng,
        label: map['label'] as String?,
      ));
    }

    final geometry = <List<double>>[];
    for (final entry in rawGeometry) {
      if (entry is! List || entry.length < 2) return null;
      final lng = (entry[0] as num?)?.toDouble();
      final lat = (entry[1] as num?)?.toDouble();
      if (lng == null || lat == null) return null;
      geometry.add([lng, lat]);
    }
    if (geometry.isEmpty || waypoints.isEmpty) return null;

    final segments = <RouteSegment>[];
    for (final entry in rawSegments) {
      if (entry is! Map) return null;
      final map = Map<String, dynamic>.from(entry);
      final instruction = map['instruction'];
      final distance = (map['distance_m'] as num?)?.toDouble();
      final duration = (map['duration_s'] as num?)?.toDouble();
      if (instruction is! String ||
          distance == null ||
          duration == null) {
        return null;
      }
      segments.add(RouteSegment(
        instruction: instruction,
        distanceMeters: distance,
        durationSeconds: duration,
      ));
    }

    final distanceMeters = (json['distance_m'] as num?)?.toDouble();
    final durationSeconds = (json['duration_s'] as num?)?.toDouble();
    if (distanceMeters == null || durationSeconds == null) return null;

    final plannedStartRaw = json['planned_start'];
    final plannedStart = plannedStartRaw is String
        ? DateTime.tryParse(plannedStartRaw)?.toLocal()
        : null;

    return ComputedRoute(
      id: id,
      waypoints: waypoints,
      preference: RoutePreference(
        style: style,
        vehicleType: vehicle,
        avoid: avoid,
      ),
      geometry: geometry,
      distanceMeters: distanceMeters,
      durationSeconds: durationSeconds,
      segments: segments,
      elevationGainMeters: (json['elevation_m'] as num?)?.toDouble(),
      isRoundTrip: json['round_trip'] == true,
      plannedStart: plannedStart,
    );
  } catch (_) {
    // Jede Form von Beschädigung endet hier - der Aufrufer verwirft.
    return null;
  }
}

/// Speichert die aktive Navigation so, dass sie einen Prozess-Tod
/// (Android-Kill im Hintergrund, Akku leer, Absturz) überlebt.
///
/// Zwei Dinge sind hier bewusst geregelt:
/// - **Drosselung**: nicht jeder GPS-Fix schreibt auf die Platte. Gespeichert
///   wird bei der ersten Sitzung sofort, danach alle [minSaveDistanceMeters]
///   oder spätestens nach [maxSaveInterval] (Stau, Ampel, Fähre).
/// - **Robustheit**: shared_preferences-Fehler (Plugin fehlt in Tests,
///   Plattform streikt) dürfen die Navigation NIE beeinflussen - alle
///   Methoden schlucken Fehler und melden nur false/null.
class NavigationSessionStore {
  NavigationSessionStore({
    Future<SharedPreferences>? prefs,
    DateTime Function()? clock,
  })  : _prefsFuture = prefs,
        _clock = clock ?? DateTime.now;

  static const String storageKey = 'navigation.active_session.v1';

  /// Ab dieser Distanz zur letzten Speicherung wird wieder geschrieben.
  static const double minSaveDistanceMeters = 250;

  /// Spätestens nach dieser Zeit wird geschrieben - auch ohne Bewegung.
  static const Duration maxSaveInterval = Duration(minutes: 2);

  /// Lazy: ein Store, der nur als Test-Doppel dient, darf die Plattform
  /// nie anfassen - sonst hängt der Widget-Test am Plugin-Kanal.
  Future<SharedPreferences>? _prefsFuture;
  Future<SharedPreferences> get _prefs =>
      _prefsFuture ??= SharedPreferences.getInstance();
  final DateTime Function() _clock;

  double? _lastSavedTraveled;
  DateTime? _lastSavedAt;

  /// Gespeicherte Sitzung oder null. Beschädigte, fremde und zu alte
  /// Sitzungen werden dabei gelöscht, damit sie nicht bei jedem Start
  /// erneut geprüft werden müssen.
  Future<NavigationSessionSnapshot?> load() async {
    try {
      final prefs = await _prefs;
      final raw = prefs.getString(storageKey);
      if (raw == null) return null;

      Object? decoded;
      try {
        decoded = jsonDecode(raw);
      } catch (_) {
        // Abgeschnittene Datei (Prozess mitten im Schreiben gestorben):
        // verwerfen, sonst wird sie bei jedem Start erneut geparst.
        await _clearPrefs(prefs);
        return null;
      }
      if (decoded is! Map) {
        await _clearPrefs(prefs);
        return null;
      }
      final snapshot =
          NavigationSessionSnapshot.fromJson(Map<String, dynamic>.from(decoded));
      if (snapshot == null) {
        await _clearPrefs(prefs);
        return null;
      }

      final age = _clock().difference(snapshot.savedAt);
      // Negative Age = Uhr wurde zurückgestellt oder Datei stammt aus der
      // Zukunft -> nicht fortsetzen. Toleranz 1 h für Zeitzonen-Effekte.
      if (age > kNavigationSessionTtl ||
          age < const Duration(hours: -1)) {
        await _clearPrefs(prefs);
        return null;
      }
      return snapshot;
    } catch (e) {
      // Speicher-/Plugin-Ausfall: die Navigation läuft ohne Sitzung weiter,
      // aber der Ausfall soll im Reporting auftauchen.
      ErrorReporter.instance.report('navigation.session', e);
      return null;
    }
  }

  /// Schreibt die Sitzung sofort (Start einer Navigation).
  Future<bool> save(NavigationSessionSnapshot snapshot) async {
    try {
      final prefs = await _prefs;
      final ok = await prefs.setString(
          storageKey, jsonEncode(snapshot.toJson()));
      if (ok) {
        _lastSavedTraveled = snapshot.traveledMeters;
        _lastSavedAt = _clock();
      }
      return ok;
    } catch (e) {
      ErrorReporter.instance.report('navigation.session', e);
      return false;
    }
  }

  /// Drossel-Entscheidung, bewusst als eigene Methode: so ist sie ohne
  /// Plattform-Kanal testbar.
  bool shouldSave(double traveledMeters) {
    final lastAt = _lastSavedAt;
    final lastM = _lastSavedTraveled;
    if (lastAt == null || lastM == null) return true;
    // Rücksprung (neue Route oder Wiederaufnahme mit kleinerem Fortschritt)
    // sofort sichern, sonst bliebe die alte Sitzung stehen.
    if (traveledMeters < lastM) return true;
    final moved = traveledMeters - lastM;
    if (moved >= minSaveDistanceMeters) return true;
    return _clock().difference(lastAt) >= maxSaveInterval;
  }

  /// Speichert nur, wenn die Drossel es zulässt. Kein Fehler nach außen.
  Future<bool> saveIfDue(NavigationSessionSnapshot snapshot) async {
    if (!shouldSave(snapshot.traveledMeters)) return false;
    return save(snapshot);
  }

  /// Sitzung verwerfen (Navigation beendet, Ziel erreicht, Nutzer lehnt ab).
  Future<void> clear() async {
    _lastSavedTraveled = null;
    _lastSavedAt = null;
    try {
      await _clearPrefs(await _prefs);
    } catch (e) {
      // Ohne Speicher gibt es nichts zu löschen - gemeldet wird es
      // trotzdem, sonst bliebe der Ausfall unsichtbar.
      ErrorReporter.instance.report('navigation.session', e);
    }
  }

  Future<void> _clearPrefs(SharedPreferences prefs) async {
    try {
      await prefs.remove(storageKey);
    } catch (e) {
      ErrorReporter.instance.report('navigation.session', e);
    }
  }
}

/// Ein Store pro App-Lauf: der Controller schreibt, die Karte liest beim
/// Start. Zwei Instanzen würden getrennte Drossel-Zustände führen.
final navigationSessionStoreProvider =
    Provider<NavigationSessionStore>((ref) => NavigationSessionStore());
