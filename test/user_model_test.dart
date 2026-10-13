import 'package:craft_of_love/models/user_model.dart';
import 'package:craft_of_love/models/seller_verification_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('local user maps never contain credentials', () {
    final user = UserModel(
      id: 42,
      firstName: 'Test',
      lastName: 'Customer',
      email: 'test@example.com',
      accountType: 'Customer',
      createdAt: '2026-10-07T00:00:00.000Z',
    );

    final localMap = user.toMap();
    expect(localMap.containsKey('password'), isFalse);

    final restored = UserModel.fromMap(localMap);
    expect(restored.id, 42);
    expect(restored.email, 'test@example.com');
    expect(restored.accountType, 'Customer');
  });

  test('Firestore user maps never contain credentials', () {
    final user = UserModel(
      id: 43,
      firebaseUid: 'firebase-user',
      firstName: 'Test',
      lastName: 'Seller',
      email: 'seller@example.com',
      accountType: 'Seller',
      shopName: 'Secure Shop',
      createdAt: '2026-10-07T00:00:00.000Z',
    );

    expect(user.toFirestoreMap().containsKey('password'), isFalse);
  });

  test('public seller profiles omit private verification details', () {
    final user = UserModel(
      id: 44,
      firebaseUid: 'student-seller',
      firstName: 'Student',
      lastName: 'Seller',
      email: 'student@example.com',
      accountType: 'Seller',
      shopName: 'Campus Crafts',
      sellerVerification: const SellerVerificationModel(
        sellerType: 'student',
        birthDate: '2000-01-01',
        address: '123 Private Street',
        identityDocumentType: 'national_id',
        payoutMethod: 'gcash',
        payoutAccountName: 'Student Seller',
      ),
      createdAt: '2026-10-08T00:00:00.000Z',
    );

    final summary = user.toFirestoreMap()['sellerVerification'] as Map;
    expect(summary['status'], 'under_review');
    expect(summary['listingLimit'], 5);
    expect(summary.containsKey('birthDate'), isFalse);
    expect(summary.containsKey('address'), isFalse);
    expect(summary.containsKey('payoutAccountName'), isFalse);
  });

  test('application payload cannot claim trusted server fields', () {
    const verification = SellerVerificationModel(
      sellerType: 'student',
      birthDate: '2000-01-01',
      address: '123 Private Street',
      identityDocumentType: 'student_id_cor',
      payoutMethod: 'gcash',
      payoutAccountName: 'Student Seller',
      schoolEmail: 'student@university.edu.ph',
      credentialExpiry: '2027-06-01',
      status: 'approved',
      isVerifiedSeller: true,
      sellerTier: 3,
      trustScore: 100,
    );

    final payload = verification.toApplicationMap();
    expect(payload['schoolEmail'], 'student@university.edu.ph');
    expect(payload['credentialExpiry'], '2027-06-01');
    expect(payload.containsKey('status'), isFalse);
    expect(payload.containsKey('isVerifiedSeller'), isFalse);
    expect(payload.containsKey('sellerTier'), isFalse);
    expect(payload.containsKey('trustScore'), isFalse);
  });

  test('Supabase trust fields populate the public user model', () {
    final user = UserModel.fromSupabaseMap({
      'id': 45,
      'first_name': 'Verified',
      'last_name': 'Crafter',
      'email': 'seller@example.com',
      'account_type': 'Seller',
      'is_verified_seller': true,
      'seller_tier': 2,
      'school_email_verified': false,
      'verification_expiry': '2099-06-01',
      'trust_score': 96.5,
      'created_at': '2026-10-11T00:00:00.000Z',
    });

    expect(user.hasCurrentSellerVerification, isTrue);
    expect(user.sellerTier, 2);
    expect(user.trustScore, 96.5);
  });
}
