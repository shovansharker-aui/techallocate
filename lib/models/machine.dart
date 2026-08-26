class Machine {
  final String id;
  final String equipmentId;
  final String equipmentName;
  final String brand; // Firestore field name kept as "brand" for backward
                       // compatibility with existing data — shown to the
                       // user as "Nickname" everywhere in the UI.
  final String category; // 'Engineering' | 'Production' | 'Warehouse'

  Machine({
    required this.id,
    required this.equipmentId,
    required this.equipmentName,
    required this.brand,
    required this.category,
  });

  /// What to actually show for this machine wherever its name appears:
  /// the nickname if one's set, otherwise the equipment name.
  String get displayName => brand.trim().isNotEmpty ? brand.trim() : equipmentName;

  factory Machine.fromMap(String id, Map<String, dynamic> data) {
    return Machine(
      id: id,
      equipmentId: data['equipmentId'] ?? '',
      equipmentName: data['equipmentName'] ?? '',
      brand: data['brand'] ?? '',
      category: data['category'] ?? 'Production',
    );
  }
}
