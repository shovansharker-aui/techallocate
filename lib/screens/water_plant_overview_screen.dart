import 'package:flutter/material.dart';
import '../utils/app_colors.dart';

// Landing screen for the "Water Plant" section of the admin nav — two
// grid tiles (GP / Softgel). The real live personnel-per-plant list gets
// wired in here in Phase 3, once the Water Plant login and manager
// dashboard exist to actually produce that data.
class WaterPlantOverviewScreen extends StatelessWidget {
  const WaterPlantOverviewScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Water Plant')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final twoColumn = constraints.maxWidth >= 500;
            final tiles = [
              _plantTile(context, 'GP Water Plant', Icons.water_drop_outlined, AppColors.categoryProduction),
              _plantTile(context, 'Softgel Water Plant', Icons.water_drop_outlined, AppColors.categoryEngineering),
            ];
            if (!twoColumn) {
              return Column(children: [tiles[0], const SizedBox(height: 12), tiles[1]]);
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: tiles[0]),
                const SizedBox(width: 12),
                Expanded(child: tiles[1]),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _plantTile(BuildContext context, String title, IconData icon, Color color) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              CircleAvatar(backgroundColor: color.withValues(alpha: 0.15), child: Icon(icon, color: color)),
              const SizedBox(width: 10),
              Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
            ]),
            const SizedBox(height: 16),
            const Text(
              'Assigned personnel will show up here once the Water Plant login and manager dashboard are set up (Phase 3).',
              style: TextStyle(color: AppColors.muted),
            ),
          ],
        ),
      ),
    );
  }
}
