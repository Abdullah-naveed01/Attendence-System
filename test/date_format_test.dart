import 'package:flutter_test/flutter_test.dart';

import 'package:smart_attendance/core/date_format.dart';

void main() {
  test('times are shown in Pakistan time (UTC+5)', () {
    // 17:32 UTC = 22:32 in Pakistan
    expect(formatPakistanTime(DateTime.utc(2026, 11, 23, 17, 32)), '10:32 PM');
    // 03:30 UTC = 08:30 in Pakistan
    expect(formatPakistanTime(DateTime.utc(2026, 11, 23, 3, 30)), '8:30 AM');
  });
}
