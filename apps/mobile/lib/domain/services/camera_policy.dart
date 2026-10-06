/// Entscheidet Kamera-Modus-Wechsel (follow ↔ manual) – pure Domain-Logik.
///
/// Quelle: docs/02-architecture.md §5 („Kamera-Modi sind State"),
/// docs/06-ux-safety.md („Zentrieren-Button im Daumenbereich").
enum CameraMode { follow, manual }

class CameraDecision {
  const CameraDecision(this.mode, {this.shouldAnimate = true});

  final CameraMode mode;
  final bool shouldAnimate;
}

class CameraPolicy {
  const CameraPolicy({
    this.manualExitPanMeters = 35,
    this.recenterZoomBump = 0.0,
  });

  /// Ab welcher Pan-Distanz die Kamera in den manuellen Modus wechselt.
  final double manualExitPanMeters;

  /// Re-Zentrieren zoomt leicht heran, damit der Fahrer den Modus-Wechsel spürt.
  final double recenterZoomBump;

  /// Nutzer hat die Karte verschoben.
  CameraDecision onUserPan({required double panDistanceMeters}) {
    if (panDistanceMeters >= manualExitPanMeters) {
      return const CameraDecision(CameraMode.manual);
    }
    return const CameraDecision(CameraMode.follow, shouldAnimate: false);
  }

  /// Nutzer tippt Zentrieren-FAB.
  CameraDecision onRecenterTap() => const CameraDecision(CameraMode.follow);

  /// Nutzer startet Navigation (später in M4).
  CameraDecision onNavigationStarted() =>
      const CameraDecision(CameraMode.follow);
}
