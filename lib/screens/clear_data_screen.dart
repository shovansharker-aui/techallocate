import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../utils/app_colors.dart';

/// Permanently deletes completed task records within a chosen date
/// range — moved here from the "View History" screen so a destructive
/// action doesn't live next to the everyday history browsing, and
/// instead sits alongside Backup/Export under Archive where it belongs.
class ClearDataScreen extends StatelessWidget {
  const ClearDataScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Clear Data')),
      body: const ClearDataBody(),
    );
  }
}

class ClearDataBody extends StatefulWidget {
  const ClearDataBody({super.key});

  @override
  State<ClearDataBody> createState() => _ClearDataBodyState();
}

class _ClearDataBodyState extends State<ClearDataBody> {
  DateTime _from = DateTime.now().subtract(const Duration(days: 30));
  DateTime _to = DateTime.now();
  bool _isClearing = false;

  String _dateLabel(DateTime d) => '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  Future<void> _pickDate({required bool isFrom}) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: isFrom ? _from : _to,
      firstDate: DateTime(now.year - 5),
      lastDate: now,
    );
    if (picked == null) return;
    setState(() {
      if (isFrom) {
        _from = picked;
        if (_to.isBefore(_from)) _to = _from;
      } else {
        _to = picked;
        if (_from.isAfter(_to)) _from = _to;
      }
    });
  }

  Future<void> _confirmClear() async {
    final rangeStart = DateTime(_from.year, _from.month, _from.day);
    final rangeEnd = DateTime(_to.year, _to.month, _to.day).add(const Duration(days: 1)); // inclusive of the "to" day
    final query = FirebaseFirestore.instance
        .collection('work_orders')
        .where('status', isEqualTo: 'completed')
        .where('completedAt', isGreaterThanOrEqualTo: Timestamp.fromDate(rangeStart))
        .where('completedAt', isLessThan: Timestamp.fromDate(rangeEnd));

    final countSnap = await query.count().get();
    final count = countSnap.count ?? 0;

    if (!mounted) return;
    if (count == 0) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('No completed tasks between ${_dateLabel(_from)} and ${_dateLabel(_to)}.')));
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Clear this range?'),
        content: Text(
          'This will permanently delete $count completed task record(s) between '
          '${_dateLabel(_from)} and ${_dateLabel(_to)} (inclusive). This cannot be undone — '
          'consider exporting a backup first if you haven\'t already.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _isClearing = true);
    try {
      final firestore = FirebaseFirestore.instance;
      // Delete in batches of 500 (Firestore's batch write limit).
      while (true) {
        final snap = await query.limit(500).get();
        if (snap.docs.isEmpty) break;
        final batch = firestore.batch();
        for (final doc in snap.docs) {
          batch.delete(doc.reference);
        }
        await batch.commit();
        if (snap.docs.length < 500) break;
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Cleared $count task(s) between ${_dateLabel(_from)} and ${_dateLabel(_to)}.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to clear data: $e')));
      }
    } finally {
      if (mounted) setState(() => _isClearing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Card(
          color: AppColors.danger.withValues(alpha: 0.06),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              const Icon(Icons.warning_amber_rounded, color: AppColors.danger),
              const SizedBox(width: 10),
              const Expanded(child: Text('This permanently deletes completed task records. This cannot be undone. Export a backup first if you need to keep a copy.')),
            ]),
          ),
        ),
        const SizedBox(height: 24),
        const Text('Date range to clear', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => _pickDate(isFrom: true),
              icon: const Icon(Icons.calendar_today_outlined, size: 18),
              label: Text('From ${_dateLabel(_from)}'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => _pickDate(isFrom: false),
              icon: const Icon(Icons.calendar_today_outlined, size: 18),
              label: Text('To ${_dateLabel(_to)}'),
            ),
          ),
        ]),
        const SizedBox(height: 20),
        SizedBox(
          height: 50,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: _isClearing ? null : _confirmClear,
            icon: _isClearing
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.delete_outline),
            label: const Text('Clear Data in Range'),
          ),
        ),
      ],
    );
  }
}
