import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../services/communication_service.dart';
import 'add_personnel_screen.dart';
import 'backfill_ai_titles_screen.dart';
import 'machines_screen.dart';
import 'manage_cfs_screen.dart';
import '../utils/app_colors.dart';
import '../services/theme_service.dart';
import '../widgets_task_type_chart.dart';
import '../widgets_notify_setting.dart';

/// Thin Scaffold wrapper around SettingsBody, so it can still be pushed
/// as its own screen anywhere that needs it, while the mobile bottom-nav
/// shell (native Android / compact web) embeds SettingsBody directly as
/// its "Settings" tab without stacking two AppBars.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: const SettingsBody(),
    );
  }
}

class SettingsBody extends StatefulWidget {
  const SettingsBody({super.key});
  @override
  State<SettingsBody> createState() => _SettingsBodyState();
}

class _SettingsBodyState extends State<SettingsBody> {
  String _whatsapp = 'regular';

  @override
  void initState() {
    super.initState();
    _loadWhatsApp();
  }

  Future<void> _loadWhatsApp() async {
    final value = await CommunicationService.getDefaultWhatsAppApp();
    if (mounted) setState(() => _whatsapp = value);
  }

  Future<void> _setWhatsApp(String value) async {
    await CommunicationService.setDefaultWhatsAppApp(value);
    if (mounted) setState(() => _whatsapp = value);
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('Administration', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Card(child: ListTile(
            leading: const CircleAvatar(child: Icon(Icons.person_add_alt_1_outlined)),
            title: const Text('Add Personnel'),
            subtitle: const Text('Add a Maintenance JO, Maintenance CF, or Water Plant Personnel.'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AddPersonnelScreen())),
          )),
          const SizedBox(height: 10),
          Card(child: ListTile(
            leading: const CircleAvatar(child: Icon(Icons.precision_manufacturing_outlined)),
            title: const Text('Machines'),
            subtitle: const Text('Add, edit or delete machines and equipment information.'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MachinesScreen())),
          )),
          const SizedBox(height: 10),
          Card(child: ListTile(
            leading: const CircleAvatar(child: Icon(Icons.handyman_outlined)),
            title: const Text('Manage CFs'),
            subtitle: const Text("See every CF's live status, and force one back to available if it's stuck."),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ManageCfsScreen())),
          )),
          const SizedBox(height: 10),
          Card(child: ListTile(
            leading: const CircleAvatar(child: Icon(Icons.auto_awesome_outlined)),
            title: const Text('Backfill AI Titles'),
            subtitle: const Text('One-time: generate AI titles for existing "Others" tasks that don\'t have one yet.'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const BackfillAiTitlesScreen())),
          )),
          const SizedBox(height: 24),
          const Text('Appearance', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          ListenableBuilder(
            listenable: themeService,
            builder: (context, _) => Card(child: ListTile(
              leading: const CircleAvatar(child: Icon(Icons.brightness_6_outlined)),
              title: const Text('Theme'),
              subtitle: Text(switch (themeService.mode) {
                AppThemeMode.light => 'Light',
                AppThemeMode.dark => 'Dark',
                AppThemeMode.colorful => 'Colorful',
                AppThemeMode.system => 'Match device setting',
              }),
              trailing: DropdownButton<AppThemeMode>(
                value: themeService.mode,
                underline: const SizedBox.shrink(),
                items: const [
                  DropdownMenuItem(value: AppThemeMode.system, child: Text('System')),
                  DropdownMenuItem(value: AppThemeMode.light, child: Text('Light')),
                  DropdownMenuItem(value: AppThemeMode.dark, child: Text('Dark')),
                  DropdownMenuItem(value: AppThemeMode.colorful, child: Text('Colorful')),
                ],
                onChanged: (value) { if (value != null) themeService.setMode(value); },
              ),
            )),
          ),
          const SizedBox(height: 24),
          const Text('Dashboard', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          const ChartModeSetting(),
          const SizedBox(height: 24),
          const Text('Notify', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          const NotifySetting(),
          const SizedBox(height: 24),
          const Text('Android Communication', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Card(child: ListTile(
            leading: const CircleAvatar(child: Icon(Icons.chat_outlined)),
            title: const Text('Default WhatsApp app'),
            subtitle: Text(_whatsapp == 'business' ? 'WhatsApp Business' : 'WhatsApp'),
            trailing: DropdownButton<String>(
              value: _whatsapp,
              underline: const SizedBox.shrink(),
              items: const [DropdownMenuItem(value: 'regular', child: Text('WhatsApp')), DropdownMenuItem(value: 'business', child: Text('WhatsApp Business'))],
              onChanged: (value) { if (value != null) _setWhatsApp(value); },
            ),
          )),
          if (kIsWeb) const Padding(padding: EdgeInsets.only(top: 8), child: Text('This preference is primarily used by the Android app.', style: TextStyle(color: AppColors.muted))),
        ],
    );
  }
}
