import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motoroute_app/core/theme/app_colors.dart';

void main() {
  test('mapHex liefert das maplibre-Format', () {
    expect(AppColors.accentPrimaryDark.mapHex, '#FF5A1F');
    expect(AppColors.bgBaseDark.mapHex, '#0B0E11');
    expect(AppColors.statusDanger.mapHex, '#E5484D');
    expect(AppColors.statusWarning.mapHex, '#F5A623');
    expect(AppColors.accentSecondary.mapHex, '#2EC4B6');
    expect(AppColors.mapRouteStart.mapHex, '#3DD68C');
    expect(AppColors.mapRouteTraveled.mapHex, '#B8BBC2');
    expect(AppColors.mapUserPosition.mapHex, '#3B82F6');
  });

  test('mapHex ignoriert den Alpha-Kanal', () {
    expect(const Color(0x80123456).mapHex, '#123456');
    expect(const Color(0x00FFFFFF).mapHex, '#FFFFFF');
  });

  test('Karten-Annotationen nutzen keine Farb-Literale', () {
    const files = [
      'lib/features/map/presentation/map_screen.dart',
      'lib/features/navigation_session/active_navigation_screen.dart',
      'lib/features/poi/poi_map_layer.dart',
      'lib/features/routing/route_overview_screen.dart',
    ];
    final literal = RegExp(r"'#[0-9A-Fa-f]{6}'");
    for (final path in files) {
      final hits = literal
          .allMatches(File(path).readAsStringSync())
          .map((m) => m.group(0))
          .toList();
      expect(hits, isEmpty, reason: '$path hat noch Farb-Literale: $hits');
    }
  });
}
