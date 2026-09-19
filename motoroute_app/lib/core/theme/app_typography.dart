import 'package:flutter/material.dart';
import 'app_colors.dart';

/// Übersetzung der Typografie-Tokens aus Phase 3, Teil B.2.
///
/// WICHTIG (siehe Phase 3 Teil B.2): `navInstruction` und `display`
/// nutzen `FontFeature.tabularFigures()` - das ist kein Stilmittel,
/// sondern verhindert, dass sich Restdistanz/ETA/Geschwindigkeit beim
/// Update seitlich verschieben. Das darf bei künftigen Änderungen an
/// diesen beiden Styles nicht versehentlich entfernt werden.
///
/// Die konkrete Schriftart (Inter/Space Grotesk, siehe Phase 3) ist
/// noch nicht final gewählt - `fontFamily` bleibt hier bewusst null
/// (System-Default), bis ein Schriftmuster auf echten Geräten geprüft
/// wurde (siehe Phase 3 Teil D: "finale Wahl in Phase 4 ... prüfen").
class AppTypography {
  const AppTypography._();

  static const TextStyle display = TextStyle(
    fontSize: 48,
    fontWeight: FontWeight.w600,
    fontFeatures: [FontFeature.tabularFigures()],
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
    color: AppColors.textSecondaryDark,
  );

  static const TextStyle navInstruction = TextStyle(
    fontSize: 28,
    fontWeight: FontWeight.w600,
    fontFeatures: [FontFeature.tabularFigures()],
  );
}
