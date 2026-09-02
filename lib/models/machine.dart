class Machine {
  final String id;
  final String equipmentId;
  final String equipmentName;
  final String brand; // Firestore field name kept as "brand" for backward
                       // compatibility with existing data — shown to the
                       // user as "Nickname" everywhere in the UI.
  final String category; // 'Engineering' | 'Production' | 'Warehouse'
  // Groups multiple physical units that belong to one larger machine
  // (e.g. a Tablet Compression unit's deduster + dust collector). 'N/A'
  // means this machine isn't part of any group.
  final String group;

  Machine({
    required this.id,
    required this.equipmentId,
    required this.equipmentName,
    required this.brand,
    required this.category,
    this.group = 'N/A',
  });

  /// What to show a JO picking a machine to work on: the nickname if
  /// one's set, otherwise the equipment name.
  String get displayName => brand.trim().isNotEmpty ? brand.trim() : equipmentName;

  /// What admin sees everywhere a machine is displayed: the real
  /// equipment name, with the nickname in brackets if one's set —
  /// e.g. "Tablet Compression Unit 1 (TC-1)".
  String get fullLabel => brand.trim().isNotEmpty ? '$equipmentName (${brand.trim()})' : equipmentName;

  bool get isGrouped => group.trim().isNotEmpty && group.trim().toUpperCase() != 'N/A';

  factory Machine.fromMap(String id, Map<String, dynamic> data) {
    return Machine(
      id: id,
      equipmentId: data['equipmentId'] ?? '',
      equipmentName: data['equipmentName'] ?? '',
      brand: data['brand'] ?? '',
      category: data['category'] ?? 'Production',
      group: (data['group'] ?? 'N/A').toString().trim().isEmpty ? 'N/A' : (data['group'] ?? 'N/A').toString(),
    );
  }
}
