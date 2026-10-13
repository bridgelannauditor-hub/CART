import 'package:craft_of_love/data/seller_verification_requirements.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every seller type has accepted IDs and requirements', () {
    expect(sellerTypeRequirements.keys, {'student', 'individual', 'business'});

    for (final type in sellerTypeRequirements.values) {
      expect(type.identityDocuments, isNotEmpty);
      expect(type.requirements, isNotEmpty);
    }
  });

  test('student ID is only offered to student sellers', () {
    expect(
      sellerTypeRequirements['student']!.identityDocuments,
      contains('student_id'),
    );
    expect(
      sellerTypeRequirements['individual']!.identityDocuments,
      isNot(contains('student_id')),
    );
    expect(
      sellerTypeRequirements['business']!.identityDocuments,
      isNot(contains('student_id')),
    );
  });
}
