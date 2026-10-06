import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/repositories/location_repository.dart';
import '../../domain/services/camera_policy.dart';
import '../../domain/services/heading_filter.dart';
import '../../domain/value_objects/app_location.dart';
import '../../infrastructure/location/geolocator_location_repository.dart';
import '../../domain/repositories/geocoding_repository.dart';
import '../../infrastructure/geocoding/http_geocoding_repository.dart';

/// Infrastruktur-Registry (docs/02-architecture.md §3, di/).
/// Später: hier Austausch gegen Fake-Ports in Tests.
final Provider<LocationRepository> locationRepositoryProvider =
    Provider<LocationRepository>((ref) => GeolocatorLocationRepository());

final Provider<GeocodingRepository> geocodingRepositoryProvider =
    Provider<GeocodingRepository>((ref) => HttpGeocodingRepository());

/// Domain-Service: Heading-Glättung (App-scope, zustandsbehaftet).
final Provider<HeadingFilter> headingFilterProvider =
    Provider<HeadingFilter>((ref) => HeadingFilter());

/// Domain-Service: Kamera-Entscheidungen (stateless).
final Provider<CameraPolicy> cameraPolicyProvider =
    Provider<CameraPolicy>((ref) => const CameraPolicy());

/// Berechtigungs-/Service-Zustand, refreshbar.
final NotifierProvider<LocationGrantController, LocationGrant?>
    locationGrantProvider = NotifierProvider<LocationGrantController,
        LocationGrant?>(LocationGrantController.new);

class LocationGrantController extends Notifier<LocationGrant?> {
  @override
  LocationGrant? build() {
    _refresh();
    return null; // null = noch prüfend (UI zeigt neutralen Zustand)
  }

  Future<void> _refresh() async {
    final LocationGrant grant =
        await ref.read(locationRepositoryProvider).resolveGrant();
    state = grant;
  }

  Future<void> refresh() => _refresh();

  /// Pre-Prompt-Fluss (docs/06-ux-safety.md §5): Erklärung vor OS-Dialog.
  Future<bool> requestWithRationale() async {
    final LocationRepository repo = ref.read(locationRepositoryProvider);
    if (!await repo.isServiceEnabled()) {
      state = LocationGrant.serviceDisabled;
      return false;
    }
    final bool ok = await repo.requestPermission();
    await _refresh();
    return ok;
  }

  Future<void> openSettings() =>
      ref.read(locationRepositoryProvider).openLocationSettings();
}

/// GPS-Stream (läuft unabhängig von der Berechtigung; UI entscheidet über Anzeige).
final StreamProvider<AppLocation> locationStreamProvider =
    StreamProvider<AppLocation>((ref) {
  final LocationRepository repo = ref.watch(locationRepositoryProvider);
  return repo.positionStream();
});

/// Kamera-Modus (follow/manual) – State laut docs/02-architecture.md §4.
final NotifierProvider<CameraModeController, CameraMode> cameraModeProvider =
    NotifierProvider<CameraModeController, CameraMode>(
        CameraModeController.new);

class CameraModeController extends Notifier<CameraMode> {
  @override
  CameraMode build() => CameraMode.follow;

  void apply(CameraDecision decision) => state = decision.mode;
}
