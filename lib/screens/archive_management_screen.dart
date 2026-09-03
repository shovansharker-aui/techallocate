import 'package:flutter/material.dart';
import 'backup_export_screen.dart';
import 'clear_data_screen.dart';

/// Landing page for archive-related admin actions. Currently two
/// options — Backup/Export and Clear Data — kept as a menu rather than
/// cramming both into one screen so more can be added later (e.g.
/// restore-from-backup) without redesigning this page.
///
/// Thin Scaffold wrapper around ArchiveManagementBody, so it can be
/// pushed as its own screen (Android admin nav) while the web admin
/// shell embeds ArchiveManagementBody directly without stacking two
/// AppBars.
class ArchiveManagementScreen extends StatelessWidget {
  const ArchiveManagementScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Archive')),
      body: const ArchiveManagementBody(),
    );
  }
}

class ArchiveManagementBody extends StatelessWidget {
  const ArchiveManagementBody({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Card(
          child: ListTile(
            leading: const CircleAvatar(child: Icon(Icons.file_download_outlined)),
            title: const Text('Backup / Export', style: TextStyle(fontWeight: FontWeight.bold)),
            subtitle: const Text('Export completed tasks for a week, month, or custom range as CSV.'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const BackupExportScreen())),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: ListTile(
            leading: const CircleAvatar(child: Icon(Icons.delete_outline)),
            title: const Text('Clear Data', style: TextStyle(fontWeight: FontWeight.bold)),
            subtitle: const Text('Permanently delete a month\'s completed task records.'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ClearDataScreen())),
          ),
        ),
      ],
    );
  }
}
