import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The four choices Settings offers. System/Light/Dark map straight
/// onto Flutter's own ThemeMode; Colorful is this app's own fourth
/// look — a distinct, vivid theme rather than a light/dark variant, so
/// it can't be represented by ThemeMode alone (see main.dart, where
/// picking it forces both `theme` and `darkTheme` to the same colorful
/// ThemeData regardless of the device's own light/dark setting).
enum AppThemeMode { system, light, dark, colorful }

// Holds the current theme mode and persists the admin's choice locally
// so it's remembered between app opens.
class ThemeService extends ChangeNotifier {
  static const _key = 'theme_mode';

  AppThemeMode _mode = AppThemeMode.system;
  AppThemeMode get mode => _mode;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_key);
    _mode = switch (saved) {
      'light' => AppThemeMode.light,
      'dark' => AppThemeMode.dark,
      'colorful' => AppThemeMode.colorful,
      _ => AppThemeMode.system,
    };
    notifyListeners();
  }

  Future<void> setMode(AppThemeMode mode) async {
    _mode = mode;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, mode.name);
  }
}

// A single shared instance the whole app reads from — simple app-wide
// state without pulling in a state management package for just this.
final themeService = ThemeService();
