import 'package:craft_of_love/utils/validators.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('school email accepts Philippine educational domains', () {
    expect(Validators.schoolEmail('student@university.edu.ph'), isNull);
  });

  test('school email rejects public email domains', () {
    expect(Validators.schoolEmail('student@gmail.com'), isNotNull);
  });
}
