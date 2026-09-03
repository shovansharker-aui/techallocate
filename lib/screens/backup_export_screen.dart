import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import '../models/app_user.dart';
import '../models/helper.dart';
import '../models/machine.dart';
import '../models/work_order.dart';
import '../utils/app_colors.dart';
import '../utils/csv_export.dart';

enum _RangeMode { thisWeek, thisMonth, custom }

/// One-tap CSV backup of completed tasks for a chosen period — this
/// week, this month, or a custom range — for admin to keep an offline
/// copy or open in Excel/Sheets.
///
/// Thin Scaffold wrapper around BackupExportBody, so it can be pushed as
/// its own screen (Android admin nav) while the web admin shell embeds
/// BackupExportBody directly without stacking two AppBars.
class BackupExportScreen extends StatelessWidget {
  const BackupExportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Backup / Export')),
      body: const BackupExportBody(),
    );
  }
}

/// The actual range picker + Export button, with no Scaffold or AppBar
/// of its own — embed this directly wherever a persistent shell (like
/// the web admin sidebar layout) already provides those.
class BackupExportBody extends StatefulWidget {
  const BackupExportBody({super.key});

  @override
  State<BackupExportBody> createState() => _BackupExportBodyState();
}

class _BackupExportBodyState extends State<BackupExportBody> {
  _RangeMode _mode = _RangeMode.thisWeek;
  DateTime _customStart = DateTime.now().subtract(const Duration(days: 7));
  DateTime _customEnd = DateTime.now();
  bool _isExporting = false;
  String? _statusText;

  ({DateTime start, DateTime end}) _resolveRange() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    switch (_mode) {
      case _RangeMode.thisWeek:
        // Monday through today (inclusive) — Firestore's upper bound
        // below is exclusive, so "end" is the start of tomorrow.
        final start = today.subtract(Duration(days: today.weekday - 1));
        return (start: start, end: today.add(const Duration(days: 1)));
      case _RangeMode.thisMonth:
        final start = DateTime(today.year, today.month, 1);
        return (start: start, end: today.add(const Duration(days: 1)));
      case _RangeMode.custom:
        final start = DateTime(_customStart.year, _customStart.month, _customStart.day);
        final end = DateTime(_customEnd.year, _customEnd.month, _customEnd.day).add(const Duration(days: 1));
        return (start: start, end: end);
    }
  }

  Future<void> _pickCustomDate({required bool isStart}) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: isStart ? _customStart : _customEnd,
      firstDate: DateTime(now.year - 3),
      lastDate: now,
    );
    if (picked == null) return;
    setState(() {
      if (isStart) {
        _customStart = picked;
        if (_customEnd.isBefore(_customStart)) _customEnd = _customStart;
      } else {
        _customEnd = picked;
        if (_customStart.isAfter(_customEnd)) _customStart = _customEnd;
      }
    });
  }

  String _formatDate(DateTime d) => '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  Future<void> _export() async {
    setState(() {
      _isExporting = true;
      _statusText = null;
    });

    try {
      final range = _resolveRange();
      final firestore = FirebaseFirestore.instance;

      final ordersSnap = await firestore
          .collection('work_orders')
          .where('status', isEqualTo: 'completed')
          .where('completedAt', isGreaterThanOrEqualTo: Timestamp.fromDate(range.start))
          .where('completedAt', isLessThan: Timestamp.fromDate(range.end))
          .get();

      final orders = ordersSnap.docs.map((d) => WorkOrder.fromMap(d.id, d.data())).toList()
        ..sort((a, b) => (a.completedAt ?? DateTime(1970)).compareTo(b.completedAt ?? DateTime(1970)));

      if (orders.isEmpty) {
        setState(() {
          _isExporting = false;
          _statusText = 'No completed tasks in that range — nothing to export.';
        });
        return;
      }

      final results = await Future.wait([
        firestore.collection('users').get(),
        firestore.collection('helpers').get(),
        firestore.collection('machines').get(),
      ]);

      final Map<String, AppUser> technicians = {for (final d in results[0].docs) d.id: AppUser.fromMap(d.id, d.data())};
      final Map<String, Helper> helpers = {for (final d in results[1].docs) d.id: Helper.fromMap(d.id, d.data())};
      final Map<String, Machine> machines = {for (final d in results[2].docs) d.id: Machine.fromMap(d.id, d.data())};

      final csv = buildWorkOrdersCsv(orders: orders, machines: machines, technicians: technicians, helpers: helpers);
      final fileName = backupFileName(range.start, range.end.subtract(const Duration(days: 1)));

      final location = await getSaveLocation(
        suggestedName: fileName,
        acceptedTypeGroups: const [
          XTypeGroup(label: 'CSV', extensions: ['csv'], mimeTypes: ['text/csv']),
        ],
      );
      if (location == null) {
        // User cancelled the save dialog — not an error.
        setState(() => _isExporting = false);
        return;
      }

      // Excel doesn't assume UTF-8 for a plain CSV — without a BOM it
      // guesses the system codepage and mangles anything outside basic
      // ASCII, including Bengali remarks that display fine in the app.
      // Prepending the UTF-8 BOM makes Excel (and Sheets) detect the
      // encoding correctly.
      final bytes = Uint8List.fromList(utf8.encode('\uFEFF$csv'));
      final file = XFile.fromData(bytes, mimeType: 'text/csv', name: fileName);
      await file.saveTo(location.path);

      if (!mounted) return;
      setState(() {
        _isExporting = false;
        _statusText = 'Exported ${orders.length} task(s) to $fileName.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isExporting = false;
        _statusText = 'Export failed: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text('Range', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          SegmentedButton<_RangeMode>(
            segments: const [
              ButtonSegment(value: _RangeMode.thisWeek, label: Text('This Week')),
              ButtonSegment(value: _RangeMode.thisMonth, label: Text('This Month')),
              ButtonSegment(value: _RangeMode.custom, label: Text('Custom')),
            ],
            selected: {_mode},
            onSelectionChanged: (s) => setState(() => _mode = s.first),
          ),
          if (_mode == _RangeMode.custom) ...[
            const SizedBox(height: 16),
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _pickCustomDate(isStart: true),
                  icon: const Icon(Icons.calendar_today_outlined),
                  label: Text('From ${_formatDate(_customStart)}'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _pickCustomDate(isStart: false),
                  icon: const Icon(Icons.calendar_today_outlined),
                  label: Text('To ${_formatDate(_customEnd)}'),
                ),
              ),
            ]),
          ],
          const SizedBox(height: 24),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(children: const [
                Icon(Icons.info_outline),
                SizedBox(width: 10),
                Expanded(child: Text('Exports every completed task in the chosen range as a CSV file, including machine, technician, CF, timing and remarks — ready to open in Excel or Google Sheets.')),
              ]),
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 50,
            child: FilledButton.icon(
              onPressed: _isExporting ? null : _export,
              icon: const Icon(Icons.file_download_outlined),
              label: _isExporting ? const CircularProgressIndicator(strokeWidth: 2) : const Text('Export CSV'),
            ),
          ),
          if (_statusText != null) ...[
            const SizedBox(height: 14),
            Text(_statusText!, style: const TextStyle(color: AppColors.muted)),
          ],
        ],
    );
  }
}
