import 'package:flutter/material.dart';

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
  /// Inaktiver Zustand einer Zustandsanzeige (Icon, Griff): muss als
  /// Grafik 3:1 schaffen, bleibt aber gedaempft gegenueber textSecondary.
  static const Color stateIdleDark = Color(0xFF68707B);

  // Karte (Annotationen): Farben ohne eigene Theme-Entsprechung.
  /// Gefahrene Strecke - gedaempft, damit die Reststrecke dominiert, aber
  /// auch mit lineOpacity 0.55 noch 3:1 gegen Wasser im dunklen Stil.
  static const Color mapRouteTraveled = Color(0xFFB8BBC2);
  /// Startmarker der Route.
  static const Color mapRouteStart = Color(0xFF3DD68C);
  /// Eigene Position als GPS-Punkt.
  static const Color mapUserPosition = Color(0xFF3B82F6);

  // Light (zweites Schema, siehe Phase 3 Teil B.1)
  static const Color bgBaseLight = Color(0xFFF5F6F4);
  static const Color bgSurfaceLight = Color(0xFFFFFFFF);
  static const Color bgSurfaceRaisedLight = Color(0xFFF0F1EE);
  static const Color textPrimaryLight = Color(0xFF12151A);
  static const Color textSecondaryLight = Color(0xFF5B6470);
  static const Color textMutedLight = Color(0xFF9AA3AD);
  /// Dunkler als textSecondaryLight: auf der orange getoenten eigenen
  /// Chat-Blase erreicht der Zeitstempel sonst nur 4,03:1.
  static const Color textSecondaryStrongLight = Color(0xFF4A525C);

  /// Akzentfarbe fuer TEXT im hellen Schema (dunkler als die Markenfarbe,
  /// die als Flaeche/Fuellung weiterhin accentPrimaryLight bleibt):
  /// Absendernamen im Chat brauchen 4,5:1 auf hellen Blasen.
  static const Color accentTextLight = Color(0xFFB03A0F);

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


/// Semantische Farben fuer den aktiven Helligkeitsmodus.
///
/// [AppColors] nennt die Tokens pro Schema (`...Dark`/`...Light`); diese
/// Klasse buendelt sie zu Rollen (`textSecondary`, `bgSurface` ...), damit
/// Screens die Helligkeit nicht an jeder Verwendungsstelle selbst
/// unterscheiden muessen. Dunkel bleibt das Standard-Erlebnis (Phase 3 B.1).
class AppPalette {
  const AppPalette({
    required this.bgBase,
    required this.bgSurface,
    required this.bgSurfaceRaised,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.textSecondaryStrong,
    required this.stateIdle,
    required this.switchActiveThumb,
    required this.switchActiveTrack,
    required this.borderHairline,
    required this.accentPrimary,
    required this.accentText,
    required this.accentSecondary,
    required this.statusWarning,
    required this.statusDanger,
    required this.statusSuccess,
    required this.shadow,
  });

  final Color bgBase;
  final Color bgSurface;
  final Color bgSurfaceRaised;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;

  /// Sekundaertext fuer kleine Schriftschnitte auf getoenten Flaechen
  /// (z. B. Zeitstempel in der eigenen Chat-Blase): dunkler als
  /// [textSecondary], damit auch 10-13 pt noch 4,5:1 schaffen.
  final Color textSecondaryStrong;
  final Color stateIdle;

  /// Griff des aktiven Schalters. Im hellen Schema die Flaechenfarbe, damit
  /// er sich gegen die durchgezogene Akzent-2-Spur absetzt (3,46:1 statt
  /// 2,46:1); im dunklen Schema bleibt es der Akzent wie bisher.
  final Color switchActiveThumb;

  /// Spur des aktiven Schalters. `null` laesst den Flutter-Standard stehen,
  /// damit das dunkle Schema exakt seine bisherige Optik behaelt.
  final Color? switchActiveTrack;
  final Color borderHairline;
  final Color accentPrimary;

  /// Akzent als Schriftfarbe (dunkler als [accentPrimary] im hellen
  /// Schema, im dunklen Schema identisch).
  final Color accentText;
  final Color accentSecondary;
  final Color statusWarning;
  final Color statusDanger;
  final Color statusSuccess;

  /// Schatten unter Karten - im hellen Schema deutlich schwacher, sonst
  /// wirken die weissen Karten wie aufgeklebt.
  final Color shadow;

  static const AppPalette dark = AppPalette(
    bgBase: AppColors.bgBaseDark,
    bgSurface: AppColors.bgSurfaceDark,
    bgSurfaceRaised: AppColors.bgSurfaceRaisedDark,
    textPrimary: AppColors.textPrimaryDark,
    textSecondary: AppColors.textSecondaryDark,
    textMuted: AppColors.textMutedDark,
    textSecondaryStrong: AppColors.textSecondaryDark,
    stateIdle: AppColors.stateIdleDark,
    switchActiveThumb: AppColors.accentSecondary,
    switchActiveTrack: null,
    borderHairline: AppColors.borderHairlineDark,
    accentPrimary: AppColors.accentPrimaryDark,
    accentText: AppColors.accentPrimaryDark,
    accentSecondary: AppColors.accentSecondary,
    statusWarning: AppColors.statusWarning,
    statusDanger: AppColors.statusDanger,
    statusSuccess: AppColors.statusSuccess,
    shadow: Color(0x40000000),
  );

  static const AppPalette light = AppPalette(
    bgBase: AppColors.bgBaseLight,
    bgSurface: AppColors.bgSurfaceLight,
    bgSurfaceRaised: AppColors.bgSurfaceRaisedLight,
    textPrimary: AppColors.textPrimaryLight,
    textSecondary: AppColors.textSecondaryLight,
    textMuted: AppColors.textMutedLight,
    textSecondaryStrong: AppColors.textSecondaryStrongLight,
    stateIdle: AppColors.textSecondaryLight,
    switchActiveThumb: AppColors.bgSurfaceLight,
    switchActiveTrack: AppColors.accentSecondaryLight,
    borderHairline: AppColors.borderHairlineLight,
    accentPrimary: AppColors.accentPrimaryLight,
    accentText: AppColors.accentTextLight,
    accentSecondary: AppColors.accentSecondaryLight,
    statusWarning: AppColors.statusWarningLight,
    statusDanger: AppColors.statusDangerLight,
    statusSuccess: AppColors.statusSuccessLight,
    shadow: Color(0x1F000000),
  );

  static AppPalette of(Brightness brightness) =>
      brightness == Brightness.light ? light : dark;
}

/// Palette des aktiven Schemas fuer Widget-Code.
///
/// Screens, die Flaechen und Texte selbst faerben, loesen die Rollen damit
/// in einer Zeile auf (`context.palette.textPrimary`) statt an jeder Stelle
/// `Theme.of(context)` zu wiederholen.
extension AppPaletteContext on BuildContext {
  AppPalette get palette => AppPalette.of(Theme.of(this).brightness);
}

/// maplibre_gl nimmt Farben als '#RRGGBB'-String entgegen. Der Umweg ueber
/// diese Erweiterung haelt das Color-Token zur einzigen Quelle: ein
/// Theme-Wechsel wirkt damit auch auf die Kartenebene, und der
/// Kontrast-Audit erfasst die Annotationen statt an Literalen vorbeizulaufen.
extension MapAnnotationHex on Color {
  String get mapHex =>
      '#${toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';
}
