import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../models/work_order.dart';
import '../services/ai_title_service.dart';
import '../utils/app_colors.dart';

/// One-time admin tool: generates an AI title (see ai_title_service.dart)
/// for every existing "Others" task -- running or already completed --
/// that doesn't have one yet. Only needed because the AI-title feature
/// was added after some "Others" tasks already existed; a NEW "Others"
/// task already gets its title automatically as soon as it's started, so
/// this only ever needs to run again if a batch of old tasks is still
/// missing one (safe to re-run any time -- it only ever touches tasks
/// still missing a title).
class BackfillAiTitlesScreen extends StatefulWidget {
  const BackfillAiTitlesScreen({super.key});

  @override
  State<BackfillAiTitlesScreen> createState() => _BackfillAiTitlesScreenState();
}

class _BackfillAiTitlesScreenState extends State<BackfillAiTitlesScreen> {
  bool _isRunning = false;
  bool _hasRun = false;
  bool _regenerateAll = false;
  int _total = 0;
  int _processed = 0;
  int _titled = 0;
  int _skipped = 0;
  int _failed = 0;
  final List<String> _log = [];

  // Guards a setState call without aborting whatever async work is still
  // in flight -- unlike an early `if (!mounted) return`, which (used
  // inside _run's loop) would silently kill the REST of the backfill the
  // moment this screen stops being shown, e.g. the user navigates away
  // mid-run since each task takes a couple of seconds. The Firestore
  // writes below never check this -- they're meant to keep happening in
  // the background even after the screen is gone.
  void _safeSetState(VoidCallback fn) {
    if (mounted) setState(fn);
  }

  Future<void> _run() async {
    _safeSetState(() {
      _isRunning = true;
      _hasRun = true;
      _total = 0;
      _processed = 0;
      _titled = 0;
      _skipped = 0;
      _failed = 0;
      _log.clear();
    });

    try {
      final snap = await FirebaseFirestore.instance.collection('work_orders').where('type', isEqualTo: 'others').get();
      final orders = snap.docs
          .map((d) => WorkOrder.fromMap(d.id, d.data()))
          .where((o) => _regenerateAll || o.summaryTitle == null || o.summaryTitle!.isEmpty)
          .toList();
      _safeSetState(() => _total = orders.length);

      for (final order in orders) {
        // Live-started tasks keep their remarks in 'description'; a
        // late-logged one keeps them in 'completionRemarks' instead (see
        // late_entry_screen.dart) -- try whichever one is actually set.
        final remarks = order.description.trim().isNotEmpty ? order.description : order.completionRemarks;
        if (remarks.trim().isEmpty) {
          _safeSetState(() {
            _processed++;
            _skipped++;
            _log.add('Skipped ${order.id} — no remarks to summarize.');
          });
          continue;
        }
        try {
          final title = await summarizeOthersTaskTitle(remarks);
          if (title == null) {
            _safeSetState(() {
              _processed++;
              _failed++;
              _log.add('Failed ${order.id} — AI request did not return a title.');
            });
          } else {
            await FirebaseFirestore.instance.collection('work_orders').doc(order.id).update({'summaryTitle': title});
            final hadTitle = order.summaryTitle != null && order.summaryTitle!.isNotEmpty;
            _safeSetState(() {
              _processed++;
              _titled++;
              _log.add('${hadTitle ? 'Replaced' : 'Titled'} ${order.id} — "$title"${hadTitle ? ' (was "${order.summaryTitle}")' : ''}');
            });
          }
        } catch (e) {
          _safeSetState(() {
            _processed++;
            _failed++;
            _log.add('Failed ${order.id} — $e');
          });
        }
        // Stays well under the free tier's per-minute request cap rather
        // than firing every call back-to-back.
        await Future.delayed(const Duration(seconds: 2));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not load tasks: $e')));
      }
    } finally {
      _safeSetState(() => _isRunning = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Backfill AI Titles')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Generates an AI title for every existing "Others" task — running or already '
              'completed — that doesn\'t have one yet. New "Others" tasks already get a title '
              'automatically as soon as they\'re started, so this is only needed once to clear '
              'the backlog of tasks created before that existed.',
            ),
            const SizedBox(height: 8),
            const Text(
              'Calls the free-tier Gemini API once per task with a short pause between calls, so '
              'a large backlog can take a while — it keeps running even if you navigate elsewhere '
              'in the app, but stops if you close this tab/app entirely before it finishes. Safe '
              'to re-run — with the box below unchecked, it only touches tasks still missing a '
              'title.',
              style: TextStyle(color: AppColors.muted, fontSize: 12),
            ),
            const SizedBox(height: 8),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: _regenerateAll,
              onChanged: _isRunning ? null : (v) => setState(() => _regenerateAll = v ?? false),
              title: const Text('Also regenerate tasks that already have a title'),
              subtitle: const Text(
                'Use this after changing how titles are generated, to fix titles made with the old style too.',
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _isRunning ? null : _run,
                icon: _isRunning
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.auto_awesome),
                label: Text(_isRunning ? 'Processing $_processed of $_total…' : (_hasRun ? 'Run again' : 'Run backfill')),
              ),
            ),
            if (_hasRun) ...[
              const SizedBox(height: 12),
              Text(
                '$_titled titled · $_skipped skipped (no remarks) · $_failed failed',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ],
            const SizedBox(height: 12),
            Expanded(
              child: ListView.builder(
                reverse: true,
                itemCount: _log.length,
                itemBuilder: (context, i) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Text(_log[_log.length - 1 - i], style: const TextStyle(fontSize: 12, color: AppColors.muted)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
