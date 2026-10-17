import 'package:flutter/widgets.dart';

/// Direkte Übersetzung der Farb-Tokens aus Phase 3, Teil B.1.
/// Absichtlich als benannte Konstanten statt generischer Theme-Farben,
/// damit jede Verwendungsstelle im Code erkennen lässt, WELCHE
/// semantische Rolle eine Farbe hat (z. B. `AppColors.statusWarning`
/// statt `Colors.orange`) - wichtig, weil Rot/Orange hier bewusst als
/// Markenfarbe UND als Warnfarbe unterschiedlich eingesetzt wird
/// (siehe Begründung in Phase 3 Teil B.1) und das im Code nicht
/// verwechselbar sein darf.
class AppColors {
  const AppColors._();

  // Dark (Standard-Erlebnis, siehe Phase 3 Teil B.1)
  static const Color bgBaseDark = Color(0xFF0B0E11);
  static const Color bgSurfaceDark = Color(0xFF151A1F);
  static const Color bgSurfaceRaisedDark = Color(0xFF1E252C);
  static const Color textPrimaryDark = Color(0xFFF5F6F4);
  static const Color textSecondaryDark = Color(0xFF9AA3AD);
  static const Color textMutedDark = Color(0xFF5B6470);

  // Light (zweites Schema, siehe Phase 3 Teil B.1)
  static const Color bgBaseLight = Color(0xFFF5F6F4);
  static const Color bgSurfaceLight = Color(0xFFFFFFFF);
  static const Color bgSurfaceRaisedLight = Color(0xFFF0F1EE);
  static const Color textPrimaryLight = Color(0xFF12151A);
  static const Color textSecondaryLight = Color(0xFF5B6470);
  static const Color textMutedLight = Color(0xFF9AA3AD);

  // Marken-/Akzentfarben - modusunabhängig leicht unterschiedlich für
  // ausreichenden Kontrast (siehe Tabelle Phase 3 Teil B.1).
  static const Color accentPrimaryDark = Color(0xFFFF5A1F);
  static const Color accentPrimaryLight = Color(0xFFE64E17);
  static const Color accentSecondary = Color(0xFF2EC4B6);
  static const Color accentSecondaryLight = Color(0xFF1E9A8F);

  // Status
  static const Color statusWarning = Color(0xFFF5A623);
  static const Color statusWarningLight = Color(0xFFC97F0E);
  static const Color statusDanger = Color(0xFFE5484D);
  static const Color statusDangerLight = Color(0xFFC7333A);
  /// Erfolg (Freigabe, Bestätigung) - Marktplatz & Moderation.
  static const Color statusSuccess = Color(0xFF46A758);
  static const Color statusSuccessLight = Color(0xFF3B8A4A);

  static const Color borderHairlineDark = Color(0x14FFFFFF); // rgba(255,255,255,0.08)
  static const Color borderHairlineLight = Color(0x14000000); // rgba(0,0,0,0.08)
}
