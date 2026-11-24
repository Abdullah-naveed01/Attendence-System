import 'package:flutter_test/flutter_test.dart';

import 'package:smart_attendance/core/date_format.dart';
import 'package:smart_attendance/models/announcement.dart';
import 'package:smart_attendance/services/announcement_service.dart';

Announcement make(DateTime created) => Announcement(
      id: created.toIso8601String(),
      courseId: 'c1',
      courseCode: 'CS-301',
      courseName: 'Mobile App Development',
      title: 'Quiz',
      message: 'Quiz on Monday',
      teacherName: 'Ashfaq Ahmed',
      createdAt: created,
      expiresAt: created.add(const Duration(days: 7)),
    );

void main() {
  final posted = DateTime.utc(2026, 11, 24, 5, 0);

  test('"Expires in X days" text', () {
    final a = make(posted);
    expect(a.expiresText(posted), 'Expires in 7 days');
    expect(a.expiresText(posted.add(const Duration(days: 6))), 'Expires in 1 day');
    expect(a.expiresText(posted.add(const Duration(days: 6, hours: 12))),
        'Expires today');
    expect(a.expiresText(posted.add(const Duration(days: 7))), 'Expired');
  });

  test('badge counts only announcements after the last visit', () {
    final list = [
      make(posted),
      make(posted.add(const Duration(hours: 2))),
      make(posted.add(const Duration(hours: 5))),
    ];
    expect(AnnouncementService.countNew(list, null), 3); // never opened
    expect(
        AnnouncementService.countNew(
            list, posted.add(const Duration(hours: 3))),
        1);
  });

  test('date and time are shown in Pakistan time', () {
    // 05:00 UTC = 10:00 AM in Pakistan
    expect(formatPakistanDateTime(posted), 'Tue, 24 Nov 2026, 10:00 AM');
  });
}
