import 'package:flutter/material.dart';

import 'mr_colors.dart';

/// Typo-, Spacing-, Radius- und Motion-Tokens
/// (Quelle: docs/05-design-system.md, Abschnitte 3–4).
abstract final class MrTypography {
  static const String fontFamily = 'Inter';

  /// displayManeuver: 44/700 tabular (Turn-Banner-Distanz).
  static const TextStyle displayManeuver = TextStyle(
    fontFamily: fontFamily,
    fontSize: 44,
    fontWeight: FontWeight.w700,
    height: 1.1,
  );

  /// streetName: 24/600.
  static const TextStyle streetName = TextStyle(
    fontFamily: fontFamily,
    fontSize: 24,
    fontWeight: FontWeight.w600,
    height: 1.2,
  );

  /// title: 20/600.
  static const TextStyle title = TextStyle(
    fontFamily: fontFamily,
    fontSize: 20,
    fontWeight: FontWeight.w600,
  );

  /// body: 16/400.
  static const TextStyle body = TextStyle(
    fontFamily: fontFamily,
    fontSize: 16,
    fontWeight: FontWeight.w400,
  );

  /// label: 13/500.
  static const TextStyle label = TextStyle(
    fontFamily: fontFamily,
    fontSize: 13,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.2,
  );
}

abstract final class MrSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
}

abstract final class MrRadii {
  static const double card = 20;
  static const double button = 16;
  static const double sheet = 28;
  static const double dialog = 24;
}

abstract final class MrMotion {
  /// Standard-Dauer; im Energiesparmodus auf 0 ms gemappt
  /// (siehe docs/08-energy-saving.md).
  static const Duration standard = Duration(milliseconds: 200);
  static const Duration fast = Duration(milliseconds: 150);
}

/// AppTheme: Dark-first (Primärthema laut Design-System).
abstract final class MrTheme {
  static ThemeData dark() {
    final scheme = ColorScheme.dark(
      surface: MrColors.base,
      primary: MrColors.accentPrimary,
      secondary: MrColors.accentSecondary,
      error: MrColors.danger,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: MrColors.base,
      fontFamily: MrTypography.fontFamily,
      appBarTheme: const AppBarTheme(
        backgroundColor: MrColors.base,
        foregroundColor: MrColors.textPrimary,
        elevation: 0,
      ),
      cardTheme: const CardThemeData(
        color: MrColors.card,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(MrRadii.card)),
          side: BorderSide(color: MrColors.stroke),
        ),
      ),
      chipTheme: const ChipThemeData(
        backgroundColor: MrColors.raised,
        selectedColor: MrColors.accentPrimary,
        labelStyle: MrTypography.label,
        side: BorderSide(color: MrColors.stroke),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: MrColors.accentPrimary,
          foregroundColor: MrColors.base,
          minimumSize: const Size(0, 56),
          textStyle: MrTypography.title,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(MrRadii.button),
          ),
        ),
      ),
    );
  }
}
