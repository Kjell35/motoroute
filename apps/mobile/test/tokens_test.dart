import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:motoroute/design/tokens/mr_colors.dart';
import 'package:motoroute/design/tokens/mr_theme.dart';

void main() {
  group('Design-Tokens „Midnight Asphalt“ (docs/05-design-system.md)', () {
    test('Farb-Tokens entsprechen der Spezifikation', () {
      expect(MrColors.base, const Color(0xFF0E1116));
      expect(MrColors.card, const Color(0xFF161B22));
      expect(MrColors.raised, const Color(0xFF1F2630));
      expect(MrColors.stroke, const Color(0xFF2A323D));
      expect(MrColors.textPrimary, const Color(0xFFF2F5F7));
      expect(MrColors.textSecondary, const Color(0xFF9AA6B2));
      expect(MrColors.accentPrimary, const Color(0xFFFF6A2B));
      expect(MrColors.accentSecondary, const Color(0xFF3DD6C3));
      expect(MrColors.warning, const Color(0xFFFFC53D));
      expect(MrColors.danger, const Color(0xFFFF3B30));
    });

    test('Theme ist dark-first mit Signal-Orange als Primärakzent', () {
      final theme = MrTheme.dark();
      expect(theme.brightness, Brightness.dark);
      expect(theme.colorScheme.primary, MrColors.accentPrimary);
      expect(theme.scaffoldBackgroundColor, MrColors.base);
    });
  });
}
