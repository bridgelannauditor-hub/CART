import 'package:craft_of_love/models/seller_onboarding_model.dart';
import 'package:flutter_test/flutter_test.dart';

SellerOnboardingState stateWith({
  bool accountVerified = true,
  String? sellerAccountStatus,
  Map<String, dynamic>? application,
}) {
  return SellerOnboardingState.fromMap({
    'accountVerified': accountVerified,
    'currentTermsVersion': '2026-10',
    'maxIdentityAttempts': 3,
    'maxAppeals': 2,
    'sellerAccountStatus': sellerAccountStatus,
    'application': application == null
        ? null
        : {'status': 'under_review', 'termsVersion': '2026-10', ...application},
  });
}

void main() {
  test('unverified accounts must confirm their email first', () {
    expect(
      stateWith(accountVerified: false).step,
      SellerOnboardingStep.verifyAccount,
    );
  });

  test('verified Buyers without an application start by applying', () {
    expect(stateWith().step, SellerOnboardingStep.apply);
  });

  test('outdated terms send the applicant back to the application', () {
    expect(
      stateWith(application: {'termsVersion': '2025-01'}).step,
      SellerOnboardingStep.apply,
    );
  });

  test('each identity outcome maps to its own step', () {
    expect(
      stateWith(application: {'identityStatus': 'not_started'}).step,
      SellerOnboardingStep.verifyIdentity,
    );
    expect(
      stateWith(application: {'identityStatus': 'needs_retry'}).step,
      SellerOnboardingStep.verifyIdentity,
    );
    expect(
      stateWith(application: {'identityStatus': 'under_review'}).step,
      SellerOnboardingStep.identityUnderReview,
    );
    expect(
      stateWith(application: {'identityStatus': 'verified'}).step,
      SellerOnboardingStep.setUpShop,
    );
    expect(
      stateWith(
        application: {'status': 'rejected', 'identityStatus': 'rejected'},
      ).step,
      SellerOnboardingStep.rejected,
    );
  });

  test('a submitted shop waits for final approval', () {
    expect(
      stateWith(
        application: {'identityStatus': 'verified', 'shopStatus': 'submitted'},
      ).step,
      SellerOnboardingStep.awaitingApproval,
    );
    expect(
      stateWith(
        application: {
          'identityStatus': 'verified',
          'shopStatus': 'changes_requested',
        },
      ).step,
      SellerOnboardingStep.setUpShop,
    );
  });

  test('only an active seller account counts as approved', () {
    expect(
      stateWith(
        sellerAccountStatus: 'inactive',
        application: {'identityStatus': 'verified', 'shopStatus': 'submitted'},
      ).step,
      SellerOnboardingStep.awaitingApproval,
    );
    expect(
      stateWith(sellerAccountStatus: 'active').step,
      SellerOnboardingStep.approved,
    );
    expect(
      stateWith(sellerAccountStatus: 'suspended').step,
      SellerOnboardingStep.suspended,
    );
  });

  test('attempts left and appeal eligibility follow server limits', () {
    final retry = stateWith(
      application: {'identityStatus': 'needs_retry', 'identityAttempts': 2},
    );
    expect(retry.identityAttemptsLeft, 1);

    expect(
      stateWith(
        application: {'status': 'rejected', 'appealCount': 1},
      ).canAppeal,
      isTrue,
    );
    expect(
      stateWith(
        application: {'status': 'rejected', 'appealCount': 2},
      ).canAppeal,
      isFalse,
    );
  });

  test('unknown reason codes never expose raw provider text', () {
    expect(
      describeSellerReasonCode('provider_internal_score_0.42'),
      'Contact Cart support if you need more information.',
    );
  });
}
