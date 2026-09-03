import 'package:flutter/material.dart';
import '../models/app_user.dart';
import '../widgets_admin_monitoring_panel.dart';
import 'admin_web_settings_screen.dart';
import 'water_plant_overview_screen.dart';
import 'archive_management_screen.dart';
import 'admin_mobile_shell.dart';

enum _AdminSection { maintenance, waterPlant, archive, settings }

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
      case _AdminSection.maintenance: return 'RPGF Maintenance Tracker';
      case _AdminSection.waterPlant: return 'Water Plant';
      case _AdminSection.archive: return 'Archive Management';
      case _AdminSection.settings: return 'Settings';
    }
  }

  Widget get _content {
    switch (_section) {
      case _AdminSection.maintenance:
        return SingleChildScrollView(padding: const EdgeInsets.all(24), child: const AdminMonitoringPanel());
      case _AdminSection.waterPlant:
        return const WaterPlantOverviewBody();
      case _AdminSection.archive:
        return const ArchiveManagementBody();
      case _AdminSection.settings:
        return const AdminSettingsBody();
    }
  }

  void _select(_AdminSection section, BuildContext context) {
    setState(() => _section = section);
  }

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 950;
    // Mobile browser / PWA width: use the exact same pill-bottom-nav
    // shell as native Android, instead of the sidebar/drawer below —
    // desktop-width web is the only surface that still gets that.
    if (compact) {
      return AdminMobileShell(user: widget.user, onLogout: widget.onLogout);
    }
    return Scaffold(
      body: Row(children: [
        SizedBox(width: 250, child: _sidebar(context)),
        Expanded(child: Column(children: [
          _topBar(context),
          Expanded(child: _content),
        ])),
      ]),
    );
  }

  Widget _sidebar(BuildContext context) => Material(color: Theme.of(context).colorScheme.surfaceContainerLowest, child: SafeArea(child: Column(children: [
    const Padding(padding: EdgeInsets.fromLTRB(20, 28, 20, 24), child: Row(children: [Image(image: AssetImage('assets/logo.png'), height: 34), SizedBox(width: 12), Text('TechAllocate', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold))])),
    ListTile(selected: _section == _AdminSection.maintenance, leading: const Icon(Icons.dashboard_outlined), title: const Text('Maintenance'), onTap: () => _select(_AdminSection.maintenance, context)),
    ListTile(selected: _section == _AdminSection.waterPlant, leading: const Icon(Icons.water_drop_outlined), title: const Text('Water Plant'), onTap: () => _select(_AdminSection.waterPlant, context)),
    ListTile(selected: _section == _AdminSection.archive, leading: const Icon(Icons.archive_outlined), title: const Text('Archive Management'), onTap: () => _select(_AdminSection.archive, context)),
    ListTile(selected: _section == _AdminSection.settings, leading: const Icon(Icons.settings_outlined), title: const Text('Settings'), onTap: () => _select(_AdminSection.settings, context)),
    const Spacer(), const Divider(height: 1),
    ListTile(leading: const CircleAvatar(child: Icon(Icons.person)), title: Text(widget.user.name, maxLines: 1, overflow: TextOverflow.ellipsis)),
    ListTile(leading: const Icon(Icons.logout), title: const Text('Log out'), onTap: widget.onLogout),
  ])));

  Widget _topBar(BuildContext context) {
    return Material(
      elevation: 1,
      child: SizedBox(
        height: 72,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Row(
            children: [
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
