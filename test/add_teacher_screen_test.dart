import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:smart_attendance/screens/admin/add_teacher_screen.dart';

// Reads the obscureText setting of the TextField under a label.
bool isHidden(WidgetTester tester, String label) {
  final field = tester.widget<TextField>(
    find.descendant(
      of: find.widgetWithText(TextFormField, label),
      matching: find.byType(TextField),
    ),
  );
  return field.obscureText;
}

void main() {
  testWidgets('eye button shows and hides both passwords', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: AddTeacherScreen(allCourses: [], teachers: []),
    ));

    const password = 'Password (at least 8 characters)';
    const confirm = 'Confirm password';

    // Hidden at the start
    expect(isHidden(tester, password), true);
    expect(isHidden(tester, confirm), true);

    // Tap the eye -> both visible
    await tester.tap(find.byIcon(Icons.visibility));
    await tester.pump();
    expect(isHidden(tester, password), false);
    expect(isHidden(tester, confirm), false);

    // Tap again -> both hidden
    await tester.tap(find.byIcon(Icons.visibility_off));
    await tester.pump();
    expect(isHidden(tester, password), true);
    expect(isHidden(tester, confirm), true);
  });
}
