import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../models/app_user.dart';
import '../models/helper.dart';
import '../models/machine.dart';
import '../models/work_order.dart';
import '../widgets_root_back_scope.dart';
import '../utils/date_format.dart';
import '../utils/duty_status.dart';
import '../utils/machine_group.dart';
import '../utils/task_type.dart';
import '../services/status_reminder_notification.dart';
import '../utils/offline_commit.dart';
import 'my_cf_assignments_screen.dart';
import 'late_entry_screen.dart';
import '../utils/app_colors.dart';

class TechnicianScreen extends StatefulWidget {
  final AppUser user;
  final VoidCallback onLogout;

  const TechnicianScreen({super.key, required this.user, required this.onLogout});

  @override
  State<TechnicianScreen> createState() => _TechnicianScreenState();
}

class _TechnicianScreenState extends State<TechnicianScreen> {
  bool _checkedMandatoryStatus = false;

  @override
  void initState() {
    super.initState();
    // Runs exactly once per app session (this State object persists
    // across the user-doc stream updates that recreate widget.user, so
    // this never re-fires just because dutyStatus changed) — matching
    // "first login of the day" rather than "every time anything reloads".
    final now = DateTime.now();
    final needsPrompt = now.hour >= 8 && widget.user.dutyStatusDate != todayKey(now);
    _checkedMandatoryStatus = true;
    if (needsPrompt) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _showMandatoryStatusDialog());
      // Also fires a real OS-level notification on web/PWA (browser
      // Notification API) as a second, more attention-grabbing nudge —
      // a no-op on the native Android app for now, since a true
      // system notification there needs a plugin plus native manifest
      // changes that aren't wired up yet.
      showStatusReminderNotification();
    }
  }

  Future<void> _showMandatoryStatusDialog() async {
    if (!mounted) return;
    final assigned = widget.user.status == 'assigned';
    final choice = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => PopScope(
        canPop: false,
        child: SimpleDialog(
          title: const Text("Set today's status"),
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Text("Please confirm your status for today before continuing."),
            ),
            SimpleDialogOption(onPressed: () => Navigator.pop(context, 'day'), child: const ListTile(leading: Icon(Icons.wb_sunny_outlined), title: Text('Day'))),
            SimpleDialogOption(onPressed: () => Navigator.pop(context, 'night'), child: const ListTile(leading: Icon(Icons.nightlight_outlined), title: Text('Night'))),
            if (!assigned) SimpleDialogOption(onPressed: () => Navigator.pop(context, 'on_leave'), child: const ListTile(leading: Icon(Icons.event_busy_outlined), title: Text('On-leave'))),
          ],
        ),
      ),
    );
    if (choice == null) {
      // Non-dismissable by design — canPop:false plus no barrier dismiss
      // means this shouldn't happen, but re-prompt just in case rather
      // than silently letting the day go unset.
      _showMandatoryStatusDialog();
      return;
    }
    await FirebaseFirestore.instance.collection('users').doc(widget.user.uid).update({
      'dutyStatus': choice,
      'status': choice == 'on_leave' ? 'on_leave' : (assigned ? 'assigned' : 'available'),
      'dutyStatusDate': todayKey(),
    });
  }

  Future<void> _setDutyStatus(BuildContext context) async {
    if (widget.user.status == 'assigned') {
      final choice = await showDialog<String>(
        context: context,
        builder: (context) => SimpleDialog(
          title: const Text('Set Status'),
          children: [
            SimpleDialogOption(onPressed: () => Navigator.pop(context, 'day'), child: const ListTile(leading: Icon(Icons.wb_sunny_outlined), title: Text('Day'))),
            SimpleDialogOption(onPressed: () => Navigator.pop(context, 'night'), child: const ListTile(leading: Icon(Icons.nightlight_outlined), title: Text('Night'))),
          ],
        ),
      );
      if (choice != null) {
        await FirebaseFirestore.instance.collection('users').doc(widget.user.uid).update({'dutyStatus': choice, 'dutyStatusDate': todayKey()});
      }
      return;
    }

    final choice = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Set Status'),
        children: [
          SimpleDialogOption(onPressed: () => Navigator.pop(context, 'day'), child: const ListTile(leading: Icon(Icons.wb_sunny_outlined), title: Text('Day'))),
          SimpleDialogOption(onPressed: () => Navigator.pop(context, 'night'), child: const ListTile(leading: Icon(Icons.nightlight_outlined), title: Text('Night'))),
          SimpleDialogOption(onPressed: () => Navigator.pop(context, 'on_leave'), child: const ListTile(leading: Icon(Icons.event_busy_outlined), title: Text('On-leave'))),
        ],
      ),
    );
    if (choice == null) return;
    await FirebaseFirestore.instance.collection('users').doc(widget.user.uid).update({
      'dutyStatus': choice,
      'status': choice == 'on_leave' ? 'on_leave' : 'available',
      'dutyStatusDate': todayKey(),
    });
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.user;
    return RootBackScope(
      child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        // A JO can now run several tasks at once, so "what's running" is
        // no longer a single currentTaskId on the user doc — it's simply
        // every work order that lists them and is still in progress.
        // array-contains + one equality filter like this doesn't need a
        // manual Firestore composite index.
        stream: FirebaseFirestore.instance
            .collection('work_orders')
            .where('assignedTechnicianIds', arrayContains: user.uid)
            .where('status', isEqualTo: 'in_progress')
            .snapshots(),
        builder: (context, snapshot) {
          final orders = (snapshot.data?.docs ?? [])
              .map((d) => WorkOrder.fromMap(d.id, d.data()))
              .toList()
            ..sort((a, b) {
              final at = a.startedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
              final bt = b.startedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
              return at.compareTo(bt);
            });

          if (orders.isEmpty) {
            return Scaffold(
              appBar: AppBar(
                title: const _DigitalClock(),
                actions: [
                  IconButton(icon: const Icon(Icons.toggle_on_outlined), tooltip: 'Set Status', onPressed: () => _setDutyStatus(context)),
                  IconButton(icon: const Icon(Icons.logout), tooltip: 'Log out', onPressed: widget.onLogout),
                ],
              ),
              body: _TechnicianHome(uid: user.uid, user: user),
            );
          }

          return _RunningTasksTabs(
            user: user,
            orders: orders,
            onSetStatus: () => _setDutyStatus(context),
            onLogout: widget.onLogout,
          );
        },
      ),
    );
  }
}

// A live-updating clock shown instead of a static "Junior Officer
// Dashboard" title — small, low-effort touch that also makes the
// dashboard double as a wall clock during a shift.
class _DigitalClock extends StatefulWidget {
  const _DigitalClock();
  @override
  State<_DigitalClock> createState() => _DigitalClockState();
}

class _DigitalClockState extends State<_DigitalClock> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final period = now.hour >= 12 ? 'PM' : 'AM';
    final hour12 = now.hour % 12 == 0 ? 12 : now.hour % 12;
    String two(int n) => n.toString().padLeft(2, '0');
    return Text(
      '$hour12:${two(now.minute)}:${two(now.second)} $period',
      style: const TextStyle(fontWeight: FontWeight.w700, fontFeatures: [FontFeature.tabularFigures()]),
    );
  }
}

// Today's completed-task count and total engaged time for this JO — a
// small positive nudge on their own dashboard, not shown to anyone else.
class _TodayStatsCard extends StatelessWidget {
  final String uid;
  const _TodayStatsCard({required this.uid});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      // Deliberately NOT filtering completedAt in the query itself:
      // array-contains + equality + a range filter on a third field is
      // exactly the combination that needs a manual Firestore composite
      // index, and none exists for this one — which silently failed and
      // is why this card showed nothing anywhere. array-contains +
      // equality alone doesn't need one, so today's cutoff is applied
      // client-side instead below.
      stream: FirebaseFirestore.instance
          .collection('work_orders')
          .where('assignedTechnicianIds', arrayContains: uid)
          .where('status', isEqualTo: 'completed')
          .snapshots(),
      builder: (context, snapshot) {
        final orders = (snapshot.data?.docs ?? [])
            .map((d) => WorkOrder.fromMap(d.id, d.data()))
            .where((o) => o.completedAt != null && !o.completedAt!.isBefore(todayStart))
            .toList();
        final count = orders.length;
        final totalSeconds = orders.fold<int>(0, (sum, o) => sum + (o.durationSeconds ?? 0));
        final hours = totalSeconds ~/ 3600;
        final minutes = (totalSeconds % 3600) ~/ 60;
        final engagedLabel = hours > 0 ? '${hours}h ${minutes}m' : '${minutes}m';
        return Card(
          color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.35),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
            child: Row(children: [
              Expanded(child: _stat(context, Icons.task_alt, '$count', count == 1 ? 'task today' : 'tasks today')),
              SizedBox(height: 42, child: VerticalDivider(width: 1, color: Theme.of(context).dividerColor)),
              Expanded(child: _stat(context, Icons.timer_outlined, engagedLabel, 'engaged today')),
            ]),
          ),
        );
      },
    );
  }

  Widget _stat(BuildContext context, IconData icon, String value, String label) {
    return Column(children: [
      Icon(icon, size: 22, color: Theme.of(context).colorScheme.primary),
      const SizedBox(height: 4),
      Text(value, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
      Text(label, style: const TextStyle(fontSize: 12, color: AppColors.muted)),
    ]);
  }
}

class _TechnicianHome extends StatelessWidget {
  final String uid;
  final AppUser user;
  const _TechnicianHome({required this.uid, required this.user});

  @override
  Widget build(BuildContext context) {
    final onLeave = user.dutyStatus == 'on_leave' || user.status == 'on_leave';
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text('Hello, ${user.name}', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Text('Status: ${_dutyLabel(user.dutyStatus)}', style: TextStyle(color: onLeave ? AppColors.danger : AppColors.success, fontWeight: FontWeight.w600)),
        const SizedBox(height: 18),
        _TodayStatsCard(uid: uid),
        const SizedBox(height: 18),
        Card(
          child: ListTile(
            leading: const CircleAvatar(child: Icon(Icons.play_arrow)),
            title: const Text('Start a task', style: TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text(onLeave ? 'Unavailable while on-leave.' : 'Select a machine and maintenance type.'),
            trailing: const Icon(Icons.chevron_right),
            enabled: !onLeave,
            onTap: onLeave ? null : () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => _StartTaskPage(uid: uid))),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: ListTile(
            leading: const CircleAvatar(child: Icon(Icons.person_add_alt_1)),
            title: const Text('CF Assignments', style: TextStyle(fontWeight: FontWeight.bold)),
            subtitle: const Text('Assign a CF, or close out ones you already assigned.'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => CfAssignmentsScreen(uid: uid))),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: ListTile(
            leading: const CircleAvatar(child: Icon(Icons.history_edu_outlined)),
            title: const Text('Add Past Task', style: TextStyle(fontWeight: FontWeight.bold)),
            subtitle: const Text('Log a task you couldn\'t enter at the time.'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => LateEntryScreen(uid: uid))),
          ),
        ),
      ],
    );
  }

  static String _dutyLabel(String value) {
    switch (value) {
      case 'night': return 'Night';
      case 'on_leave': return 'On-leave';
      default: return 'Day';
    }
  }
}

// The screen shown once a JO has one or more tasks running. Each task
// gets its own tab so they can be worked and completed independently;
// the "+" in the top right starts yet another one without disturbing
// the tasks already in progress.
class _RunningTasksTabs extends StatelessWidget {
  final AppUser user;
  final List<WorkOrder> orders;
  final VoidCallback onSetStatus;
  final VoidCallback onLogout;

  const _RunningTasksTabs({
    required this.user,
    required this.orders,
    required this.onSetStatus,
    required this.onLogout,
  });

  @override
  Widget build(BuildContext context) {
    final uid = user.uid;
    // Keying by the set of task ids (not just the count) means the tab
    // controller is only rebuilt from scratch when a task actually
    // starts or finishes — not on every minor field update (like a CF
    // being added) that re-fires the parent query — so the JO doesn't
    // lose their selected tab while just editing one of them.
    final tabKey = ValueKey(orders.map((o) => o.id).join(','));
    return DefaultTabController(
      key: tabKey,
      length: orders.length,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Running Tasks'),
          actions: [
            PopupMenuButton<String>(
              tooltip: 'More',
              onSelected: (value) {
                switch (value) {
                  case 'cf':
                    Navigator.of(context).push(MaterialPageRoute(builder: (_) => CfAssignmentsScreen(uid: uid)));
                    break;
                  case 'late_entry':
                    Navigator.of(context).push(MaterialPageRoute(builder: (_) => LateEntryScreen(uid: uid)));
                    break;
                  case 'status':
                    onSetStatus();
                    break;
                  case 'logout':
                    onLogout();
                    break;
                }
              },
              itemBuilder: (context) => const [
                PopupMenuItem(value: 'cf', child: Text('CF Assignments')),
                PopupMenuItem(value: 'late_entry', child: Text('Add Past Task')),
                PopupMenuItem(value: 'status', child: Text('Set Status')),
                PopupMenuDivider(),
                PopupMenuItem(value: 'logout', child: Text('Log out')),
              ],
            ),
            IconButton(
              icon: const Icon(Icons.add),
              tooltip: 'Start another task',
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => _StartTaskPage(uid: uid))),
            ),
          ],
          bottom: TabBar(
            isScrollable: true,
            // Bold + full-opacity for the selected tab, dimmer for the
            // rest — makes it unambiguous which task's tab is currently
            // open, on top of the underline indicator TabBar already
            // draws.
            labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.normal, fontSize: 14),
            tabs: [
              for (var i = 0; i < orders.length; i++) Tab(text: 'Task ${i + 1}'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            for (final order in orders)
              _CurrentTaskView(uid: uid, taskId: order.id, totalRunningCount: orders.length),
          ],
        ),
      ),
    );
  }
}

class _StartTaskPage extends StatefulWidget {
  final String uid;
  const _StartTaskPage({required this.uid});
  @override
  State<_StartTaskPage> createState() => _StartTaskPageState();
}

class _StartTaskPageState extends State<_StartTaskPage> {
  String? _selectedMachineId;
  Machine? _selectedMachine;
  Set<String> _selectedGroupUnitIds = <String>{};
  String _type = 'preventive';
  final Set<String> _preventiveTypes = <String>{};
  final _remarksController = TextEditingController();
  final _machineSearchController = TextEditingController();
  bool _isSaving = false;
  bool _showSuggestions = false;
  String? _errorText;

  late final Stream<QuerySnapshot<Map<String, dynamic>>> _machinesStream = FirebaseFirestore.instance.collection('machines').orderBy('equipmentName').snapshots();

  @override
  void dispose() {
    _remarksController.dispose();
    _machineSearchController.dispose();
    super.dispose();
  }

  List<Machine> _filterMachines(List<Machine> machines, String query) {
    final search = query.trim().toLowerCase();
    if (search.isEmpty) return const [];
    final matches = machines.where((m) => m.displayName.toLowerCase().contains(search) || m.equipmentName.toLowerCase().contains(search) || m.equipmentId.toLowerCase().contains(search) || m.group.toLowerCase().contains(search)).toList();
    matches.sort((a, b) {
      int score(Machine m) {
        final n = m.displayName.toLowerCase();
        final id = m.equipmentId.toLowerCase();
        return (n == search || id == search) ? 0 : (n.startsWith(search) || id.startsWith(search)) ? 1 : 2;
      }
      final c = score(a).compareTo(score(b));
      return c == 0 ? a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()) : c;
    });
    return matches;
  }

  Future<void> _selectMachine(Machine machine, List<Machine> allMachines) async {
    final resolved = resolveGroup(machine, allMachines);
    var groupUnitIds = <String>{};
    var effective = machine;
    if (resolved != null) {
      final picked = await pickGroupUnits(context, tapped: machine, resolved: resolved);
      if (picked == null) return; // cancelled — leave prior selection untouched
      groupUnitIds = picked;
      effective = resolved.main;
    }
    setState(() {
      _selectedMachine = effective;
      _selectedMachineId = effective.id;
      _selectedGroupUnitIds = groupUnitIds;
      _machineSearchController.text = effective.displayName;
      _machineSearchController.selection = TextSelection.fromPosition(TextPosition(offset: _machineSearchController.text.length));
      _showSuggestions = false;
      _errorText = null;
    });
  }

  Future<void> _startTask() async {
    setState(() => _errorText = null);
    // Machine is only mandatory for real maintenance tasks. "Others" (OT)
    // covers work with no specific machine — e.g. general housekeeping —
    // so it can be started without picking one.
    if (_type != 'others' && _selectedMachineId == null) return setState(() => _errorText = 'Please select a machine.');
    if (_type == 'preventive' && _preventiveTypes.isEmpty) return setState(() => _errorText = 'Select at least one preventive maintenance type.');
    if (_type == 'others' && _remarksController.text.trim().isEmpty) return setState(() => _errorText = 'Please describe what this task is.');

    setState(() => _isSaving = true);
    final firestore = FirebaseFirestore.instance;
    final ref = firestore.collection('work_orders').doc();
    final batch = firestore.batch();
    // Client-side timestamp, not FieldValue.serverTimestamp(): if this
    // write happens while offline, serverTimestamp() would resolve to
    // whenever it eventually SYNCS, not when the task actually started —
    // silently erasing however long the JO was genuinely working offline.
    final startedNow = Timestamp.fromDate(DateTime.now());
    batch.set(ref, {
      'type': _type,
      'preventiveTypes': _type == 'preventive' ? _preventiveTypes.toList() : <String>[],
      'machineId': _selectedMachineId,
      'groupMachineIds': _selectedGroupUnitIds.toList(),
      'description': _remarksController.text.trim(),
      'status': 'in_progress',
      'assignedTechnicianIds': [widget.uid],
      // CFs are no longer picked when starting a task — a JO adds them
      // afterwards, from that task's own tab via "Add CF".
      'helperIds': <String>[],
      'createdBy': widget.uid,
      'createdAt': startedNow,
      'startedAt': startedNow,
    });
    // "assigned" now means "has at least one running task" — a JO
    // starting a second (or third...) task simply re-affirms it.
    batch.update(firestore.collection('users').doc(widget.uid), {'status': 'assigned'});
    try {
      // Fire the write and move on immediately — see offline_commit.dart
      // for why we never wait on this, not even briefly.
      commitAllowingOffline(batch);
      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() { _errorText = 'Failed to start task: $e'; _isSaving = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Start a Task')),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        Text(_type == 'others' ? 'Machine (optional)' : 'Machine', style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(stream: _machinesStream, builder: (context, snapshot) {
          if (snapshot.hasError) return Text('Unable to load machines: ${snapshot.error}');
          final machines = snapshot.data?.docs.map((d) => Machine.fromMap(d.id, d.data())).toList() ?? [];
          final suggestions = _filterMachines(machines, _machineSearchController.text);
          return Column(children: [
            TextField(
              controller: _machineSearchController,
              onChanged: (v) => setState(() { _selectedMachine = null; _selectedMachineId = null; _selectedGroupUnitIds = {}; _showSuggestions = v.trim().isNotEmpty; }),
              onTap: () => setState(() => _showSuggestions = _machineSearchController.text.trim().isNotEmpty),
              decoration: InputDecoration(labelText: _type == 'others' ? 'Search machine (optional)' : 'Search machine', hintText: 'Machine name or equipment ID', prefixIcon: const Icon(Icons.search), suffixIcon: _selectedMachine == null ? null : IconButton(onPressed: () => setState(() { _selectedMachine = null; _selectedMachineId = null; _selectedGroupUnitIds = {}; _machineSearchController.clear(); }), icon: const Icon(Icons.clear)), border: const OutlineInputBorder()),
            ),
            if (_showSuggestions && suggestions.isNotEmpty) Card(child: ConstrainedBox(
              // Shows about 5 rows before scrolling, rather than
              // silently dropping every match past the 5th.
              constraints: const BoxConstraints(maxHeight: 320),
              child: ListView(
                shrinkWrap: true,
                children: suggestions.map((m) => ListTile(title: Text(m.displayName), subtitle: Text(m.equipmentId), onTap: () => _selectMachine(m, machines))).toList(),
              ),
            )),
            if (_selectedMachine != null) Align(alignment: Alignment.centerLeft, child: Padding(padding: const EdgeInsets.only(top: 8), child: Text(
              _selectedGroupUnitIds.isEmpty
                  ? 'Selected: ${_selectedMachine!.displayName}'
                  : 'Selected: ${_selectedMachine!.displayName} + ${_selectedGroupUnitIds.length} other unit(s)',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ))),
          ]);
        }),
        const SizedBox(height: 20),
        const Text('Maintenance Type', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final t in allTaskTypes) _typeChip(t, taskTypeCodeAndName(t)),
        ]),
        if (_type == 'preventive') ...[
          const SizedBox(height: 14),
          const Text('Preventive Maintenance Type (multiple allowed)', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: ['W', 'M', '3M', '6M', 'Y', '2Y', '6Y'].map((v) {
              return FilterChip(
                label: Text(v),
                selected: _preventiveTypes.contains(v),
                onSelected: (selected) {
                  setState(() {
                    if (selected) {
                      _preventiveTypes.add(v);
                    } else {
                      _preventiveTypes.remove(v);
                    }
                  });
                },
              );
            }).toList(),
          ),
        ],
        const SizedBox(height: 18),
        Text(
          _type == 'others' ? 'What is this task? (required)' : 'Starting remarks (optional)',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _remarksController,
          maxLines: 3,
          decoration: InputDecoration(
            border: const OutlineInputBorder(),
            hintText: _type == 'others' ? 'Describe the task, e.g. "Cleaning storage room"' : 'Optional issue/background information',
          ),
        ),
        const SizedBox(height: 18),
        if (_errorText != null) Padding(padding: const EdgeInsets.only(bottom: 12), child: Text(_errorText!, style: const TextStyle(color: AppColors.danger))),
        SizedBox(height: 50, child: FilledButton(onPressed: _isSaving ? null : _startTask, child: _isSaving ? const CircularProgressIndicator(strokeWidth: 2) : const Text('Start Task'))),
      ]),
    );
  }

  Widget _typeChip(String value, String label) => ChoiceChip(label: Text(label), selected: _type == value, onSelected: (_) => setState(() { _type = value; if (value != 'preventive') _preventiveTypes.clear(); }));
}

class _CurrentTaskView extends StatefulWidget {
  final String uid;
  final String taskId;
  // How many tasks this JO has running in total, INCLUDING this one —
  // used on completion to decide whether they go back to "available" or
  // stay "assigned" because another task is still open.
  final int totalRunningCount;
  const _CurrentTaskView({required this.uid, required this.taskId, required this.totalRunningCount});
  @override
  State<_CurrentTaskView> createState() => _CurrentTaskViewState();
}

class _CurrentTaskViewState extends State<_CurrentTaskView> {
  bool _isCompleting = false;

  String _typeCode(WorkOrder order) => taskTypeCode(order.type);

  Future<void> _chooseAndAddHelpers(WorkOrder order) async {
    final snap = await FirebaseFirestore.instance.collection('helpers').orderBy('name').get();
    final helpers = snap.docs.map((d) => Helper.fromMap(d.id, d.data())).toList();
    final available = helpers.where((h) => h.status == 'available' || order.helperIds.contains(h.uid)).toList();
    final selected = Set<String>.from(order.helperIds);
    await showModalBottomSheet<void>(context: context, isScrollControlled: true, builder: (sheetContext) => StatefulBuilder(builder: (context, setSheetState) => SafeArea(child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text('Add / Manage CFs', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 420),
          child: ListView(
            shrinkWrap: true,
            children: available.map((h) {
              return CheckboxListTile(
                value: selected.contains(h.uid),
                title: Text(h.name),
                secondary: const Icon(Icons.handyman_outlined),
                onChanged: (v) {
                  setSheetState(() {
                    if (v == true) {
                      selected.add(h.uid);
                    } else {
                      selected.remove(h.uid);
                    }
                  });
                },
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(width: double.infinity, child: FilledButton(onPressed: () async { Navigator.pop(sheetContext); await _syncHelpers(order.helperIds.toSet(), selected); }, child: Text('Save (${selected.length})'))),
      ]),
    ))));
  }

  Future<void> _confirmReleaseAllHelpers(WorkOrder order) async {
    if (order.helperIds.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Release all CFs?'),
        content: Text('This will release all ${order.helperIds.length} CF(s) from this task.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Release all')),
        ],
      ),
    );
    if (confirmed == true) {
      await _syncHelpers(order.helperIds.toSet(), <String>{});
    }
  }

  Future<void> _syncHelpers(Set<String> oldIds, Set<String> newIds) async {
    final added = newIds.difference(oldIds);
    final removed = oldIds.difference(newIds);
    final firestore = FirebaseFirestore.instance;
    try {
      // Adding a CF deliberately still requires a live connection: it
      // reads the CF's current status and writes only if still
      // "available", inside a transaction, specifically to stop two
      // people from double-booking the same CF at the same moment.
      // Firestore transactions need a round-trip to the server to do
      // that safely, so this one step can't be queued offline the way
      // the rest of this screen's writes are — it will simply show an
      // error below if there's no signal, same as before this change.
      for (final id in added) {
        await firestore.runTransaction((tx) async {
          final ref = firestore.collection('helpers').doc(id);
          final snap = await tx.get(ref);
          if (!snap.exists) throw Exception('CF not found.');
          final data = snap.data()!;
          if ((data['status'] ?? 'available') != 'available') throw Exception('${data['name'] ?? 'CF'} is no longer available.');
          tx.update(ref, {'status': 'assigned', 'currentTaskId': widget.taskId});
          tx.update(firestore.collection('work_orders').doc(widget.taskId), {'helperIds': FieldValue.arrayUnion([id])});
        });
      }
      for (final id in removed) {
        final batch = firestore.batch();
        batch.update(firestore.collection('work_orders').doc(widget.taskId), {'helperIds': FieldValue.arrayRemove([id])});
        batch.update(firestore.collection('helpers').doc(id), {'status': 'available', 'currentTaskId': null});
        // Releasing a CF is safe to fire-and-forget — unlike adding one
        // (above), it can't create a double-booking.
        commitAllowingOffline(batch);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not update CFs: $e')));
    }
  }

  Future<void> _addAnotherJo(WorkOrder order) async {
    final snap = await FirebaseFirestore.instance.collection('users').where('role', isEqualTo: 'technician').orderBy('name').get();
    final all = snap.docs.map((d) => AppUser.fromMap(d.id, d.data())).toList();
    // Anyone not already on this task — a JO can be on several tasks at
    // once already, so there's no "must be available" restriction the
    // way there is for CFs (who can only ever be on one task).
    final candidates = all.where((u) => u.uid != widget.uid && !order.assignedTechnicianIds.contains(u.uid)).toList();

    if (candidates.isEmpty) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No other Junior Officer to add.')));
      return;
    }

    final picked = await showModalBottomSheet<AppUser>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Padding(padding: EdgeInsets.all(16), child: Text('Bring another Junior Officer onto this task', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold))),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 420),
            child: ListView(
              shrinkWrap: true,
              children: candidates.map((u) => ListTile(
                leading: const Icon(Icons.engineering_outlined),
                title: Text(u.name),
                onTap: () => Navigator.pop(sheetContext, u),
              )).toList(),
            ),
          ),
        ]),
      ),
    );
    if (picked == null) return;

    final firestore = FirebaseFirestore.instance;
    final batch = firestore.batch();
    batch.update(firestore.collection('work_orders').doc(widget.taskId), {
      'assignedTechnicianIds': FieldValue.arrayUnion([picked.uid]),
    });
    batch.update(firestore.collection('users').doc(picked.uid), {'status': 'assigned'});
    commitAllowingOffline(batch);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${picked.name} added to this task.')));
    }
  }

  Future<void> _confirmCancelTask(WorkOrder order) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Cancel this task?'),
        content: const Text('This removes the task entirely, as if it was never started. Use this if it was started by mistake. This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Keep Task')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Cancel Task'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final firestore = FirebaseFirestore.instance;
    final batch = firestore.batch();
    batch.update(firestore.collection('work_orders').doc(widget.taskId), {'status': 'cancelled'});
    final stillBusy = widget.totalRunningCount > 1;
    for (final id in order.assignedTechnicianIds) {
      batch.update(firestore.collection('users').doc(id), {'status': id == widget.uid && !stillBusy ? 'available' : 'assigned'});
    }
    for (final id in order.helperIds) {
      batch.update(firestore.collection('helpers').doc(id), {'status': 'available', 'currentTaskId': null});
    }
    commitAllowingOffline(batch);
  }

  Future<void> _confirmAndComplete(WorkOrder order) async {
    final otherJOs = order.assignedTechnicianIds.where((id) => id != widget.uid).toList();
    if (otherJOs.isNotEmpty) {
      // Multi-JO task: "Complete" for just me means stepping away — the
      // task keeps running for whoever else is still on it, and only
      // actually completes once the last JO leaves it.
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Leave this task?'),
          content: const Text('It will keep running for the other Junior Officer(s) on it — you\'ll just be taken off it.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Stay')),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Leave Task')),
          ],
        ),
      );
      if (confirmed != true) return;
      await _leaveMultiJoTask();
      return;
    }

    final picked = await pickCompletionTime(context, startedAt: order.startedAt);
    if (picked == null || !mounted) return;

    final required = order.type != 'preventive';
    // The TextEditingController is owned by the dialog itself.
    // This is important because Flutter may still dispatch a focus
    // notification for the TextField immediately after the dialog closes.
    // Disposing a controller here, immediately after showDialog returns,
    // can cause: "A TextEditingController was used after being disposed."
    final remarks = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _CompletionConfirmationDialog(
        initialRemarks: order.completionRemarks,
        requiredRemarks: required,
      ),
    );

    if (!mounted || remarks == null) return;
    await _completeTask(order, remarks, completedAt: picked.time, lateEntry: picked.isBacktime);
  }

  Future<void> _leaveMultiJoTask() async {
    final firestore = FirebaseFirestore.instance;
    final batch = firestore.batch();
    batch.update(firestore.collection('work_orders').doc(widget.taskId), {
      'assignedTechnicianIds': FieldValue.arrayRemove([widget.uid]),
    });
    final stillBusy = widget.totalRunningCount > 1;
    batch.update(firestore.collection('users').doc(widget.uid), {'status': stillBusy ? 'assigned' : 'available'});
    commitAllowingOffline(batch);
  }

  Future<void> _completeTask(WorkOrder order, String remarks, {required DateTime completedAt, required bool lateEntry}) async {
    setState(() => _isCompleting = true);
    final firestore = FirebaseFirestore.instance;
    final duration = order.startedAt == null ? null : completedAt.difference(order.startedAt!).inSeconds;
    final batch = firestore.batch();
    final update = <String, dynamic>{
      'status': 'completed',
      'completedAt': Timestamp.fromDate(completedAt),
      'durationSeconds': duration,
      'completionRemarks': remarks,
    };
    if (lateEntry) update['lateEntry'] = true;
    batch.update(firestore.collection('work_orders').doc(widget.taskId), update);
    // Only drop back to "available" if this was the JO's last running
    // task — otherwise they're still busy with the others.
    final stillBusy = widget.totalRunningCount > 1;
    batch.update(firestore.collection('users').doc(widget.uid), {'status': stillBusy ? 'assigned' : 'available'});
    for (final id in order.helperIds) {
      batch.update(firestore.collection('helpers').doc(id), {'status': 'available', 'currentTaskId': null});
    }
    try {
      // Same fire-and-forget write as Start Task — the completion (with
      // the duration already computed above from the original
      // startedAt) is saved locally right away regardless of signal, and
      // this screen moves on immediately rather than waiting on it.
      commitAllowingOffline(batch);
    } catch (e) {
      if (mounted) {
        setState(() => _isCompleting = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to complete task: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('work_orders').doc(widget.taskId).snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        if (!snapshot.data!.exists) return const Center(child: Text('Task not found.'));
        final order = WorkOrder.fromMap(snapshot.data!.id, snapshot.data!.data()!);
        return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          // An "Others" task may have no machine at all — Firestore's
          // .doc() rejects an empty ID outright, so skip the lookup
          // entirely rather than let it throw.
          future: order.machineId.isEmpty
              ? null
              : FirebaseFirestore.instance.collection('machines').doc(order.machineId).get(),
          builder: (context, machineSnapshot) {
            final machine = machineSnapshot.data?.exists == true ? Machine.fromMap(machineSnapshot.data!.id, machineSnapshot.data!.data()!) : null;
            return Padding(padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: ListView(children: [
                const Text('Task Running', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                const SizedBox(height: 18),
                Row(children: [
                  CircleAvatar(radius: 16, child: Text(_typeCode(order), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold))),
                  const SizedBox(width: 10),
                  Expanded(child: Text('Machine: ${machine?.displayName ?? (order.machineId.isEmpty ? 'None' : order.machineId)}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600))),
                ]),
                if (machine?.equipmentId.isNotEmpty == true) Padding(padding: const EdgeInsets.only(top: 4), child: Text('Equipment ID: ${machine!.equipmentId}')),
                if (order.groupMachineIds.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
                      future: FirebaseFirestore.instance.collection('machines').where(FieldPath.documentId, whereIn: order.groupMachineIds).get(),
                      builder: (context, snap) {
                        final Map<String, Machine> byId = {for (final d in (snap.data?.docs ?? [])) d.id: Machine.fromMap(d.id, d.data())};
                        final labels = order.groupMachineIds.map((id) => byId[id]?.equipmentId ?? id).join(', ');
                        return Text('Other units: $labels');
                      },
                    ),
                  ),
                if (order.type == 'preventive' && order.preventiveTypes.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text('Preventive type: ${order.preventiveTypes.join(', ')}')),
                if (order.startedAt != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text('Started: ${formatDateTime12h(order.startedAt)}')),
                if (order.description.isNotEmpty) ...[const SizedBox(height: 8), Text('Starting remarks: ${order.description}')],
                const SizedBox(height: 18),
                Row(children: [
                  const Expanded(child: Text('Junior Officer(s)', style: TextStyle(fontWeight: FontWeight.w600))),
                  OutlinedButton.icon(onPressed: () => _addAnotherJo(order), icon: const Icon(Icons.person_add_alt_1), label: const Text('Add JO')),
                ]),
                const SizedBox(height: 4),
                StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: order.assignedTechnicianIds.isEmpty ? null : FirebaseFirestore.instance.collection('users').where(FieldPath.documentId, whereIn: order.assignedTechnicianIds).snapshots(),
                  builder: (context, joSnapshot) {
                    final docs = joSnapshot.data?.docs ?? [];
                    if (docs.isEmpty) return const Text('—');
                    return Column(
                      children: docs.map((d) {
                        final isMe = d.id == widget.uid;
                        return ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.engineering_outlined),
                          title: Text('${(d.data()['name'] ?? '').toString()}${isMe ? ' (You)' : ''}'),
                        );
                      }).toList(),
                    );
                  },
                ),
                const SizedBox(height: 18),
                Row(children: [
                  const Expanded(child: Text('CFs', style: TextStyle(fontWeight: FontWeight.w600))),
                  if (order.helperIds.isNotEmpty)
                    TextButton.icon(
                      onPressed: () => _confirmReleaseAllHelpers(order),
                      icon: const Icon(Icons.person_remove_alt_1, size: 18),
                      label: const Text('Release all'),
                      style: TextButton.styleFrom(foregroundColor: AppColors.danger),
                    ),
                  OutlinedButton.icon(onPressed: () => _chooseAndAddHelpers(order), icon: const Icon(Icons.person_add_alt_1), label: const Text('Add CF')),
                ]),
                const SizedBox(height: 4),
                StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: order.helperIds.isEmpty ? null : FirebaseFirestore.instance.collection('helpers').where(FieldPath.documentId, whereIn: order.helperIds).snapshots(),
                  builder: (context, helperSnapshot) {
                    final docs = helperSnapshot.data?.docs ?? [];
                    if (docs.isEmpty) return const Text('No CF selected.');
                    return Column(
                      children: docs.map((d) {
                        return ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.handyman_outlined),
                          title: Text((d.data()['name'] ?? '').toString()),
                          trailing: TextButton(
                            onPressed: () => _syncHelpers(
                              order.helperIds.toSet(),
                              order.helperIds.toSet()..remove(d.id),
                            ),
                            child: const Text('Release'),
                          ),
                        );
                      }).toList(),
                    );
                  },
                ),
                const SizedBox(height: 18),
                if (order.type != 'preventive') Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: AppColors.warning.withValues(alpha: .08), borderRadius: BorderRadius.circular(10)), child: const Text('Completion remarks are required for Breakdown, Calibration and Adjustment tasks.')),
              ])),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(foregroundColor: AppColors.danger, side: const BorderSide(color: AppColors.danger)),
                    onPressed: () => _confirmCancelTask(order),
                    icon: const Icon(Icons.close),
                    label: const Text('Cancel Task'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: AppColors.success, foregroundColor: Colors.white),
                    onPressed: _isCompleting ? null : () => _confirmAndComplete(order),
                    icon: const Icon(Icons.check_circle_outline),
                    label: _isCompleting ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Complete Task'),
                  ),
                ),
              ]),
            ]));
          },
        );
      },
    );
  }
}


class _CompletionConfirmationDialog extends StatefulWidget {
  final String initialRemarks;
  final bool requiredRemarks;

  const _CompletionConfirmationDialog({
    required this.initialRemarks,
    required this.requiredRemarks,
  });

  @override
  State<_CompletionConfirmationDialog> createState() =>
      _CompletionConfirmationDialogState();
}

class _CompletionConfirmationDialogState
    extends State<_CompletionConfirmationDialog> {
  late final TextEditingController _remarksController;

  @override
  void initState() {
    super.initState();
    _remarksController =
        TextEditingController(text: widget.initialRemarks);
  }

  @override
  void dispose() {
    _remarksController.dispose();
    super.dispose();
  }

  void _submit() {
    final remarks = _remarksController.text.trim();

    if (widget.requiredRemarks && remarks.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Remarks are required for BM, CL and AD.'),
        ),
      );
      return;
    }

    Navigator.of(context).pop(remarks);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Confirm Task Completion'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Please double-check the task details before final submission.',
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _remarksController,
              maxLines: 4,
              textInputAction: TextInputAction.newline,
              decoration: InputDecoration(
                labelText: widget.requiredRemarks
                    ? 'Corrective action / adjustment / calibration remarks (required)'
                    : 'Completion remarks (optional)',
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('Confirm & Submit'),
        ),
      ],
    );
  }
}
