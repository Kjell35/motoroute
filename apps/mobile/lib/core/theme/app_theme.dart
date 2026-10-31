import 'package:flutter/material.dart';
import 'app_colors.dart';
import 'app_typography.dart';

/// Bündelt die Tokens aus app_colors.dart/app_typography.dart zu
/// Flutter-ThemeData. Dark ist das Standard-Theme (siehe Phase 3 Teil
/// B.1: "Dark-first, nicht nur Dark Mode als Option").
class AppTheme {
  const AppTheme._();

  static ThemeData get dark => ThemeData(
        useMaterial3: true,
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
        appBarTheme: const AppBarTheme(
          backgroundColor: AppColors.bgBaseDark,
          foregroundColor: AppColors.textPrimaryDark,
          elevation: 0,
          centerTitle: false,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: AppColors.bgSurfaceDark,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 18, vertical: 17),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: AppColors.borderHairlineDark),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: AppColors.borderHairlineDark),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(
                color: AppColors.accentPrimaryDark, width: 1.5),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            minimumSize: const Size(0, 54),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            textStyle: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      );

  static ThemeData get light => ThemeData(
        useMaterial3: true,
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
        appBarTheme: const AppBarTheme(
          backgroundColor: AppColors.bgBaseLight,
          foregroundColor: AppColors.textPrimaryLight,
          elevation: 0,
          centerTitle: false,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: AppColors.bgSurfaceLight,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 18, vertical: 17),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: AppColors.borderHairlineLight),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: AppColors.borderHairlineLight),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(
                color: AppColors.accentPrimaryLight, width: 1.5),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            minimumSize: const Size(0, 54),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            textStyle: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      );
}
