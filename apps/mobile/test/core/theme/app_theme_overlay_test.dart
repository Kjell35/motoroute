import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motoroute_app/core/theme/app_theme.dart';

void main() {
  group('Statusleisten-Symbole', () {
    test('heller Hintergrund fordert dunkle Symbole an', () {
      const style = AppTheme.statusOverlayLight;
      expect(style.statusBarIconBrightness, Brightness.dark);
      expect(style.statusBarBrightness, Brightness.light);
      expect(style.statusBarColor, const Color(0x00000000));
    });

    test('dunkler Hintergrund fordert helle Symbole an', () {
      const style = AppTheme.statusOverlayDark;
      expect(style.statusBarIconBrightness, Brightness.light);
      expect(style.statusBarBrightness, Brightness.dark);
    });
  });
}
