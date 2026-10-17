import 'package:flutter/widgets.dart';

/// Farb-Tokens aus der alten MotoRoute-App (v1.0.x, Phase 3 B.1) — der
/// Look, an den Nutzer in den früheren Builds gewohnt sind. Direkt aus dem
/// v1.0.3-Stand übernommen (Kommentar dort abgekürzt).
class AppColors {
  const AppColors._();

  // Dark (Standard-Erlebnis)
  static const Color bgBaseDark = Color(0xFF0B0E11);
  static const Color bgSurfaceDark = Color(0xFF151A1F);
  static const Color bgSurfaceRaisedDark = Color(0xFF1E252C);
  static const Color textPrimaryDark = Color(0xFFF5F6F4);
  static const Color textSecondaryDark = Color(0xFF9AA3AD);
  static const Color textMutedDark = Color(0xFF5B6470);

  // Light (zweites Schema)
  static const Color bgBaseLight = Color(0xFFF5F6F4);
  static const Color bgSurfaceLight = Color(0xFFFFFFFF);
  static const Color bgSurfaceRaisedLight = Color(0xFFF0F1EE);
  static const Color textPrimaryLight = Color(0xFF12151A);
  static const Color textSecondaryLight = Color(0xFF5B6470);
  static const Color textMutedLight = Color(0xFF9AA3AD);

  // Marken-/Akzentfarben
  static const Color accentPrimaryDark = Color(0xFFFF5A1F);
  static const Color accentPrimaryLight = Color(0xFFE64E17);
  static const Color accentSecondary = Color(0xFF2EC4B6);
  static const Color accentSecondaryLight = Color(0xFF1E9A8F);

  // Status
  static const Color statusWarning = Color(0xFFF5A623);
  static const Color statusWarningLight = Color(0xFFC97F0E);
  static const Color statusDanger = Color(0xFFE5484D);
  static const Color statusDangerLight = Color(0xFFC7333A);
  static const Color statusSuccess = Color(0xFF46A758);
  static const Color statusSuccessLight = Color(0xFF3B8A4A);

  static const Color borderHairlineDark = Color(0x14FFFFFF);
  static const Color borderHairlineLight = Color(0x14000000);
}

/// 8-px-Grid aus Phase 3 B.3.
class AppSpacing {
  const AppSpacing._();

  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
  static const double xxxl = 48;

  static const double touchTargetPlanning = 48;
  static const double touchTargetDriving = 64;
}
