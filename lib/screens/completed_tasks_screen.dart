import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../models/helper.dart';
import '../models/machine.dart';
import '../models/work_order.dart';
import '../models/app_user.dart';
import '../utils/date_format.dart';
import '../utils/task_type.dart';
import '../utils/app_colors.dart';
import '../widgets_people_line.dart';

/// Thin Scaffold wrapper around CompletedTasksBody, so it can be pushed
/// as its own screen (desktop web's "View History" button) while the
/// mobile bottom-nav shell (native Android / compact web) embeds
/// CompletedTasksBody directly as its "History" tab without stacking
/// two AppBars.
class CompletedTasksScreen extends StatelessWidget {
  const CompletedTasksScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Completed Tasks')),
      body: const CompletedTasksBody(),
    );
  }
}

class CompletedTasksBody extends StatefulWidget {
  const CompletedTasksBody({super.key});

  @override
  State<CompletedTasksBody> createState() => _CompletedTasksBodyState();
}

class _CompletedTasksBodyState extends State<CompletedTasksBody> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);

  String _typeDetail(WorkOrder order) {
    if (order.type == 'preventive' && order.preventiveTypes.isNotEmpty) {
      return order.preventiveTypes.join(', ');
    }
    return '';
  }

  Future<List<AppUser>> _users() async {
    final snap = await FirebaseFirestore.instance.collection('users').get();
    return snap.docs.map((d) => AppUser.fromMap(d.id, d.data())).toList();
  }

  Future<List<Helper>> _helpers() async {
    final snap = await FirebaseFirestore.instance.collection('helpers').get();
    return snap.docs.map((d) => Helper.fromMap(d.id, d.data())).toList();
  }

  Future<Map<String, Machine>> _machines() async {
    final snap = await FirebaseFirestore.instance.collection('machines').get();
    return {for (final d in snap.docs) d.id: Machine.fromMap(d.id, d.data())};
  }

  Widget _monthlyTaskList({required DateTime start, required DateTime end}) {
    return _PaginatedMonthlyTasks(
      start: start,
      end: end,
      typeCode: (o) => taskTypeCode(o.type),
      typeDetail: _typeDetail,
      users: _users,
      helpers: _helpers,
      machines: _machines,
    );
  }

  Widget _taskList({required DateTime start, required DateTime end}) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('work_orders')
          .where('status', isEqualTo: 'completed')
          .where('completedAt', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
          .where('completedAt', isLessThan: Timestamp.fromDate(end))
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) return Text('Unable to load completed tasks: ${snapshot.error}');
        final orders = (snapshot.data?.docs ?? [])
            .map((d) => WorkOrder.fromMap(d.id, d.data()))
            .toList()
          ..sort((a, b) => (b.completedAt ?? DateTime(1970)).compareTo(a.completedAt ?? DateTime(1970)));
        if (orders.isEmpty) return const Card(child: Padding(padding: EdgeInsets.all(18), child: Text('No completed tasks in this period.')));

        return FutureBuilder(
          future: Future.wait([_users(), _helpers(), _machines()]),
          builder: (context, AsyncSnapshot<List<dynamic>> peopleSnapshot) {
            if (!peopleSnapshot.hasData) return const LinearProgressIndicator();
            final users = <String, AppUser>{for (final u in peopleSnapshot.data![0] as List<AppUser>) u.uid: u};
            final helpers = <String, Helper>{for (final h in peopleSnapshot.data![1] as List<Helper>) h.uid: h};
            final machines = peopleSnapshot.data![2] as Map<String, Machine>;

            return Column(
              children: orders.map((order) {
                return _CompletedTaskRow(order: order, machines: machines, users: users, helpers: helpers, typeDetail: _typeDetail(order));
              }).toList(),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final monthStart = _month;
    final monthEnd = DateTime(_month.year, _month.month + 1);
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('Today', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          _taskList(start: todayStart, end: now.add(const Duration(minutes: 1))),
          const SizedBox(height: 28),
          Row(
            children: [
              const Expanded(child: Text('Monthly History', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold))),
              IconButton(onPressed: () => setState(() => _month = DateTime(_month.year, _month.month - 1)), icon: const Icon(Icons.chevron_left)),
              Text('${_month.year}-${_month.month.toString().padLeft(2, '0')}'),
              IconButton(onPressed: () => setState(() => _month = DateTime(_month.year, _month.month + 1)), icon: const Icon(Icons.chevron_right)),
            ],
          ),
          const SizedBox(height: 8),
          _monthlyTaskList(start: monthStart, end: monthEnd),
        ],
    );
  }
}

// Loads a month's completed tasks a page at a time instead of one
// unbounded live listener — a busy month can have thousands of entries,
// and pulling them all into memory at once gets slow and wasteful as
// history grows. This trades away live auto-updates for the monthly
// list (a completed, historical record doesn't need to be live the way
// an in-progress task does) in exchange for predictable, bounded loads.
class _PaginatedMonthlyTasks extends StatefulWidget {
  final DateTime start;
  final DateTime end;
  final String Function(WorkOrder) typeCode;
  final String Function(WorkOrder) typeDetail;
  final Future<List<AppUser>> Function() users;
  final Future<List<Helper>> Function() helpers;
  final Future<Map<String, Machine>> Function() machines;

  const _PaginatedMonthlyTasks({
    required this.start,
    required this.end,
    required this.typeCode,
    required this.typeDetail,
    required this.users,
    required this.helpers,
    required this.machines,
  });

  @override
  State<_PaginatedMonthlyTasks> createState() => _PaginatedMonthlyTasksState();
}

class _PaginatedMonthlyTasksState extends State<_PaginatedMonthlyTasks> {
  static const _pageSize = 50;

  final List<WorkOrder> _orders = [];
  DocumentSnapshot<Map<String, dynamic>>? _lastDoc;
  bool _isLoading = false;
  bool _hasMore = true;
  Map<String, AppUser> _users = {};
  Map<String, Helper> _helpers = {};
  Map<String, Machine> _machines = {};
  bool _peopleLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadPeople();
    _loadNextPage();
  }

  @override
  void didUpdateWidget(covariant _PaginatedMonthlyTasks oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.start != widget.start || oldWidget.end != widget.end) {
      // Month changed (user tapped the arrows) — reset and reload.
      setState(() {
        _orders.clear();
        _lastDoc = null;
        _hasMore = true;
      });
      _loadNextPage();
    }
  }

  Future<void> _loadPeople() async {
    final results = await Future.wait([widget.users(), widget.helpers(), widget.machines()]);
    if (!mounted) return;
    setState(() {
      _users = {for (final u in results[0] as List<AppUser>) u.uid: u};
      _helpers = {for (final h in results[1] as List<Helper>) h.uid: h};
      _machines = results[2] as Map<String, Machine>;
      _peopleLoaded = true;
    });
  }

  Future<void> _loadNextPage() async {
    if (_isLoading || !_hasMore) return;
    setState(() => _isLoading = true);

    var query = FirebaseFirestore.instance
        .collection('work_orders')
        .where('status', isEqualTo: 'completed')
        .where('completedAt', isGreaterThanOrEqualTo: Timestamp.fromDate(widget.start))
        .where('completedAt', isLessThan: Timestamp.fromDate(widget.end))
        .orderBy('completedAt', descending: true)
        .limit(_pageSize);

    if (_lastDoc != null) {
      query = query.startAfterDocument(_lastDoc!);
    }

    try {
      final snap = await query.get();
      if (!mounted) return;
      setState(() {
        _orders.addAll(snap.docs.map((d) => WorkOrder.fromMap(d.id, d.data())));
        _lastDoc = snap.docs.isNotEmpty ? snap.docs.last : _lastDoc;
        _hasMore = snap.docs.length == _pageSize;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load more tasks: $e')),
      );
    }
  }

  void _removeLocally(String orderId) {
    setState(() => _orders.removeWhere((o) => o.id == orderId));
  }

  @override
  Widget build(BuildContext context) {
    if (!_peopleLoaded || (_orders.isEmpty && _isLoading)) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_orders.isEmpty) {
      return const Card(
        child: Padding(padding: EdgeInsets.all(18), child: Text('No completed tasks in this period.')),
      );
    }

    // Grouped by date rather than one flat list — _orders is already
    // sorted newest-first (the query orders by completedAt descending),
    // so a date header just needs to appear whenever the date changes
    // between one row and the next.
    final children = <Widget>[];
    DateTime? lastDate;
    for (final order in _orders) {
      final completedAt = order.completedAt;
      final orderDate = completedAt == null ? null : DateTime(completedAt.year, completedAt.month, completedAt.day);
      if (orderDate != null && orderDate != lastDate) {
        children.add(_DateHeader(date: orderDate));
        lastDate = orderDate;
      }
      children.add(_CompletedTaskRow(
        order: order,
        machines: _machines,
        users: _users,
        helpers: _helpers,
        typeDetail: widget.typeDetail(order),
        onDeleted: () => _removeLocally(order.id),
      ));
    }

    return Column(
      children: [
        ...children,
        if (_hasMore)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Center(
              child: _isLoading
                  ? const CircularProgressIndicator()
                  : OutlinedButton.icon(
                      onPressed: _loadNextPage,
                      icon: const Icon(Icons.expand_more),
                      label: const Text('Load more'),
                    ),
            ),
          ),
      ],
    );
  }
}

/// A tappable row for one completed task — tapping opens the full detail
/// sheet (see showCompletedTaskDetail below), which is also where
/// deleting it lives.
/// A date separator between groups of completed tasks in the monthly
/// history list, so it's unmistakable when one day's tasks end and the
/// next day's begin.
class _DateHeader extends StatelessWidget {
  final DateTime date;
  const _DateHeader({required this.date});

  @override
  Widget build(BuildContext context) {
    const weekdays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    const months = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
    final label = '${weekdays[date.weekday - 1]}, ${date.day} ${months[date.month - 1]} ${date.year}';
    return Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 6),
      child: Row(children: [
        Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.muted)),
        const SizedBox(width: 10),
        Expanded(child: Divider(color: AppColors.muted.withValues(alpha: 0.25))),
      ]),
    );
  }
}

class _CompletedTaskRow extends StatelessWidget {
  final WorkOrder order;
  final Map<String, Machine> machines;
  final Map<String, AppUser> users;
  final Map<String, Helper> helpers;
  final String typeDetail;
  final VoidCallback? onDeleted;

  const _CompletedTaskRow({
    required this.order,
    required this.machines,
    required this.users,
    required this.helpers,
    required this.typeDetail,
    this.onDeleted,
  });

  @override
  Widget build(BuildContext context) {
    final machine = machines[order.machineId];
    // Union with contributorIds so a JO who left this task early (before
    // whoever finished it did) still shows up here as having worked on
    // it — assignedTechnicianIds alone is just the final roster.
    final techNames = {...order.assignedTechnicianIds, ...order.contributorIds}.map((id) => users[id]?.name).whereType<String>().toList();
    final helperNames = order.helperIds.map((id) => helpers[id]?.name).whereType<String>().toList();
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(child: Text(taskTypeCode(order.type))),
        title: Row(children: [
          Expanded(child: Text(order.displayTitle(machineLabel: machine?.displayName), maxLines: 1, overflow: TextOverflow.ellipsis)),
          if (order.lateEntry) ...[const SizedBox(width: 6), lateEntryBadge()],
        ]),
        subtitle: Text([
          if (typeDetail.isNotEmpty) typeDetail,
          formatDateTime12h(order.completedAt),
        ].join(' · ')),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => showCompletedTaskDetail(
          context,
          order: order,
          machine: machine,
          otherUnitLabels: order.groupMachineIds.map((id) => machines[id]?.equipmentId ?? id).toList(),
          technicianNames: techNames,
          helperNames: helperNames,
          onDeleted: onDeleted,
        ),
      ),
    );
  }
}

/// Shows the full details of a completed task in a bottom sheet, with a
/// Delete action (confirmed before it actually deletes). Shared by the
/// admin's completed-tasks list and the home dashboard's today widget so
/// both present the same detail view.
Future<void> showCompletedTaskDetail(
  BuildContext context, {
  required WorkOrder order,
  required Machine? machine,
  List<String> otherUnitLabels = const [],
  required List<String> technicianNames,
  required List<String> helperNames,
  VoidCallback? onDeleted,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => _CompletedTaskDetailSheet(
      order: order,
      machine: machine,
      otherUnitLabels: otherUnitLabels,
      technicianNames: technicianNames,
      helperNames: helperNames,
      onDeleted: onDeleted,
    ),
  );
}

class _CompletedTaskDetailSheet extends StatefulWidget {
  final WorkOrder order;
  final Machine? machine;
  final List<String> otherUnitLabels;
  final List<String> technicianNames;
  final List<String> helperNames;
  final VoidCallback? onDeleted;

  const _CompletedTaskDetailSheet({
    required this.order,
    required this.machine,
    this.otherUnitLabels = const [],
    required this.technicianNames,
    required this.helperNames,
    this.onDeleted,
  });

  @override
  State<_CompletedTaskDetailSheet> createState() => _CompletedTaskDetailSheetState();
}

class _CompletedTaskDetailSheetState extends State<_CompletedTaskDetailSheet> {
  bool _isDeleting = false;
  bool _isSavingRemarks = false;
  late String _remarks = widget.order.completionRemarks;
  late String _description = widget.order.description;
  late DateTime? _startedAt = widget.order.startedAt;
  late DateTime? _completedAt = widget.order.completedAt;
  late int? _durationSeconds = widget.order.durationSeconds;
  late String _machineId = widget.order.machineId;
  late List<String> _groupMachineIds = List.of(widget.order.groupMachineIds);
  late Machine? _machine = widget.machine;
  late List<String> _otherUnitLabels = List.of(widget.otherUnitLabels);

  Future<void> _editDescription() async {
    final controller = TextEditingController(text: _description);
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Edit starting remarks'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 5,
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, controller.text.trim()), child: const Text('Save')),
        ],
      ),
    );
    controller.dispose();
    if (result == null || !mounted) return;
    try {
      await FirebaseFirestore.instance.collection('work_orders').doc(widget.order.id).update({'description': result});
      if (mounted) setState(() => _description = result);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to save: $e')));
    }
  }

  // Start and end are edited independently (each with its own button, next
  // to its own row) rather than as a single combined flow -- a combined
  // flow's end-date picker had to take the (possibly just-changed) new
  // start as its firstDate while also trying to default to the OLD end
  // date as initialDate, which crashes whenever the new start lands after
  // the old end. Editing one side at a time avoids that: each picker only
  // ever has to be consistent with the OTHER value, which never changes
  // out from under it mid-flow.
  Future<void> _editStartTime() async {
    final now = DateTime.now();
    final current = _startedAt ?? now;

    final date = await showDatePicker(context: context, initialDate: current, firstDate: current.subtract(const Duration(days: 365)), lastDate: now);
    if (date == null || !mounted) return;
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(current));
    if (time == null) return;
    final newStart = DateTime(date.year, date.month, date.day, time.hour, time.minute);

    if (newStart.isAfter(now)) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Start time cannot be in the future.')));
      return;
    }
    if (_completedAt != null && !newStart.isBefore(_completedAt!)) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Start time must be before the completion time.')));
      return;
    }

    final newDuration = _completedAt != null ? _completedAt!.difference(newStart).inSeconds : _durationSeconds;
    try {
      final update = <String, dynamic>{'startedAt': Timestamp.fromDate(newStart)};
      if (newDuration != null) update['durationSeconds'] = newDuration;
      // Kept in sync for the same reason as technician_screen.dart's own
      // start-time edit: contributorJoinTimes takes precedence over
      // startedAt when computing the creator's own engaged time (see
      // WorkOrder.contributorInterval), so leaving it stale here would
      // silently keep their hours-worked figure wrong.
      if (widget.order.createdBy.isNotEmpty) update['contributorJoinTimes.${widget.order.createdBy}'] = Timestamp.fromDate(newStart);
      await FirebaseFirestore.instance.collection('work_orders').doc(widget.order.id).update(update);
      if (mounted) {
        setState(() {
          _startedAt = newStart;
          if (newDuration != null) _durationSeconds = newDuration;
        });
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to save: $e')));
    }
  }

  Future<void> _editEndTime() async {
    final now = DateTime.now();
    final current = _completedAt ?? now;

    final date = await showDatePicker(context: context, initialDate: current, firstDate: current.subtract(const Duration(days: 365)), lastDate: now);
    if (date == null || !mounted) return;
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(current));
    if (time == null) return;
    final newEnd = DateTime(date.year, date.month, date.day, time.hour, time.minute);

    if (newEnd.isAfter(now)) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Completion time cannot be in the future.')));
      return;
    }
    if (_startedAt != null && !newEnd.isAfter(_startedAt!)) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Completion time must be after the start time.')));
      return;
    }

    final newDuration = _startedAt != null ? newEnd.difference(_startedAt!).inSeconds : _durationSeconds;
    try {
      final update = <String, dynamic>{'completedAt': Timestamp.fromDate(newEnd)};
      if (newDuration != null) update['durationSeconds'] = newDuration;
      await FirebaseFirestore.instance.collection('work_orders').doc(widget.order.id).update(update);
      if (mounted) {
        setState(() {
          _completedAt = newEnd;
          if (newDuration != null) _durationSeconds = newDuration;
        });
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to save: $e')));
    }
  }

  Future<void> _editMachines() async {
    final snap = await FirebaseFirestore.instance.collection('machines').orderBy('equipmentName').get();
    final machines = snap.docs.map((d) => Machine.fromMap(d.id, d.data())).toList();
    final selected = <String>{
      if (_machineId.isNotEmpty) _machineId,
      ..._groupMachineIds,
    };

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Text('Select Machine(s)', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 420),
                child: ListView(
                  shrinkWrap: true,
                  children: machines.map((m) {
                    return CheckboxListTile(
                      value: selected.contains(m.id),
                      title: Text(m.displayName),
                      subtitle: m.equipmentId.isNotEmpty ? Text(m.equipmentId) : null,
                      onChanged: (v) {
                        setSheetState(() {
                          if (v == true) {
                            selected.add(m.id);
                          } else {
                            selected.remove(m.id);
                          }
                        });
                      },
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () async {
                    final ids = selected.toList();
                    Navigator.pop(sheetContext);
                    final newMachineId = ids.isEmpty ? '' : ids.first;
                    final newGroupIds = ids.length > 1 ? ids.sublist(1) : <String>[];
                    try {
                      await FirebaseFirestore.instance.collection('work_orders').doc(widget.order.id).update({
                        'machineId': newMachineId,
                        'groupMachineIds': newGroupIds,
                      });
                      final byId = {for (final m in machines) m.id: m};
                      final newMachine = newMachineId.isEmpty ? null : byId[newMachineId];
                      final newOtherLabels = newGroupIds.map((id) => byId[id]?.equipmentId ?? id).toList();
                      if (mounted) {
                        setState(() {
                          _machineId = newMachineId;
                          _groupMachineIds = newGroupIds;
                          _machine = newMachine;
                          _otherUnitLabels = newOtherLabels;
                        });
                      }
                    } catch (e) {
                      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not update machines: $e')));
                    }
                  },
                  child: Text('Save (${selected.length} selected)'),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Future<void> _editRemarks() async {
    final controller = TextEditingController(text: _remarks);
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Edit completion remarks'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 5,
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, controller.text.trim()), child: const Text('Save')),
        ],
      ),
    );
    controller.dispose();
    if (result == null || !mounted) return;

    setState(() => _isSavingRemarks = true);
    try {
      await FirebaseFirestore.instance.collection('work_orders').doc(widget.order.id).update({'completionRemarks': result});
      if (mounted) setState(() { _remarks = result; _isSavingRemarks = false; });
    } catch (e) {
      if (mounted) {
        setState(() => _isSavingRemarks = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to save: $e')));
      }
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete this task?'),
        content: const Text('This permanently deletes the record. This cannot be undone.'),
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
    if (confirmed != true || !mounted) return;

    setState(() => _isDeleting = true);
    try {
      await FirebaseFirestore.instance.collection('work_orders').doc(widget.order.id).delete();
      widget.onDeleted?.call();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() => _isDeleting = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to delete: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final order = widget.order;
    final machine = _machine;
    // Main unit + other units, merged into one sorted list under a
    // single "Equipment ID" row — the nickname shown in the title above
    // already identifies the machine/group, so a separate "Group: <name>"
    // row would just repeat it.
    final equipmentIds = {
      if (machine != null && machine.equipmentId.isNotEmpty) machine.equipmentId,
      ..._otherUnitLabels,
    }.toList()
      ..sort();
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(children: [
                CircleAvatar(child: Text(taskTypeCode(order.type))),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    // The AI-generated title (for an 'others' task) is
                    // derived from the ORIGINAL starting remarks -- if
                    // those get edited below, this title can go stale,
                    // but re-summarizing on every edit here felt like
                    // more surprise than value for a historical record.
                    order.displayTitle(machineLabel: machine?.fullLabel),
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
                if (order.lateEntry) ...[const SizedBox(width: 6), lateEntryBadge()],
                const SizedBox(width: 8),
                Text(_duration(_durationSeconds), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
              ]),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(child: _detailRow('Started', formatDateTime12h(_startedAt))),
                InkWell(
                  onTap: _editStartTime,
                  borderRadius: BorderRadius.circular(6),
                  child: const Padding(padding: EdgeInsets.all(2), child: Icon(Icons.edit_outlined, size: 16, color: AppColors.muted)),
                ),
                const SizedBox(width: 10),
                Expanded(child: _detailRow('Completed', formatDateTime12h(_completedAt))),
                InkWell(
                  onTap: _editEndTime,
                  borderRadius: BorderRadius.circular(6),
                  child: const Padding(padding: EdgeInsets.all(2), child: Icon(Icons.edit_outlined, size: 16, color: AppColors.muted)),
                ),
              ]),
              const SizedBox(height: 2),
              PeopleLine(widget.technicianNames, widget.helperNames),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                  child: equipmentIds.isEmpty
                      ? const Text('No machine selected.', style: TextStyle(color: AppColors.muted, fontSize: 13, fontStyle: FontStyle.italic))
                      : _detailRow('Equipment ID', equipmentIds.join(', ')),
                ),
                InkWell(
                  onTap: _editMachines,
                  borderRadius: BorderRadius.circular(6),
                  child: const Padding(padding: EdgeInsets.all(2), child: Icon(Icons.edit_outlined, size: 16, color: AppColors.muted)),
                ),
              ]),
              if (order.preventiveTypes.isNotEmpty) _detailRow('Preventive type', order.preventiveTypes.join(', ')),
              const SizedBox(height: 8),
              Row(children: [
                const Text('Starting remarks', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.muted)),
                const SizedBox(width: 6),
                InkWell(
                  onTap: _editDescription,
                  borderRadius: BorderRadius.circular(6),
                  child: const Padding(padding: EdgeInsets.all(2), child: Icon(Icons.edit_outlined, size: 16, color: AppColors.muted)),
                ),
              ]),
              const SizedBox(height: 2),
              Text(_description.trim().isEmpty ? 'No remarks.' : _description.trim(), style: _description.trim().isEmpty ? const TextStyle(color: AppColors.muted, fontStyle: FontStyle.italic) : null),
              const SizedBox(height: 10),
              Row(children: [
                const Text('Completion remarks', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.muted)),
                const SizedBox(width: 6),
                if (_isSavingRemarks)
                  const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                else
                  InkWell(
                    onTap: _editRemarks,
                    borderRadius: BorderRadius.circular(6),
                    child: const Padding(padding: EdgeInsets.all(2), child: Icon(Icons.edit_outlined, size: 16, color: AppColors.muted)),
                  ),
              ]),
              const SizedBox(height: 2),
              Text(_remarks.trim().isEmpty ? 'No remarks.' : _remarks.trim(), style: _remarks.trim().isEmpty ? const TextStyle(color: AppColors.muted, fontStyle: FontStyle.italic) : null),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _isDeleting ? null : _delete,
                  icon: _isDeleting ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.delete_outline),
                  label: const Text('Delete task'),
                  style: OutlinedButton.styleFrom(foregroundColor: AppColors.danger, side: const BorderSide(color: AppColors.danger)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: RichText(
        text: TextSpan(
          style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 14),
          children: [
            TextSpan(text: '$label: ', style: const TextStyle(fontWeight: FontWeight.w600)),
            TextSpan(text: value),
          ],
        ),
      ),
    );
  }

  String _duration(int? seconds) {
    if (seconds == null || seconds < 0) return '—';
    final d = Duration(seconds: seconds);
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    if (h > 0) return '${h}h ${m}m';
    if (m > 0) return '${m}m ${s}s';
    return '${s}s';
  }
}

/// Small "Late Entry" badge shown next to a task that was typed in after
/// the fact (see LateEntryScreen) rather than tracked live, so admin can
/// tell the recorded times were a JO's recollection, not a live capture.
Widget lateEntryBadge() {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
    decoration: BoxDecoration(
      color: AppColors.warning.withValues(alpha: 0.15),
      borderRadius: BorderRadius.circular(6),
    ),
    child: const Text(
      'Late Entry',
      style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.warning),
    ),
  );
}
