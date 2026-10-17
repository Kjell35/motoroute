import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// App-weiter Hell/Dunkel-Toggle (System/Hell/Dunkel), geräteweit
/// persistiert (shared_preferences, überlebt App-Neustarts).
///
/// Vorher war die App-UI fest dunkel (ThemeMode.dark in main.dart) -
/// nur der KARTENSTIL hatte eine Hell/Dunkel-Wahl. Dieser Controller
/// macht die Einstellungs-Option ehrlich: Sie ändert jetzt tatsächlich
/// das UI-Theme, nicht nur die Karte.
enum AppThemeMode { system, light, dark }

class ThemeModeController extends StateNotifier<AppThemeMode> {
  ThemeModeController() : super(AppThemeMode.dark) {
    _restore();
  }

  static const _kKey = 'app.themeMode';

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    state = _fromString(prefs.getString(_kKey));
  }

  Future<void> set(AppThemeMode mode) async {
    state = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kKey, _toString(mode));
  }

  static AppThemeMode _fromString(String? raw) => switch (raw) {
        'light' => AppThemeMode.light,
        'system' => AppThemeMode.system,
        _ => AppThemeMode.dark,
      };

  static String _toString(AppThemeMode mode) => switch (mode) {
        AppThemeMode.light => 'light',
        AppThemeMode.system => 'system',
        AppThemeMode.dark => 'dark',
      };
}

/// Mappt auf Flutters ThemeMode für MaterialApp.
final themeModeControllerProvider =
    StateNotifierProvider<ThemeModeController, AppThemeMode>((ref) {
  return ThemeModeController();
});

/// Convenience für main.dart: AppThemeMode -> Flutter ThemeMode.
extension AppThemeModeX on AppThemeMode {
  ThemeMode get flutterMode => switch (this) {
        AppThemeMode.light => ThemeMode.light,
        AppThemeMode.dark => ThemeMode.dark,
        AppThemeMode.system => ThemeMode.system,
      };
}
