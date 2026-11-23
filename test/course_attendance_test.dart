import 'package:flutter_test/flutter_test.dart';

import 'package:smart_attendance/models/course_attendance.dart';

CourseAttendance make(int attended, int total) => CourseAttendance(
      courseId: 'c1',
      courseName: 'Test',
      courseCode: 'CS-000',
      totalSessions: total,
      attendedSessions: attended,
    );

void main() {
  test('percentage = attended / total x 100', () {
    expect(make(3, 4).percentage, 75);
    expect(make(6, 10).percentage, 60);
  });

  test('exactly 75% is not a warning, below 75% is', () {
    expect(make(3, 4).isBelowMinimum, false);
    expect(make(2, 4).isBelowMinimum, true);
  });

  test('no classes held -> no warning', () {
    expect(make(0, 0).isBelowMinimum, false);
    expect(make(0, 0).percentage, 0);
  });

  test('classes needed in a row to reach 75%', () {
    // 6 of 10 = 60%. After 6 more: 12 of 16 = 75%.
    expect(make(6, 10).classesNeededFor75, 6);
    expect(make(3, 4).classesNeededFor75, 0);
  });
}
