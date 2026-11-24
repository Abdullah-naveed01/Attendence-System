// Simple date/time formatting without adding a package.
// All times are converted to the phone's local time zone.

const _days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _fullDays = [
  'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday',
];
const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

// e.g. "Mon, 23 Nov 2026"
String formatDate(DateTime date) {
  final d = date.toLocal();
  return '${_days[d.weekday - 1]}, ${d.day} ${_months[d.month - 1]} ${d.year}';
}

// e.g. "2:05 PM"
String formatTime(DateTime date) {
  final d = date.toLocal();
  return formatClock(d.hour * 60 + d.minute);
}

// A moment in time shown as a Pakistan date + time (UTC+5),
// e.g. "Tue, 24 Nov 2026, 10:32 AM", whatever time zone the phone uses.
String formatPakistanDateTime(DateTime date) {
  final pk = date.toUtc().add(const Duration(hours: 5));
  return '${_days[pk.weekday - 1]}, ${pk.day} ${_months[pk.month - 1]} '
      '${pk.year}, ${formatClock(pk.hour * 60 + pk.minute)}';
}

// A moment in time shown as Pakistan time (UTC+5), e.g. "10:32 PM",
// whatever time zone the phone is set to.
String formatPakistanTime(DateTime date) {
  final pk = date.toUtc().add(const Duration(hours: 5));
  return formatClock(pk.hour * 60 + pk.minute);
}

// Minutes since midnight -> "8:30 AM"
String formatClock(int minutesSinceMidnight) {
  final h24 = minutesSinceMidnight ~/ 60;
  final minute = (minutesSinceMidnight % 60).toString().padLeft(2, '0');
  final hour = h24 % 12 == 0 ? 12 : h24 % 12;
  final amPm = h24 < 12 ? 'AM' : 'PM';
  return '$hour:$minute $amPm';
}

// Minutes since midnight -> "08:30" / "13:30" (24-hour, like the timetable)
String formatClock24(int minutesSinceMidnight) {
  final hour = (minutesSinceMidnight ~/ 60).toString().padLeft(2, '0');
  final minute = (minutesSinceMidnight % 60).toString().padLeft(2, '0');
  return '$hour:$minute';
}

// 1 -> "Mon"
String shortDayName(int weekday) => _days[weekday - 1];

// 1 -> "Monday"
String dayName(int weekday) => _fullDays[weekday - 1];
