import 'package:flutter_test/flutter_test.dart';

import 'package:smart_attendance/core/pakistan_time.dart';
import 'package:smart_attendance/models/course.dart';
import 'package:smart_attendance/models/timetable_slot.dart';

Course course() =>
    Course(id: 'c1', name: 'Mobile App Dev', code: 'CS-301', semester: '5');

TimetableSlot makeSlot(int day, String start, String end) => TimetableSlot(
      id: '$day$start',
      course: course(),
      dayOfWeek: day,
      startMinutes: TimetableSlot.timeToMinutes(start),
      endMinutes: TimetableSlot.timeToMinutes(end),
    );

// Monday 08:30 - 11:30 (Mobile App Dev Lab)
final mondayLab = makeSlot(DateTime.monday, '08:30:00', '11:30:00');
// Wednesday 11:00 - 13:00 (Mobile App Dev lecture)
final wednesday = makeSlot(DateTime.wednesday, '11:00:00', '13:00:00');

// 23 Nov 2026 is a Monday.
DateTime monday(int hour, int minute) => DateTime(2026, 11, 23, hour, minute);

void main() {
  test('time text is converted to minutes', () {
    expect(TimetableSlot.timeToMinutes('08:30:00'), 510);
    expect(TimetableSlot.timeToMinutes('16:30'), 990);
  });

  test('Start Class opens exactly at start_time', () {
    expect(mondayLab.statusAt(monday(8, 29)), SlotStatus.upcoming);
    expect(mondayLab.canStartAt(monday(8, 29)), false);
    expect(mondayLab.canStartAt(monday(8, 30)), true);
    expect(mondayLab.canStartAt(monday(10, 0)), true);
  });

  test('Start Class closes at end_time', () {
    expect(mondayLab.canStartAt(monday(11, 29)), true);
    expect(mondayLab.statusAt(monday(11, 30)), SlotStatus.finished);
    expect(mondayLab.canStartAt(monday(11, 30)), false);
  });

  test('another day is never open', () {
    final tuesday = DateTime(2026, 11, 24, 9, 0);
    expect(mondayLab.statusAt(tuesday), SlotStatus.notToday);
    expect(mondayLab.canStartAt(tuesday), false);
  });

  test('"Opens ..." text picks the next class', () {
    final slots = [mondayLab, wednesday];
    // Monday 07:00 -> today's lab
    expect(opensText(slots, monday(7, 0)), 'Opens today 08:30');
    // Monday 12:00 -> Wednesday lecture
    expect(opensText(slots, monday(12, 0)), 'Opens Wednesday 11:00');
    // Thursday -> next Monday
    expect(opensText(slots, DateTime(2026, 11, 26, 9, 0)),
        'Opens Monday 08:30');
    expect(opensText([], monday(9, 0)), 'Not in the timetable');
  });

  test('Pakistan time is UTC + 5 hours', () {
    final difference =
        pakistanNow().difference(DateTime.now().toUtc()).inMinutes;
    expect(difference, closeTo(300, 1));
  });
}
