import 'package:flutter/material.dart';
import '../models/app_user.dart';
import '../widgets_admin_monitoring_panel.dart';
import '../widgets_pill_bottom_nav.dart';
import 'archive_management_screen.dart';
import 'water_plant_overview_screen.dart';
import 'settings_screen.dart';
import 'completed_tasks_screen.dart';

/// The admin experience for native Android, Android browser, and PWA —
/// a pill-shaped bottom nav with 5 destinations (Archive, Water Plant,
/// Home, Settings, History) instead of a side drawer. Desktop-width web
/// keeps its own separate sidebar shell (AdminWebDashboardScreen)
/// unchanged; this one is used by admin_dashboard_screen.dart directly
/// (native is always "mobile-shaped") and by AdminWebDashboardScreen
/// only when the browser viewport is narrow.
class AdminMobileShell extends StatefulWidget {
  final AppUser user;
  final VoidCallback onLogout;
  const AdminMobileShell({super.key, required this.user, required this.onLogout});

  @override
  State<AdminMobileShell> createState() => _AdminMobileShellState();
}

class _AdminMobileShellState extends State<AdminMobileShell> {
  int _index = 2; // Home

  static const _titles = ['Archive', 'Water Plant', 'RPGF Maintenance Tracker', 'Settings', 'History'];

  Widget get _content {
    switch (_index) {
      case 0: return const ArchiveManagementBody();
      case 1: return const WaterPlantOverviewBody();
      case 2: return SingleChildScrollView(padding: const EdgeInsets.all(16), child: const AdminMonitoringPanel());
      case 3: return const SettingsBody();
      case 4: return const CompletedTasksBody();
      default: return const SizedBox.shrink();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_titles[_index]),
        actions: [
          IconButton(icon: const Icon(Icons.logout), tooltip: 'Log out', onPressed: widget.onLogout),
          const Padding(
            padding: EdgeInsets.only(right: 16, left: 4),
            child: Image(image: AssetImage('assets/renata_logo.png'), height: 32),
          ),
        ],
      ),
      body: _content,
      extendBody: true,
      bottomNavigationBar: PillBottomNav(currentIndex: _index, onTap: (i) => setState(() => _index = i)),
    );
  }
}
