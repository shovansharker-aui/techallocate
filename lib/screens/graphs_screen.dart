import 'package:flutter/material.dart';
import '../utils/date_format.dart';
import '../widgets_breakdown_trend_chart.dart';
import '../widgets_employee_hours_chart.dart';
import '../widgets_monthly_work_hours_chart.dart';
import '../widgets_work_density_chart.dart';

enum _AnalysisView { daily, monthly, breakdownTrend }

/// The list of "extra" graphs beyond the main dashboard's Today's
/// Summary chart. Used two ways:
///  - directly, as desktop's dedicated "Graphs" sidebar section
///    (showEmployeeHours: true — see AdminWebDashboardScreen), which
///    additionally gets a Daily/Monthly/Breakdowns toggle plus day or
///    month navigation to match (showEmployeeHours doubles as "is this
///    the desktop Analysis menu" since only that surface has room for
///    any of it) — Daily shows a single day, Monthly a whole-month
///    overview, Breakdowns a per-machine breakdown-count trend chart
///    for a whole month (both of the latter two share the same month
///    selection)
///  - embedded below the full-width Today's Summary chart on the mobile
///    detail page (TaskChartsDetailScreen), since mobile has no spare
///    bottom-nav slot for a whole separate section, and no spare width
///    for a full-roster leaderboard or date navigation either — it
///    always shows just today's Work Density, unchanged
class GraphsBody extends StatefulWidget {
  final bool shrinkWrap;
  final bool showEmployeeHours;
  const GraphsBody({super.key, this.shrinkWrap = false, this.showEmployeeHours = false});

  @override
  State<GraphsBody> createState() => _GraphsBodyState();
}

class _GraphsBodyState extends State<GraphsBody> {
  _AnalysisView _view = _AnalysisView.daily;
  DateTime _selectedDate = _dateOnly(DateTime.now());
  DateTime _selectedMonth = _monthOnly(DateTime.now());

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);
  static DateTime _monthOnly(DateTime d) => DateTime(d.year, d.month);

  bool get _isToday => _dateOnly(DateTime.now()) == _selectedDate;
  bool get _isCurrentMonth => _monthOnly(DateTime.now()) == _selectedMonth;

  void _shiftDate(int days) => setState(() => _selectedDate = _selectedDate.add(Duration(days: days)));
  void _shiftMonth(int months) => setState(() => _selectedMonth = DateTime(_selectedMonth.year, _selectedMonth.month + months));

  // Ties the Monthly heatmap into the Daily view: tapping a day jumps
  // straight to that day's full breakdown instead of leaving Monthly as
  // a dead end.
  void _jumpToDate(DateTime d) => setState(() {
        _view = _AnalysisView.daily;
        _selectedDate = _dateOnly(d);
      });

  @override
  Widget build(BuildContext context) {
    final desktop = widget.showEmployeeHours;
    return ListView(
      padding: const EdgeInsets.all(20),
      shrinkWrap: widget.shrinkWrap,
      physics: widget.shrinkWrap ? const NeverScrollableScrollPhysics() : null,
      children: [
        if (desktop) ...[
          _viewToggle(),
          const SizedBox(height: 12),
          _view == _AnalysisView.daily ? _dateNav() : _monthNav(),
          const SizedBox(height: 16),
        ],
        if (!desktop || _view == _AnalysisView.daily) WorkDensityCard(date: desktop ? _selectedDate : null),
        if (desktop) ...[
          const SizedBox(height: 16),
          if (_view == _AnalysisView.daily)
            EmployeeHoursCard(
              rangeStart: _selectedDate,
              rangeEndExclusive: _selectedDate.add(const Duration(days: 1)),
              includeRunning: _isToday,
              title: 'Hours Worked · ${_isToday ? 'Today' : formatDate(_selectedDate)}',
              subtitle: "Each JO's total engaged time that day — overlapping tasks are counted once, not added together.",
            )
          else if (_view == _AnalysisView.monthly) ...[
            MonthlyWorkHoursChart(month: _selectedMonth, onSelectDay: _jumpToDate),
            const SizedBox(height: 16),
            EmployeeHoursCard(
              rangeStart: _selectedMonth,
              rangeEndExclusive: DateTime(_selectedMonth.year, _selectedMonth.month + 1),
              includeRunning: _isCurrentMonth,
              title: 'Hours Worked · ${formatMonthYear(_selectedMonth)}',
              subtitle: "Each JO's total engaged time this month — overlapping tasks are counted once, not added together.",
            ),
          ] else
            BreakdownTrendChart(month: _selectedMonth),
        ],
        // Add future graphs here, each as its own card.
      ],
    );
  }

  Widget _viewToggle() {
    return SegmentedButton<_AnalysisView>(
      segments: const [
        ButtonSegment(value: _AnalysisView.daily, label: Text('Daily'), icon: Icon(Icons.today_outlined)),
        ButtonSegment(value: _AnalysisView.monthly, label: Text('Monthly'), icon: Icon(Icons.calendar_view_month_outlined)),
        ButtonSegment(value: _AnalysisView.breakdownTrend, label: Text('Breakdowns'), icon: Icon(Icons.leaderboard_outlined)),
      ],
      selected: {_view},
      onSelectionChanged: (s) => setState(() => _view = s.first),
    );
  }

  Widget _navRow({required VoidCallback onPrev, required VoidCallback? onNext, required String label}) {
    return Row(children: [
      IconButton(icon: const Icon(Icons.chevron_left), tooltip: 'Previous', onPressed: onPrev),
      Expanded(
        child: Center(child: Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold))),
      ),
      IconButton(icon: const Icon(Icons.chevron_right), tooltip: 'Next', onPressed: onNext),
    ]);
  }

  Widget _dateNav() {
    return _navRow(
      onPrev: () => _shiftDate(-1),
      onNext: _isToday ? null : () => _shiftDate(1),
      label: _isToday ? 'Today' : formatDate(_selectedDate),
    );
  }

  Widget _monthNav() {
    return _navRow(
      onPrev: () => _shiftMonth(-1),
      onNext: _isCurrentMonth ? null : () => _shiftMonth(1),
      label: formatMonthYear(_selectedMonth),
    );
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
