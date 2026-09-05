class AppUser {
  final String uid;
  final String name;
  final String role;
  final String employeeId;
  final String trade;
  final String shift;
  final String phone;
  final String status; // available | assigned | on_leave
  final String dutyStatus; // day | night | on_leave
  // 'YYYY-MM-DD' of the last date this JO actually set their status —
  // used to require it again after 8:00 AM on a new day (see
  // TechnicianScreen's mandatory check-in).
  final String dutyStatusDate;
  final String? currentTaskId;
  // Id of the last admin Notify broadcast this person has already been
  // shown — kept on their own account doc (not local device storage) so
  // "seen it once" holds across devices/browsers/incognito tabs, all of
  // which are the same person as far as this app can tell. See
  // NotifyService.
  final String lastNotifySeenId;

  AppUser({
    required this.uid,
    required this.name,
    required this.role,
    required this.employeeId,
    required this.trade,
    required this.shift,
    required this.phone,
    required this.status,
    required this.dutyStatus,
    this.dutyStatusDate = '',
    this.currentTaskId,
    this.lastNotifySeenId = '',
  });

  factory AppUser.fromMap(String uid, Map<String, dynamic> data) {
    return AppUser(
      uid: uid,
      name: data['name'] ?? '',
      role: data['role'] ?? 'technician',
      employeeId: data['employeeId'] ?? '',
      trade: data['trade'] ?? '',
      shift: data['shift'] ?? '',
      phone: data['phone'] ?? '',
      status: data['status'] ?? 'available',
      dutyStatus: (data['dutyStatus'] ?? data['shift'] ?? 'day').toString(),
      dutyStatusDate: (data['dutyStatusDate'] ?? '').toString(),
      currentTaskId: data['currentTaskId'],
      lastNotifySeenId: (data['lastNotifySeenId'] ?? '').toString(),
    );
  }
}
