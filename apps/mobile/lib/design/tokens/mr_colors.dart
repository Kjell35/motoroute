import 'package:flutter/material.dart';

/// Farb-Tokens des Design-Systems „Midnight Asphalt“
/// (Quelle der Wahrheit: docs/05-design-system.md, Abschnitt 2).
abstract final class MrColors {
  // Surfaces
  static const Color base = Color(0xFF0E1116);
  static const Color card = Color(0xFF161B22);
  static const Color raised = Color(0xFF1F2630);
  static const Color stroke = Color(0xFF2A323D);

  // Text
  static const Color textPrimary = Color(0xFFF2F5F7);
  static const Color textSecondary = Color(0xFF9AA6B2);

  // Akzente
  static const Color accentPrimary = Color(0xFFFF6A2B);
  static const Color accentSecondary = Color(0xFF3DD6C3);

  // Status
  static const Color warning = Color(0xFFFFC53D);
  static const Color danger = Color(0xFFFF3B30);
}
