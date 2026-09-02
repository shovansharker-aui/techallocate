/// Shared date/time formatting — every place in the app that shows a
/// clock time uses these, so the switch to 12-hour AM/PM only had to
/// happen in one place.
library;

String _two(int n) => n.toString().padLeft(2, '0');

/// "25/12/2026 2:45 PM"
String formatDateTime12h(DateTime? value) {
  if (value == null) return '';
  final local = value.toLocal();
  return '${_two(local.day)}/${_two(local.month)}/${local.year} ${formatTime12h(local)}';
}

/// "2:45 PM" — hour is NOT zero-padded (matches how a 12-hour clock is
/// normally written), minute is.
String formatTime12h(DateTime value) {
  final local = value.toLocal();
  final period = local.hour >= 12 ? 'PM' : 'AM';
  final hour12 = local.hour % 12 == 0 ? 12 : local.hour % 12;
  return '$hour12:${_two(local.minute)} $period';
}
