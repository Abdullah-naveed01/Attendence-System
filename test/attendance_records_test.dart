import 'package:flutter_test/flutter_test.dart';

import 'package:smart_attendance/core/csv.dart';
import 'package:smart_attendance/widgets/status_chip.dart';

void main() {
  test('CSV quotes every value and doubles quotes inside values', () {
    final csv = toCsv(
      ['Student', 'Status'],
      [
        ['Ali, Khan', 'Present'],
        ['Sara "S"', 'Absent'],
      ],
    );
    expect(
      csv,
      '"Student","Status"\n'
      '"Ali, Khan","Present"\n'
      '"Sara ""S""","Absent"',
    );
  });

  test('status labels', () {
    expect(statusLabel('present'), 'Present');
    expect(statusLabel('late'), 'Late');
    expect(statusLabel('excused'), 'Excused');
    expect(statusLabel('absent'), 'Absent');
    expect(statusLabel('in_progress'), 'In progress');
  });
}
