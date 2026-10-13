class SellerVerificationModel {
  final String sellerType;
  final String birthDate;
  final String address;
  final String identityDocumentType;
  final String payoutMethod;
  final String payoutAccountName;
  final String? organizationName;
  final String? businessRegistrationNumber;
  final String? schoolEmail;
  final String? credentialExpiry;
  final String? businessType;
  final String? businessTaxId;
  final String? businessAddress;
  final String? representativeRole;
  final bool identityCaptureCompleted;
  final bool faceCaptureCompleted;
  final String status;
  final String level;
  final int listingLimit;
  final String? submittedAt;
  final bool isVerifiedSeller;
  final int sellerTier;
  final bool schoolEmailVerified;
  final String? verificationExpiry;
  final double trustScore;

  const SellerVerificationModel({
    required this.sellerType,
    required this.birthDate,
    required this.address,
    required this.identityDocumentType,
    required this.payoutMethod,
    required this.payoutAccountName,
    this.organizationName,
    this.businessRegistrationNumber,
    this.schoolEmail,
    this.credentialExpiry,
    this.businessType,
    this.businessTaxId,
    this.businessAddress,
    this.representativeRole,
    this.identityCaptureCompleted = false,
    this.faceCaptureCompleted = false,
    this.status = 'under_review',
    this.level = 'registered',
    this.listingLimit = 5,
    this.submittedAt,
    this.isVerifiedSeller = false,
    this.sellerTier = 1,
    this.schoolEmailVerified = false,
    this.verificationExpiry,
    this.trustScore = 0,
  });

  /// Full application payload sent only to the trusted profile function.
  Map<String, dynamic> toApplicationMap() {
    return {
      'sellerType': sellerType,
      'birthDate': birthDate,
      'address': address,
      'identityDocumentType': identityDocumentType,
      'payoutMethod': payoutMethod,
      'payoutAccountName': payoutAccountName,
      'organizationName': organizationName,
      'businessRegistrationNumber': businessRegistrationNumber,
      'schoolEmail': schoolEmail,
      'credentialExpiry': credentialExpiry,
      'businessType': businessType,
      'businessTaxId': businessTaxId,
      'businessAddress': businessAddress,
      'representativeRole': representativeRole,
      'identityCaptureCompleted': identityCaptureCompleted,
      'faceCaptureCompleted': faceCaptureCompleted,
    };
  }

  /// Non-sensitive summary that is safe to keep on the public seller profile.
  Map<String, dynamic> toPublicMap() {
    return {
      'sellerType': sellerType,
      'status': status,
      'level': level,
      'listingLimit': listingLimit,
      'submittedAt': submittedAt,
      'isVerifiedSeller': isVerifiedSeller,
      'sellerTier': sellerTier,
      'schoolEmailVerified': schoolEmailVerified,
      'verificationExpiry': verificationExpiry,
      'trustScore': trustScore,
    };
  }

  factory SellerVerificationModel.fromFirestoreMap(Map<String, dynamic> map) {
    return SellerVerificationModel(
      sellerType: map['sellerType'] ?? 'individual',
      birthDate: map['birthDate'] ?? '',
      address: map['address'] ?? '',
      identityDocumentType: map['identityDocumentType'] ?? '',
      payoutMethod: map['payoutMethod'] ?? '',
      payoutAccountName: map['payoutAccountName'] ?? '',
      organizationName: map['organizationName'],
      businessRegistrationNumber: map['businessRegistrationNumber'],
      schoolEmail: map['schoolEmail'],
      credentialExpiry: map['credentialExpiry'],
      businessType: map['businessType'],
      businessTaxId: map['businessTaxId'],
      businessAddress: map['businessAddress'],
      representativeRole: map['representativeRole'],
      identityCaptureCompleted:
          map['identityCaptureCompleted'] as bool? ?? false,
      faceCaptureCompleted: map['faceCaptureCompleted'] as bool? ?? false,
      status: map['status'] ?? 'under_review',
      level: map['level'] ?? 'registered',
      listingLimit: (map['listingLimit'] as num?)?.toInt() ?? 5,
      submittedAt: map['submittedAt'],
      isVerifiedSeller: map['isVerifiedSeller'] as bool? ?? false,
      sellerTier: (map['sellerTier'] as num?)?.toInt() ?? 1,
      schoolEmailVerified: map['schoolEmailVerified'] as bool? ?? false,
      verificationExpiry: map['verificationExpiry'] as String?,
      trustScore: (map['trustScore'] as num?)?.toDouble() ?? 0,
    );
  }
}
