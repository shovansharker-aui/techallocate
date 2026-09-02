import 'package:flutter/material.dart';
import '../models/app_user.dart';
import '../widgets_admin_monitoring_panel.dart';
import 'admin_web_settings_screen.dart';
import 'water_plant_overview_screen.dart';
import 'backup_export_screen.dart';

class AdminWebDashboardScreen extends StatelessWidget {
  final AppUser user;
  final VoidCallback onLogout;
  const AdminWebDashboardScreen({super.key, required this.user, required this.onLogout});

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 950;
    return Scaffold(
      body: Row(children: [
        if (!compact) SizedBox(width: 250, child: _sidebar(context)),
        Expanded(child: Column(children: [
          _topBar(context, compact),
          Expanded(child: SingleChildScrollView(padding: const EdgeInsets.all(24), child: const AdminMonitoringPanel())),
        ])),
      ]),
      drawer: compact ? Drawer(child: _sidebar(context)) : null,
    );
  }

  Widget _sidebar(BuildContext context) => Material(color: Theme.of(context).colorScheme.surfaceContainerLowest, child: SafeArea(child: Column(children: [
    const Padding(padding: EdgeInsets.fromLTRB(20, 28, 20, 24), child: Row(children: [Icon(Icons.engineering, size: 34), SizedBox(width: 12), Text('TechAllocate', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold))])),
    ListTile(selected: true, leading: const Icon(Icons.dashboard_outlined), title: const Text('Maintenance'), onTap: () { if (MediaQuery.sizeOf(context).width < 950) Navigator.of(context).pop(); }),
    ListTile(leading: const Icon(Icons.water_drop_outlined), title: const Text('Water Plant'), onTap: () { if (MediaQuery.sizeOf(context).width < 950) Navigator.of(context).pop(); Navigator.of(context).push(MaterialPageRoute(builder: (_) => const WaterPlantOverviewScreen())); }),
    ListTile(leading: const Icon(Icons.file_download_outlined), title: const Text('Backup / Export'), onTap: () { if (MediaQuery.sizeOf(context).width < 950) Navigator.of(context).pop(); Navigator.of(context).push(MaterialPageRoute(builder: (_) => const BackupExportScreen())); }),
    ListTile(leading: const Icon(Icons.settings_outlined), title: const Text('Settings'), onTap: () { if (MediaQuery.sizeOf(context).width < 950) Navigator.of(context).pop(); Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AdminWebSettingsScreen())); }),
    const Spacer(), const Divider(height: 1),
    ListTile(leading: const CircleAvatar(child: Icon(Icons.person)), title: Text(user.name, maxLines: 1, overflow: TextOverflow.ellipsis), subtitle: const Text('Admin')),
    ListTile(leading: const Icon(Icons.logout), title: const Text('Log out'), onTap: onLogout),
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
              const Text(
                'Admin Dashboard',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
      ),
    );
  }
}