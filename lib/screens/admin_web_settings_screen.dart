import 'package:flutter/material.dart';
import 'add_employee_screen.dart';
import 'machines_screen.dart';
import 'add_helper_screen.dart';
import '../services/theme_service.dart';

class AdminWebSettingsScreen extends StatelessWidget {
  const AdminWebSettingsScreen({super.key});

  void _open(BuildContext context, Widget page) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => page),
    );
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final contentWidth = width > 1000 ? 900.0 : double.infinity;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: contentWidth),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              const Text(
                'Administration',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 10),
              Card(
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  leading: const CircleAvatar(
                    child: Icon(Icons.person_add_alt_1_outlined),
                  ),
                  title: const Text(
                    'Add New Employee',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: const Text(
                    'Create a Junior Officer account with name, employee ID, phone and PIN.',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _open(context, const AddEmployeeScreen()),
                ),
              ),
              const SizedBox(height: 12),
              Card(
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  leading: const CircleAvatar(
                    child: Icon(Icons.handyman_outlined),
                  ),
                  title: const Text(
                    'CFs',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: const Text(
                    'Add CFs who can accompany Junior Officers without using the app.',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _open(context, const AddHelperScreen()),
                ),
              ),
              const SizedBox(height: 12),
              Card(
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  leading: const CircleAvatar(
                    child: Icon(Icons.precision_manufacturing_outlined),
                  ),
                  title: const Text(
                    'Machines',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: const Text(
                    'Add, edit, delete and search machine/equipment records.',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _open(context, const MachinesScreen()),
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Appearance',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 10),
              ListenableBuilder(
                listenable: themeService,
                builder: (context, _) => Card(
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    leading: const CircleAvatar(child: Icon(Icons.brightness_6_outlined)),
                    title: const Text('Theme', style: TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(switch (themeService.mode) {
                      ThemeMode.light => 'Light',
                      ThemeMode.dark => 'Dark',
                      ThemeMode.system => 'Match device setting',
                    }),
                    trailing: DropdownButton<ThemeMode>(
                      value: themeService.mode,
                      underline: const SizedBox.shrink(),
                      items: const [
                        DropdownMenuItem(value: ThemeMode.system, child: Text('System')),
                        DropdownMenuItem(value: ThemeMode.light, child: Text('Light')),
                        DropdownMenuItem(value: ThemeMode.dark, child: Text('Dark')),
                      ],
                      onChanged: (value) { if (value != null) themeService.setMode(value); },
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
