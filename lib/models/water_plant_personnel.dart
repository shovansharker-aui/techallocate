class WaterPlantPersonnel {
  final String id;
  final String employeeId;
  final String name;
  final String dutyStatus; // 'day' | 'night' | 'on_leave'
  final String plant; // 'gp' | 'softgel' — the AM assignment; the actual
                       // *effective* plant after 1PM is computed, not
                       // stored directly (see utils/water_plant.dart).
  final DateTime? statusSetAt;

  WaterPlantPersonnel({
    required this.id,
    required this.employeeId,
    required this.name,
    required this.dutyStatus,
    required this.plant,
    required this.statusSetAt,
  });

  factory WaterPlantPersonnel.fromMap(String id, Map<String, dynamic> data) {
    return WaterPlantPersonnel(
      id: id,
      employeeId: data['employeeId'] ?? '',
      name: data['name'] ?? '',
      dutyStatus: data['dutyStatus'] ?? 'day',
      plant: data['plant'] ?? 'gp',
      statusSetAt: (data['statusSetAt'] as dynamic)?.toDate(),
    );
  }
}
