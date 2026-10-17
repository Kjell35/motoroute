import 'package:flutter/material.dart';

/// Typografie-Tokens aus der alten MotoRoute-App (v1.0.x, Phase 3 B.2).
/// `fontFamily` bleibt bewusst null (System-Default) wie im Original.
class AppTypography {
  const AppTypography._();

  static const TextStyle display = TextStyle(
    fontSize: 48,
    fontWeight: FontWeight.w600,
    // Tabellenziffern (tnum) — verhindert, dass Restdistanz/ETA beim
    // Update seitlich zappeln (Phase 3 B.2, constexprsichere Variante).
    fontFeatures: [FontFeature('tnum')],
  );

  static const TextStyle title = TextStyle(
    fontSize: 24,
    fontWeight: FontWeight.w600,
  );

  static const TextStyle body = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w400,
  );

  static const TextStyle bodyStrong = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w600,
  );

  static const TextStyle caption = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w400,
    color: Color(0xFF9AA3AD), // AppColors.textSecondaryDark
  );

  static const TextStyle navInstruction = TextStyle(
    fontSize: 28,
    fontWeight: FontWeight.w600,
    fontFeatures: [FontFeature('tnum')],
  );
}
