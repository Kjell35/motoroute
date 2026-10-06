import 'dart:async';

import 'package:geolocator/geolocator.dart';

import '../../domain/repositories/location_repository.dart';
import '../../domain/value_objects/app_location.dart';

/// Infrastruktur-Adapter (docs/02-architecture.md §3): geolocator → Domain-Port.
class GeolocatorLocationRepository implements LocationRepository {
  GeolocatorLocationRepository({this.distanceFilterMeters = 5});

  /// Update-Filter: 5 m verhindert 1-Hz-Bursts im Stand (Energie, docs/08 §2).
  final double distanceFilterMeters;

  Stream<AppLocation>? _cached;

  AppLocation _map(Position p) => AppLocation(
        latitude: p.latitude,
        longitude: p.longitude,
        headingDegrees: (p.heading >= 0 && p.heading <= 360 && !p.heading.isNaN)
            ? p.heading
            : null,
        speedMps: (p.speed >= 0 && !p.speed.isNaN) ? p.speed : null,
        timestamp: p.timestamp,
      );

  @override
  Stream<AppLocation> positionStream() {
    return _cached ??= Geolocator.getPositionStream(
      locationSettings: LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: distanceFilterMeters,
      ),
    ).map(_map);
  }

  @override
  Future<AppLocation?> lastKnown() async {
    final Position? p = await Geolocator.getLastKnownPosition();
    return p == null ? null : _map(p);
  }

  @override
  Future<bool> isGranted() async => await Geolocator.checkPermission() ==
          LocationPermission.whileInUse ||
      await Geolocator.checkPermission() == LocationPermission.always;

  @override
  Future<bool> requestPermission() async {
    final LocationPermission p = await Geolocator.requestPermission();
    return p == LocationPermission.whileInUse || p == LocationPermission.always;
  }

  @override
  Future<bool> isServiceEnabled() => Geolocator.isLocationServiceEnabled();

  @override
  Future<bool> openLocationSettings() async {
    await Geolocator.openLocationSettings();
    return true;
  }

  @override
  Future<LocationGrant> resolveGrant() async {
    if (!await isServiceEnabled()) return LocationGrant.serviceDisabled;
    final LocationPermission p = await Geolocator.checkPermission();
    switch (p) {
      case LocationPermission.always:
      case LocationPermission.whileInUse:
        return LocationGrant.granted;
      case LocationPermission.deniedForever:
        return LocationGrant.deniedForever;
      case LocationPermission.denied:
        return LocationGrant.denied;
      case LocationPermission.unableToDetermine:
        return LocationGrant.undetermined;
    }
  }
}
