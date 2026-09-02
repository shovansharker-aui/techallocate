import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../models/water_plant_personnel.dart';
import '../utils/app_colors.dart';
import '../utils/water_plant.dart';

// Admin's live Water Plant view — two tiles (GP / Softgel) each listing
// who's currently assigned there (after the 1PM swap is applied) and
// their Day/Night/On-Leave status for today.
class WaterPlantOverviewScreen extends StatelessWidget {
  const WaterPlantOverviewScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Water Plant')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance.collection('water_plant_personnel').orderBy('name').snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Unable to load: ${snapshot.error}'));
          }

          final people = (snapshot.data?.docs ?? [])
              .map((d) => WaterPlantPersonnel.fromMap(d.id, d.data()))
              .toList();

          final gp = people.where((p) => effectivePlant(p.plant) == 'gp').toList();
          final softgel = people.where((p) => effectivePlant(p.plant) == 'softgel').toList();

          return Padding(
            padding: const EdgeInsets.all(16),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final twoColumn = constraints.maxWidth >= 500;
                final tiles = [
                  _plantTile('GP Water Plant', Icons.water_drop_outlined, AppColors.categoryProduction, gp),
                  _plantTile('Softgel Water Plant', Icons.water_drop_outlined, AppColors.categoryEngineering, softgel),
                ];
                if (!twoColumn) {
                  return ListView(children: [tiles[0], const SizedBox(height: 12), tiles[1]]);
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
          );
        },
      ),
    );
  }

  Widget _plantTile(String title, IconData icon, Color color, List<WaterPlantPersonnel> people) {
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
            const SizedBox(height: 14),
            if (people.isEmpty)
              const Text('No one currently assigned here.', style: TextStyle(color: AppColors.muted))
            else
              ...people.map((p) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Row(children: [
                      CircleAvatar(radius: 14, child: Text(p.name.isEmpty ? '?' : p.name[0].toUpperCase())),
                      const SizedBox(width: 10),
                      Expanded(child: Text(p.name, overflow: TextOverflow.ellipsis)),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: p.dutyStatus == 'on_leave'
                              ? AppColors.danger.withValues(alpha: 0.12)
                              : AppColors.success.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          dutyStatusLabel(p.dutyStatus),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: p.dutyStatus == 'on_leave' ? AppColors.danger : AppColors.success,
                          ),
                        ),
                      ),
                    ]),
                  )),
          ],
        ),
      ),
    );
  }
}
