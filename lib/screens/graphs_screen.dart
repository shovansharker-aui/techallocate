import 'package:flutter/material.dart';
import '../widgets_breakdown_trend_chart.dart';
import '../widgets_work_density_chart.dart';

/// The list of "extra" graphs beyond the main dashboard's Today's
/// Summary chart. Used two ways:
///  - directly, as desktop's dedicated "Breakdown Summary" sidebar
///    section (showEmployeeHours: true — see AdminWebDashboardScreen):
///    just the Breakdown Trend chart, which manages its own
///    month/custom-range selection (see BreakdownTrendChart)
///  - embedded below the full-width Today's Summary chart on the mobile
///    detail page (TaskChartsDetailScreen), since mobile has no spare
///    bottom-nav slot for a whole separate section — it always shows
///    just today's Work Density, unchanged
class GraphsBody extends StatelessWidget {
  final bool shrinkWrap;
  final bool showEmployeeHours;
  const GraphsBody({super.key, this.shrinkWrap = false, this.showEmployeeHours = false});

  @override
  Widget build(BuildContext context) {
    final desktop = showEmployeeHours;
    return ListView(
      padding: const EdgeInsets.all(20),
      shrinkWrap: shrinkWrap,
      physics: shrinkWrap ? const NeverScrollableScrollPhysics() : null,
      children: [
        if (desktop) const BreakdownTrendChart() else const WorkDensityCard(),
      ],
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
      appBar: AppBar(title: const Text('Breakdown Summary')),
      body: const GraphsBody(),
    );
  }
}
