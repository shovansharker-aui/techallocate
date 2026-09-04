import 'package:flutter/material.dart';
import '../widgets_work_density_chart.dart';

/// The list of "extra" graphs beyond the main dashboard's Today's
/// Summary chart — currently just Work Density, with room to add more
/// over time. Used two ways:
///  - directly, as desktop's dedicated "Graphs" sidebar section
///  - embedded below the full-width Today's Summary chart on the mobile
///    detail page (TaskChartsDetailScreen), since mobile has no spare
///    bottom-nav slot for a whole separate section
class GraphsBody extends StatelessWidget {
  final bool shrinkWrap;
  const GraphsBody({super.key, this.shrinkWrap = false});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      shrinkWrap: shrinkWrap,
      physics: shrinkWrap ? const NeverScrollableScrollPhysics() : null,
      children: const [
        WorkDensityCard(),
        // Add future graphs here, each as its own card.
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
      appBar: AppBar(title: const Text('Analysis')),
      body: const GraphsBody(),
    );
  }
}
