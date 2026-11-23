import '../core/date_format.dart';
import 'course.dart';

// Where "now" (Pakistan time) is compared to one timetable slot.
enum SlotStatus {
  notToday, // the slot is on another day
  upcoming, // later today
  open, // between start_time and end_time -> the class can start
  finished, // already over today
}

// One row of the timetable table: a course on one weekday, from start to end.
// The same rule is checked on the server in start_session:
//   right day AND start_time <= now < end_time  (Pakistan time)
class TimetableSlot {
  final String id;
  final Course course;
  final int dayOfWeek; // 1 = Monday ... 7 = Sunday (same as DateTime.weekday)
  final int startMinutes; // minutes since midnight, e.g. 08:30 -> 510
  final int endMinutes;

  TimetableSlot({
    required this.id,
    required this.course,
    required this.dayOfWeek,
    required this.startMinutes,
    required this.endMinutes,
  });

  // The map comes from: select('*, courses(*)')
  factory TimetableSlot.fromMap(Map<String, dynamic> map) {
    return TimetableSlot(
      id: map['id'] as String,
      course: Course.fromMap(Map<String, dynamic>.from(map['courses'])),
      dayOfWeek: (map['day_of_week'] as num).toInt(),
      startMinutes: timeToMinutes(map['start_time'] as String),
      endMinutes: timeToMinutes(map['end_time'] as String),
    );
  }

  // "08:30:00" -> 510
  static int timeToMinutes(String time) {
    final parts = time.split(':');
    return int.parse(parts[0]) * 60 + int.parse(parts[1]);
  }

  SlotStatus statusAt(DateTime now) {
    if (now.weekday != dayOfWeek) return SlotStatus.notToday;

    final nowMinutes = now.hour * 60 + now.minute;
    if (nowMinutes < startMinutes) return SlotStatus.upcoming;
    if (nowMinutes < endMinutes) return SlotStatus.open;
    return SlotStatus.finished;
  }

  bool canStartAt(DateTime now) => statusAt(now) == SlotStatus.open;

  // e.g. "08:30 - 11:30"
  String get timeRange =>
      '${formatClock24(startMinutes)} - ${formatClock24(endMinutes)}';

  // e.g. "Mon 08:30 - 11:30"
  String get dayAndTime => '${shortDayName(dayOfWeek)} $timeRange';

  // How many minutes from "now" until this slot next starts (0 to 7 days ahead).
  int minutesUntilNextStart(DateTime now) {
    final nowMinutes = now.hour * 60 + now.minute;
    final daysAhead = (dayOfWeek - now.weekday + 7) % 7;
    var minutes = daysAhead * 24 * 60 + startMinutes - nowMinutes;
    if (minutes < 0) minutes += 7 * 24 * 60; // earlier today -> next week
    return minutes;
  }
}

// The next scheduled class among [slots], or null if there are none.
TimetableSlot? nextSlot(List<TimetableSlot> slots, DateTime now) {
  TimetableSlot? best;
  for (final slot in slots) {
    if (best == null ||
        slot.minutesUntilNextStart(now) < best.minutesUntilNextStart(now)) {
      best = slot;
    }
  }
  return best;
}

// Text for a closed "Start Class" button, e.g. "Opens Monday 08:30"
// or "Opens today 13:30". [slots] are the slots of one course.
String opensText(List<TimetableSlot> slots, DateTime now) {
  final next = nextSlot(slots, now);
  if (next == null) return 'Not in the timetable';

  final nowMinutes = now.hour * 60 + now.minute;
  final laterToday =
      next.dayOfWeek == now.weekday && next.startMinutes > nowMinutes;
  final day = laterToday ? 'today' : dayName(next.dayOfWeek);
  return 'Opens $day ${formatClock24(next.startMinutes)}';
}
