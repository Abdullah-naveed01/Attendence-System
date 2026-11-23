import '../core/supabase_client.dart';
import '../models/timetable_slot.dart';

// Reads the timetable table (see sql/timetable.sql).
class TimetableService {
  // All timetable slots this user may see, with the course of each slot.
  // RLS decides which rows come back:
  //   teacher -> their own courses, student -> enrolled courses, admin -> all.
  Future<List<TimetableSlot>> getMySlots() async {
    final rows = await supabase
        .from('timetable')
        .select('*, courses(*)')
        .order('day_of_week')
        .order('start_time');

    final slots = rows
        // skip a slot if its course could not be read
        .where((row) => row['courses'] != null)
        .map((row) => TimetableSlot.fromMap(row))
        .toList();

    // Always Monday -> Sunday, then by start time
    // (so "Thu 13:30" is listed before "Fri 14:30").
    slots.sort((a, b) {
      if (a.dayOfWeek != b.dayOfWeek) return a.dayOfWeek - b.dayOfWeek;
      return a.startMinutes - b.startMinutes;
    });
    return slots;
  }
}

// Only today's slots, in time order.
List<TimetableSlot> slotsForToday(List<TimetableSlot> slots, DateTime now) {
  return slots.where((slot) => slot.dayOfWeek == now.weekday).toList();
}
