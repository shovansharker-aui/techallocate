import 'package:flutter/material.dart';
import '../models/app_user.dart';
import '../widgets_admin_monitoring_panel.dart';
import 'admin_web_settings_screen.dart';
import 'water_plant_overview_screen.dart';
import 'backup_export_screen.dart';

enum _AdminSection { maintenance, waterPlant, backup, settings }

// The web admin shell — sidebar (desktop) / drawer (mobile web) that
// stays on screen while switching between sections, instead of each
// section being a full-screen route push that replaces (and hides) the
// nav entirely. Only the four top-level sections here behave this way;
// screens reached by drilling further in (Add Personnel, Machines, etc.)
// still push as their own full screens with a normal back arrow — this
// is about keeping the main sections reachable, not flattening all
// navigation.
class AdminWebDashboardScreen extends StatefulWidget {
  final AppUser user;
  final VoidCallback onLogout;
  const AdminWebDashboardScreen({super.key, required this.user, required this.onLogout});

  @override
  State<AdminWebDashboardScreen> createState() => _AdminWebDashboardScreenState();
}

class _AdminWebDashboardScreenState extends State<AdminWebDashboardScreen> {
  _AdminSection _section = _AdminSection.maintenance;

  String get _title {
    switch (_section) {
      case _AdminSection.maintenance: return 'Admin Dashboard';
      case _AdminSection.waterPlant: return 'Water Plant';
      case _AdminSection.backup: return 'Backup / Export';
      case _AdminSection.settings: return 'Settings';
    }
  }

  Widget get _content {
    switch (_section) {
      case _AdminSection.maintenance:
        return SingleChildScrollView(padding: const EdgeInsets.all(24), child: const AdminMonitoringPanel());
      case _AdminSection.waterPlant:
        return const WaterPlantOverviewBody();
      case _AdminSection.backup:
        return const BackupExportBody();
      case _AdminSection.settings:
        return const AdminSettingsBody();
    }
  }

  void _select(_AdminSection section, BuildContext context) {
    setState(() => _section = section);
    if (MediaQuery.sizeOf(context).width < 950) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 950;
    return Scaffold(
      body: Row(children: [
        if (!compact) SizedBox(width: 250, child: _sidebar(context)),
        Expanded(child: Column(children: [
          _topBar(context, compact),
          Expanded(child: _content),
        ])),
      ]),
      drawer: compact ? Drawer(child: _sidebar(context)) : null,
      // Flutter's default edge-swipe zone for opening a drawer is a thin
      // sliver right at the screen edge — barely triggerable on a touch
      // screen, and easy to lose to a browser's own edge-swipe gestures
      // on web/PWA. Widening it makes the swipe-to-open gesture reliable
      // on the web build the same way it already is on native Android.
      drawerEdgeDragWidth: compact ? MediaQuery.sizeOf(context).width * 0.5 : null,
      drawerEnableOpenDragGesture: compact,
    );
  }

  Widget _sidebar(BuildContext context) => Material(color: Theme.of(context).colorScheme.surfaceContainerLowest, child: SafeArea(child: Column(children: [
    const Padding(padding: EdgeInsets.fromLTRB(20, 28, 20, 24), child: Row(children: [Icon(Icons.engineering, size: 34), SizedBox(width: 12), Text('TechAllocate', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold))])),
    ListTile(selected: _section == _AdminSection.maintenance, leading: const Icon(Icons.dashboard_outlined), title: const Text('Maintenance'), onTap: () => _select(_AdminSection.maintenance, context)),
    ListTile(selected: _section == _AdminSection.waterPlant, leading: const Icon(Icons.water_drop_outlined), title: const Text('Water Plant'), onTap: () => _select(_AdminSection.waterPlant, context)),
    ListTile(selected: _section == _AdminSection.backup, leading: const Icon(Icons.file_download_outlined), title: const Text('Backup / Export'), onTap: () => _select(_AdminSection.backup, context)),
    ListTile(selected: _section == _AdminSection.settings, leading: const Icon(Icons.settings_outlined), title: const Text('Settings'), onTap: () => _select(_AdminSection.settings, context)),
    const Spacer(), const Divider(height: 1),
    ListTile(leading: const CircleAvatar(child: Icon(Icons.person)), title: Text(widget.user.name, maxLines: 1, overflow: TextOverflow.ellipsis)),
    ListTile(leading: const Icon(Icons.logout), title: const Text('Log out'), onTap: widget.onLogout),
  ])));

  Widget _topBar(BuildContext context, bool compact) {
    return Material(
      elevation: 1,
      child: SizedBox(
        height: 72,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Row(
            children: [
              if (compact)
                Builder(
                  builder: (context) => IconButton(
                    icon: const Icon(Icons.menu),
                    onPressed: () => Scaffold.of(context).openDrawer(),
                  ),
                ),
              Text(
                _title,
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
