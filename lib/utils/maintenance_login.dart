import 'package:cloud_firestore/cloud_firestore.dart';

/// Creates the login (a 'users' doc, role technician) that lets an
/// existing Water Plant person also work as a maintenance JO, with the
/// Water Plant screens on their dashboard (waterPlantAccess). Links it
/// back on their water_plant_personnel doc via maintenanceUserId.
/// Throws a String message if the Employee ID is already used by a login.
Future<String> createMaintenanceLogin({
  required String personnelDocId,
  required String name,
  required String employeeId,
  required String phone,
  required String pin,
}) async {
  final firestore = FirebaseFirestore.instance;
  final existing = await firestore.collection('users').where('employeeId', isEqualTo: employeeId).limit(1).get();
  if (existing.docs.isNotEmpty) throw 'A login with Employee ID $employeeId already exists.';
  final ref = firestore.collection('users').doc();
  final batch = firestore.batch();
  batch.set(ref, {
    'name': name,
    'employeeId': employeeId,
    'phone': phone,
    'pin': pin,
    'role': 'technician',
    'waterPlantAccess': true,
    'trade': '',
    'shift': '',
    'status': 'available',
    'dutyStatus': 'day',
    'currentTaskId': null,
    'createdAt': FieldValue.serverTimestamp(),
  });
  batch.update(firestore.collection('water_plant_personnel').doc(personnelDocId), {'maintenanceUserId': ref.id});
  await batch.commit();
  return ref.id;
}
