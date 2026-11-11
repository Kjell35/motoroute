import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motoroute_app/core/theme/app_colors.dart';

/// WCAG-Kontrastverhaeltnis zweier Farben (1:1 bis 21:1).
double _contrast(Color a, Color b) {
  double channel(double c) =>
      c <= 0.03928 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
  double luminance(Color c) =>
      0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b);
  final la = luminance(a);
  final lb = luminance(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

/// Die Stellen, an denen das helle Schema unter der Grenze lag:
/// Akzent als Schriftfarbe, Zeitstempel auf der eigenen Chat-Blase,
/// gedaempfte Symbole auf Karten, Beschriftung auf der Akzentflaeche,
/// der Griff des aktiven Schalters und die Beschriftung auf der
/// Teal-Akzentflaeche (Route-Scan-Button).
void main() {
  const p = AppPalette.light;

  test('Akzent als Schrift erreicht 4,5:1 auf hellen Flaechen', () {
    expect(_contrast(p.accentText, p.bgSurfaceRaised), greaterThanOrEqualTo(4.5));
    expect(_contrast(p.accentText, p.bgSurface), greaterThanOrEqualTo(4.5));
  });

  test('Zeitstempel auf der eigenen Chat-Blase erreicht 4,5:1', () {
    // Die eigene Blase ist die Akzentfarbe mit 25 % Deckkraft auf dem
    // Scaffold-Hintergrund (siehe conversation_screen).
    final ownBubble = Color.alphaBlend(
      p.accentPrimary.withValues(alpha: 0.25),
      p.bgBase,
    );
    expect(_contrast(p.textSecondaryStrong, ownBubble),
        greaterThanOrEqualTo(4.5));
    expect(_contrast(p.textPrimary, ownBubble), greaterThanOrEqualTo(4.5));
  });

  test('Gedaempfte Symbole auf Karten erreichen 3:1', () {
    expect(_contrast(p.stateIdle, p.bgSurface), greaterThanOrEqualTo(3.0));
    expect(_contrast(p.stateIdle, p.bgBase), greaterThanOrEqualTo(3.0));
  });

  test('Beschriftung auf der Akzentflaeche erreicht 4,5:1', () {
    expect(_contrast(p.textPrimary, p.accentPrimary),
        greaterThanOrEqualTo(4.5));
  });

  test('Aktiver Schalter: Griff hebt sich mit 3:1 von der Spur ab', () {
    expect(p.switchActiveTrack, isNotNull);
    expect(_contrast(p.switchActiveThumb, p.switchActiveTrack!),
        greaterThanOrEqualTo(3.0));
    // Der Griff muss auch gegen die Karte erkennbar bleiben.
    expect(_contrast(p.switchActiveThumb, p.bgSurface),
        lessThanOrEqualTo(1.1));
  });

  test('Beschriftung auf der Teal-Flaeche erreicht 4,5:1', () {
    // "Route von anderer App scannen" (FilledButton.tonalIcon) nutzt den
    // Primaertext des Schemas; weisse Schrift kam nur auf 3,46:1.
    expect(_contrast(p.textPrimary, p.accentSecondary),
        greaterThanOrEqualTo(4.5));
  });

  test('Das dunkle Schema bleibt bei den bisherigen Werten', () {
    const d = AppPalette.dark;
    expect(d.accentText, AppColors.accentPrimaryDark);
    expect(d.textSecondaryStrong, AppColors.textSecondaryDark);
  });

  test('Das dunkle Schema behaelt die bisherige Schalter-Optik', () {
    const d = AppPalette.dark;
    expect(d.switchActiveThumb, AppColors.accentSecondary);
    // null = Flutter-Standardspur, wie vor der Umstellung.
    expect(d.switchActiveTrack, isNull);
  });
}
