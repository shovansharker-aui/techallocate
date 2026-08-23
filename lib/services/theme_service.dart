import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Holds the current theme mode (light/dark/system) and persists the
// admin's choice locally so it's remembered between app opens.
class ThemeService extends ChangeNotifier {
  static const _key = 'theme_mode';

  ThemeMode _mode = ThemeMode.system;
  ThemeMode get mode => _mode;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_key);
    _mode = switch (saved) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
    notifyListeners();
  }

  Future<void> setMode(ThemeMode mode) async {
    _mode = mode;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, mode.name);
  }
}

// A single shared instance the whole app reads from — simple app-wide
// state without pulling in a state management package for just this.
final themeService = ThemeService();
