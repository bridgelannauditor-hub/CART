/// Where an applicant is in the six-step Seller onboarding flow.
///
/// Built from `public.get_my_seller_onboarding()`. The server decides every
/// transition; this model only reads the result for display.
enum SellerOnboardingStep {
  verifyAccount,
  apply,
  verifyIdentity,
  identityUnderReview,
  setUpShop,
  awaitingApproval,
  approved,
  rejected,
  appealed,
  suspended,
}

class SellerApplicationState {
  final String status;
  final int revision;
  final String sellerType;
  final String? termsVersion;
  final String identityStatus;
  final int identityAttempts;
  final String? identityReasonCode;
  final String shopStatus;
  final String? shopName;
  final String? shopDescription;
  final String? shopCategory;
  final String? shopCity;
  final String? reviewReasonCode;
  final int appealCount;

  const SellerApplicationState({
    required this.status,
    required this.revision,
    required this.sellerType,
    required this.termsVersion,
    required this.identityStatus,
    required this.identityAttempts,
    required this.identityReasonCode,
    required this.shopStatus,
    required this.shopName,
    required this.shopDescription,
    required this.shopCategory,
    required this.shopCity,
    required this.reviewReasonCode,
    required this.appealCount,
  });

  factory SellerApplicationState.fromMap(Map<String, dynamic> map) {
    return SellerApplicationState(
      status: map['status'] as String? ?? 'under_review',
      revision: (map['revision'] as num?)?.toInt() ?? 1,
      sellerType: map['sellerType'] as String? ?? 'individual',
      termsVersion: map['termsVersion'] as String?,
      identityStatus: map['identityStatus'] as String? ?? 'not_started',
      identityAttempts: (map['identityAttempts'] as num?)?.toInt() ?? 0,
      identityReasonCode: map['identityReasonCode'] as String?,
      shopStatus: map['shopStatus'] as String? ?? 'not_started',
      shopName: map['shopName'] as String?,
      shopDescription: map['shopDescription'] as String?,
      shopCategory: map['shopCategory'] as String?,
      shopCity: map['shopCity'] as String?,
      reviewReasonCode: map['reviewReasonCode'] as String?,
      appealCount: (map['appealCount'] as num?)?.toInt() ?? 0,
    );
  }
}

class SellerOnboardingState {
  final bool accountVerified;
  final String currentTermsVersion;
  final int maxIdentityAttempts;
  final int maxAppeals;
  final String? sellerAccountStatus;
  final SellerApplicationState? application;

  const SellerOnboardingState({
    required this.accountVerified,
    required this.currentTermsVersion,
    required this.maxIdentityAttempts,
    required this.maxAppeals,
    required this.sellerAccountStatus,
    required this.application,
  });

  factory SellerOnboardingState.fromMap(Map<String, dynamic> map) {
    final application = map['application'];
    return SellerOnboardingState(
      accountVerified: map['accountVerified'] as bool? ?? false,
      currentTermsVersion: map['currentTermsVersion'] as String? ?? '',
      maxIdentityAttempts: (map['maxIdentityAttempts'] as num?)?.toInt() ?? 3,
      maxAppeals: (map['maxAppeals'] as num?)?.toInt() ?? 0,
      sellerAccountStatus: map['sellerAccountStatus'] as String?,
      application: application is Map
          ? SellerApplicationState.fromMap(
              Map<String, dynamic>.from(application),
            )
          : null,
    );
  }

  int get identityAttemptsLeft {
    final used = application?.identityAttempts ?? 0;
    return (maxIdentityAttempts - used).clamp(0, maxIdentityAttempts);
  }

  bool get canAppeal =>
      application?.status == 'rejected' &&
      (application?.appealCount ?? 0) < maxAppeals;

  SellerOnboardingStep get step {
    if (sellerAccountStatus == 'active') return SellerOnboardingStep.approved;
    if (sellerAccountStatus == 'suspended' ||
        sellerAccountStatus == 'revoked') {
      return SellerOnboardingStep.suspended;
    }
    if (!accountVerified) return SellerOnboardingStep.verifyAccount;
    final app = application;
    if (app == null) return SellerOnboardingStep.apply;

    switch (app.status) {
      case 'approved':
        return SellerOnboardingStep.approved;
      case 'suspended':
        return SellerOnboardingStep.suspended;
      case 'rejected':
        return SellerOnboardingStep.rejected;
      case 'appealed':
        return SellerOnboardingStep.appealed;
    }
    if (app.termsVersion != currentTermsVersion) {
      return SellerOnboardingStep.apply;
    }
    switch (app.identityStatus) {
      case 'verified':
        return app.shopStatus == 'submitted'
            ? SellerOnboardingStep.awaitingApproval
            : SellerOnboardingStep.setUpShop;
      case 'under_review':
        return SellerOnboardingStep.identityUnderReview;
      case 'rejected':
        return SellerOnboardingStep.rejected;
      default:
        return SellerOnboardingStep.verifyIdentity;
    }
  }
}

/// Applicant-facing explanations for server reason codes. Sensitive provider
/// details are never shown; unknown codes fall back to a generic message.
String describeSellerReasonCode(String? code) {
  switch (code) {
    case 'image_blurry':
    case 'image_unclear':
      return 'The ID photo was not clear enough. Retake it in good light, '
          'with all four corners visible.';
    case 'document_expired':
      return 'The ID appears to be expired. Use a valid, unexpired ID.';
    case 'document_unsupported':
      return 'This type of ID is not accepted. Choose another government ID.';
    case 'capture_failed':
    case 'session_interrupted':
    case 'provider_unavailable':
      return 'The verification session was interrupted. No details were '
          'lost; please try again.';
    case 'face_mismatch':
    case 'liveness_failed':
      return 'The selfie check could not be completed. Make sure your face '
          'is fully visible and well lit, then try again.';
    case 'prohibited_items':
      return 'Some items in the shop description are not allowed on Cart. '
          'Review the Seller policy and update your shop.';
    case 'shop_details_incomplete':
      return 'Some shop details are missing or unclear. Update your shop and '
          'submit it again.';
    case 'policy_violation':
      return 'The application does not meet the Seller policy.';
    default:
      return 'Contact Cart support if you need more information.';
  }
}
