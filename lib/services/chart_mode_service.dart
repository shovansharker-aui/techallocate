import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum ChartMode { sunburst, treemap }

// Holds the admin's chosen chart style (sunburst/treemap) and persists it
// locally, the same way ThemeService persists light/dark/system.
//
// This used to be stored in Firestore, in a document tucked inside the
// 'users' collection. That write was being silently rejected — almost
// certainly because that collection's security rules validate the shape
// of a real employee record (role, PIN, etc.), and a bare
// {'chartMode': 'treemap'} document doesn't match that shape, so
// Firestore refused it without any error ever reaching the UI: the
// Segmented Button just snapped back once the (unchanged) document came
// back through the stream. A chart-style preference doesn't need to sync
// across devices anyway — it's a per-admin display preference, exactly
// like the theme — so storing it locally sidesteps the whole problem.
class ChartModeService extends ChangeNotifier {
  static const _key = 'chart_mode';

  ChartMode _mode = ChartMode.sunburst;
  ChartMode get mode => _mode;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_key);
    _mode = saved == 'treemap' ? ChartMode.treemap : ChartMode.sunburst;
    notifyListeners();
  }

  Future<void> setMode(ChartMode mode) async {
    _mode = mode;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, mode.name);
  }
}

final chartModeService = ChartModeService();
