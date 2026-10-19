/// Where an applicant is in the six-step Seller onboarding flow.
///
/// Built from `public.get_my_seller_onboarding()`. The server decides every
/// transition; this model only reads the result for display.
enum SellerOnboardingStep {
  verifyAccount,
  apply,
  verifySchoolEmail,
  verifyIdentity,
  identityUnderReview,
  setUpShop,
  awaitingApproval,
  approved,
  rejected,
  appealed,
  suspended,
}

/// Plain-language application states shown to customers.
///
/// These labels deliberately describe progress without granting permissions.
/// Seller access still comes only from the server-owned seller account state.
enum SellerApplicationStatus {
  notApplied('Not applied'),
  pendingVerification('Pending verification'),
  verificationInProgress('Verification in progress'),
  verificationFailed('Verification failed'),
  shopSetupRequired('Shop setup required'),
  pendingAdminApproval('Pending admin approval'),
  approved('Approved'),
  rejected('Rejected'),
  requiresResubmission('Requires resubmission'),
  suspended('Suspended');

  final String label;

  const SellerApplicationStatus(this.label);
}

class SellerApplicationState {
  final String status;
  final int revision;
  final String sellerType;
  final String? termsVersion;
  final String? schoolEmail;
  final bool schoolEmailVerified;
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
    required this.schoolEmail,
    required this.schoolEmailVerified,
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
      schoolEmail: map['schoolEmail'] as String?,
      schoolEmailVerified: map['schoolEmailVerified'] as bool? ?? false,
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

  SellerApplicationStatus get applicationStatus {
    if (sellerAccountStatus == 'active') {
      return SellerApplicationStatus.approved;
    }
    if (sellerAccountStatus == 'suspended' ||
        sellerAccountStatus == 'revoked') {
      return SellerApplicationStatus.suspended;
    }

    final app = application;
    if (app == null) return SellerApplicationStatus.notApplied;

    if (app.status == 'approved') return SellerApplicationStatus.approved;
    if (app.status == 'rejected') {
      return app.identityStatus == 'rejected'
          ? SellerApplicationStatus.verificationFailed
          : SellerApplicationStatus.rejected;
    }
    if (app.termsVersion != currentTermsVersion ||
        app.identityStatus == 'needs_retry' ||
        app.shopStatus == 'changes_requested') {
      return SellerApplicationStatus.requiresResubmission;
    }
    if (app.identityStatus == 'pending' ||
        app.identityStatus == 'under_review') {
      return SellerApplicationStatus.verificationInProgress;
    }
    if (app.identityStatus != 'verified') {
      return SellerApplicationStatus.pendingVerification;
    }
    if (app.shopStatus == 'submitted' || app.status == 'appealed') {
      return SellerApplicationStatus.pendingAdminApproval;
    }
    return SellerApplicationStatus.shopSetupRequired;
  }

  String get applicationStatusGuidance {
    switch (applicationStatus) {
      case SellerApplicationStatus.notApplied:
        return 'Review the requirements and submit an application when you are ready.';
      case SellerApplicationStatus.pendingVerification:
        return 'Complete the required email and identity verification steps.';
      case SellerApplicationStatus.verificationInProgress:
        return 'Your identity verification is being processed. Pull down to refresh.';
      case SellerApplicationStatus.verificationFailed:
        return 'Review the reason below and use the available retry or appeal option.';
      case SellerApplicationStatus.shopSetupRequired:
        return 'Identity verification passed. Complete and submit your shop profile.';
      case SellerApplicationStatus.pendingAdminApproval:
        return 'Your completed application is waiting for an authorized administrator.';
      case SellerApplicationStatus.approved:
        return 'Seller permissions are active and the Seller dashboard is available.';
      case SellerApplicationStatus.rejected:
        return 'Review the decision and follow the correction or appeal instructions below.';
      case SellerApplicationStatus.requiresResubmission:
        return 'Additional information or another verification attempt is required.';
      case SellerApplicationStatus.suspended:
        return 'Seller access is unavailable. Your customer account remains active.';
    }
  }

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
    if (app.sellerType == 'student' && !app.schoolEmailVerified) {
      return SellerOnboardingStep.verifySchoolEmail;
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
    case 'details_mismatch':
      return 'The name, birthdate or address you entered does not match your '
          'ID. Request a review and double-check them against your ID.';
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
