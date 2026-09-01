import 'package:flutter/material.dart';
import '../models/app_user.dart';
import '../widgets_admin_monitoring_panel.dart';
import 'settings_screen.dart';
import 'water_plant_overview_screen.dart';
import '../widgets_root_back_scope.dart';

class AdminDashboardScreen extends StatelessWidget {
  final AppUser user;
  final VoidCallback onLogout;
  const AdminDashboardScreen({super.key, required this.user, required this.onLogout});

  @override
  Widget build(BuildContext context) {
    return RootBackScope(child: Scaffold(
      appBar: AppBar(title: const Text('Maintenance'), actions: [
        IconButton(icon: const Icon(Icons.settings_outlined), tooltip: 'Settings', onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsScreen()))),
        IconButton(icon: const Icon(Icons.logout), tooltip: 'Log out', onPressed: onLogout),
      ]),
      drawer: Drawer(
        child: SafeArea(
          child: Column(
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 24, 20, 16),
                child: Row(children: [
                  Icon(Icons.engineering, size: 30),
                  SizedBox(width: 10),
                  Text('TechAllocate', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                ]),
              ),
              ListTile(
                selected: true,
                leading: const Icon(Icons.dashboard_outlined),
                title: const Text('Maintenance'),
                onTap: () => Navigator.of(context).pop(),
              ),
              ListTile(
                leading: const Icon(Icons.water_drop_outlined),
                title: const Text('Water Plant'),
                onTap: () {
                  Navigator.of(context).pop();
                  Navigator.of(context).push(MaterialPageRoute(builder: (_) => const WaterPlantOverviewScreen()));
                },
              ),
            ],
          ),
        ),
      ),
      body: RefreshIndicator(onRefresh: () async {}, child: const SingleChildScrollView(padding: EdgeInsets.all(12), child: AdminMonitoringPanel())),
    ));
  }
}
