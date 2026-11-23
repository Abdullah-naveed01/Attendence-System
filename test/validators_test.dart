import 'package:flutter_test/flutter_test.dart';

import 'package:smart_attendance/core/validators.dart';

void main() {
  test('email format', () {
    expect(validateEmail('ashfaq@test.com'), isNull);
    expect(validateEmail(' riaz@uni.edu.pk '), isNull);
    expect(validateEmail('ashfaq'), isNotNull);
    expect(validateEmail('ashfaq@test'), isNotNull);
    expect(validateEmail(''), isNotNull);
  });

  test('password at least 8 characters', () {
    expect(validatePassword('Test@123'), isNull); // 8 characters
    expect(validatePassword('Test@12'), isNotNull); // 7 characters
    expect(validatePassword(null), isNotNull);
  });

  test('confirm password must match', () {
    expect(validateConfirmPassword('Test@1234', 'Test@1234'), isNull);
    expect(validateConfirmPassword('Test@1235', 'Test@1234'), isNotNull);
    expect(validateConfirmPassword('', 'Test@1234'), isNotNull);
  });

  test('course codes are compared in capital letters', () {
    expect(normalizeCourseCode(' cs-401 '), 'CS-401');
  });
}
