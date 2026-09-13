import 'package:flutter/material.dart';
import '../utils/date_format.dart';
import '../widgets_breakdown_trend_chart.dart';
import '../widgets_hour_worked_radar_chart.dart';
import '../widgets_work_density_chart.dart';

/// The list of "extra" graphs beyond the main dashboard's Today's
/// Summary chart. Used two ways:
///  - directly, as desktop's dedicated "Graphs" sidebar section
///    (showEmployeeHours: true — see AdminWebDashboardScreen), which
///    shows Work Density and Hours Worked side by side (daily by
///    default, or a custom date range via the icon next to the day
///    nav), followed by the Breakdown Trend chart (current month by
///    default, or its own custom range via its own top-right icon —
///    see BreakdownTrendChart, which manages that selection itself)
///  - embedded below the full-width Today's Summary chart on the mobile
///    detail page (TaskChartsDetailScreen), since mobile has no spare
///    bottom-nav slot for a whole separate section, and no spare width
///    for a full-roster radar chart or date navigation either — it
///    always shows just today's Work Density, unchanged
class GraphsBody extends StatefulWidget {
  final bool shrinkWrap;
  final bool showEmployeeHours;
  const GraphsBody({super.key, this.shrinkWrap = false, this.showEmployeeHours = false});

  @override
  State<GraphsBody> createState() => _GraphsBodyState();
}

class _GraphsBodyState extends State<GraphsBody> {
  DateTime _selectedDate = _dateOnly(DateTime.now());
  // null = daily mode (day nav below); non-null = a custom range picked
  // via the icon, which switches Work Density + Hours Worked into their
  // range/aggregate forms until switched back to Daily.
  DateTimeRange? _customRange;

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  bool get _isToday => _dateOnly(DateTime.now()) == _selectedDate;
  bool get _isCustom => _customRange != null;

  void _shiftDate(int days) => setState(() => _selectedDate = _selectedDate.add(Duration(days: days)));

  Future<void> _pickCustomRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 3),
      lastDate: now,
      initialDateRange: _customRange ?? DateTimeRange(start: _selectedDate.subtract(const Duration(days: 6)), end: _selectedDate),
    );
    if (picked != null) setState(() => _customRange = picked);
  }

  @override
  Widget build(BuildContext context) {
    final desktop = widget.showEmployeeHours;

    if (!desktop) {
      // Mobile embed: unchanged, always today's Work Density only — no
      // spare width here for the radar chart or range navigation.
      return ListView(
        padding: const EdgeInsets.all(20),
        shrinkWrap: widget.shrinkWrap,
        physics: widget.shrinkWrap ? const NeverScrollableScrollPhysics() : null,
        children: const [WorkDensityCard()],
      );
    }

    final rangeStart = _isCustom ? DateTime(_customRange!.start.year, _customRange!.start.month, _customRange!.start.day) : _selectedDate;
    final rangeEndExclusive = _isCustom ? DateTime(_customRange!.end.year, _customRange!.end.month, _customRange!.end.day).add(const Duration(days: 1)) : _selectedDate.add(const Duration(days: 1));
    final now = DateTime.now();
    final includeRunning = _isCustom ? (!now.isBefore(rangeStart) && now.isBefore(rangeEndExclusive)) : _isToday;
    final hoursLabel = _isCustom ? '${formatDate(_customRange!.start)} – ${formatDate(_customRange!.end)}' : (_isToday ? 'Today' : formatDate(_selectedDate));

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _rangeControl(),
        const SizedBox(height: 16),
        LayoutBuilder(builder: (context, constraints) {
          final density = WorkDensityCard(date: _isCustom ? null : _selectedDate, customRange: _customRange);
          final radar = HourWorkedRadarCard(
            rangeStart: rangeStart,
            rangeEndExclusive: rangeEndExclusive,
            includeRunning: includeRunning,
            title: 'Hours Worked · $hoursLabel',
            subtitle: "Each JO's total engaged time — overlapping tasks are counted once. Tap a point for details.",
          );
          if (constraints.maxWidth < 900) {
            return Column(children: [density, const SizedBox(height: 16), radar]);
          }
          return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: density),
            const SizedBox(width: 16),
            Expanded(child: radar),
          ]);
        }),
        const SizedBox(height: 16),
        const BreakdownTrendChart(),
        // Add future graphs here, each as its own card.
      ],
    );
  }

  Widget _rangeControl() {
    return Row(children: [
      if (!_isCustom) ...[
        IconButton(icon: const Icon(Icons.chevron_left), tooltip: 'Previous day', onPressed: () => _shiftDate(-1)),
        Expanded(child: Center(child: Text(_isToday ? 'Today' : formatDate(_selectedDate), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)))),
        IconButton(icon: const Icon(Icons.chevron_right), tooltip: 'Next day', onPressed: _isToday ? null : () => _shiftDate(1)),
      ] else
        Expanded(
          child: Center(
            child: Text(
              '${formatDate(_customRange!.start)} – ${formatDate(_customRange!.end)}',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
        ),
      PopupMenuButton<String>(
        icon: const Icon(Icons.calendar_month_outlined),
        tooltip: 'Change range',
        onSelected: (value) {
          if (value == 'daily') {
            setState(() => _customRange = null);
          } else {
            _pickCustomRange();
          }
        },
        itemBuilder: (context) => const [
          PopupMenuItem(value: 'daily', child: Text('Daily')),
          PopupMenuItem(value: 'custom', child: Text('Custom Range…')),
        ],
      ),
    ]);
  }
}

/// Thin Scaffold wrapper around GraphsBody, kept for consistency with
/// the other *Screen/*Body pairs in this project even though nothing
/// currently pushes it as a standalone route.
class GraphsScreen extends StatelessWidget {
  const GraphsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Analysis')),
      body: const GraphsBody(),
    );
  }
}
