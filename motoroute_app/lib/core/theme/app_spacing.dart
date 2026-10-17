/// 8-px-Grid aus Phase 3, Teil B.3. Bewusst als einzige erlaubte
/// Abstandswerte - Code-Reviews sollten jeden magischen Abstandswert
/// außerhalb dieser Liste zurückweisen.
class AppSpacing {
  const AppSpacing._();

  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
  static const double xxxl = 48;

  /// Mindest-Touch-Ziel im Planungsmodus (Phase 3 Teil B.3).
  static const double touchTargetPlanning = 48;

  /// Mindest-Touch-Ziel im Fahrmodus - Handschuh-Toleranz
  /// (Phase 3 Teil B.3 / B.4).
  static const double touchTargetDriving = 64;
}
