import 'package:flutter/material.dart';
import '../widgets_task_type_chart.dart';
import 'graphs_screen.dart';

/// Reached by tapping the "Today's Summary" chart on native Android and
/// mobile/PWA web — since neither has a spare bottom-nav slot for a
/// whole separate "Graphs" section the way desktop does, this is where
/// all the charts live on those platforms instead: the tapped chart
/// shown large at the top, with every other graph (Work Density, and
/// whatever gets added later) scrollable underneath.
class TaskChartsDetailScreen extends StatelessWidget {
  const TaskChartsDetailScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Analysis')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: const [
          SizedBox(height: 340, child: TaskTypeBreakdownCard()),
          SizedBox(height: 18),
          GraphsBody(shrinkWrap: true),
        ],
      ),
    );
  }
}
