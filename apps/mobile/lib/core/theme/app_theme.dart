import 'package:flutter/material.dart';
import 'app_colors.dart';
import 'app_typography.dart';

/// Bündelt die Tokens aus app_colors.dart/app_typography.dart zu
/// Flutter-ThemeData. Dark ist das Standard-Theme (siehe Phase 3 Teil
/// B.1: "Dark-first, nicht nur Dark Mode als Option").
class AppTheme {
  const AppTheme._();

  static ThemeData get dark => ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: AppColors.bgBaseDark,
        colorScheme: const ColorScheme.dark(
          primary: AppColors.accentPrimaryDark,
          secondary: AppColors.accentSecondary,
          surface: AppColors.bgSurfaceDark,
          error: AppColors.statusDanger,
        ),
        textTheme: const TextTheme(
          displayLarge: AppTypography.display,
          headlineSmall: AppTypography.title,
          bodyLarge: AppTypography.body,
          bodyMedium: AppTypography.bodyStrong,
          labelSmall: AppTypography.caption,
        ).apply(
          bodyColor: AppColors.textPrimaryDark,
          displayColor: AppColors.textPrimaryDark,
        ),
      );

  static ThemeData get light => ThemeData(
        brightness: Brightness.light,
        scaffoldBackgroundColor: AppColors.bgBaseLight,
        colorScheme: const ColorScheme.light(
          primary: AppColors.accentPrimaryLight,
          secondary: AppColors.accentSecondaryLight,
          surface: AppColors.bgSurfaceLight,
          error: AppColors.statusDangerLight,
        ),
        textTheme: const TextTheme(
          displayLarge: AppTypography.display,
          headlineSmall: AppTypography.title,
          bodyLarge: AppTypography.body,
          bodyMedium: AppTypography.bodyStrong,
          labelSmall: AppTypography.caption,
        ).apply(
          bodyColor: AppColors.textPrimaryLight,
          displayColor: AppColors.textPrimaryLight,
        ),
      );
}
