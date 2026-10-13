import '../database/tables.dart';
import 'seller_verification_model.dart';

class UserModel {
  final int? id;

  // Firebase Auth uid for this user (null until the user has been created
  // in Firebase Auth). Doc ID in the `users` Firestore collection.
  final String? firebaseUid;

  final String firstName;
  final String lastName;
  final String email;
  final String? phone;
  final String accountType;
  final String? gender;
  final bool onboardingCompleted;

  // ==========================
  // SHOP NAME
  // ==========================

  final String? shopName;

  // ==========================
  // SHOP APPEARANCE
  // ==========================

  final String? coverImage;
  final String? profileImage;
  final bool isLive;

  final SellerVerificationModel? sellerVerification;

  /// Server-controlled public trust fields. Verification evidence is stored
  /// separately and is never exposed through this model.
  final bool isVerifiedSeller;
  final int sellerTier;
  final bool schoolEmailVerified;
  final String? verificationExpiry;
  final double trustScore;

  final String createdAt;

  bool get hasCurrentSellerVerification {
    if (!isVerifiedSeller) return false;
    if (verificationExpiry == null) return true;
    final expiry = DateTime.tryParse(verificationExpiry!);
    if (expiry == null) return false;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return !expiry.isBefore(today);
  }

  const UserModel({
    this.id,
    this.firebaseUid,
    required this.firstName,
    required this.lastName,
    required this.email,
    this.phone,
    required this.accountType,
    this.gender,
    this.onboardingCompleted = true,
    this.shopName,
    this.coverImage,
    this.profileImage,
    this.isLive = false,
    this.sellerVerification,
    this.isVerifiedSeller = false,
    this.sellerTier = 1,
    this.schoolEmailVerified = false,
    this.verificationExpiry,
    this.trustScore = 0,
    required this.createdAt,
  });

  // ==========================
  // TO MAP
  // ==========================

  Map<String, dynamic> toMap() {
    return {
      DBTables.id: id,
      DBTables.firstName: firstName,
      DBTables.lastName: lastName,
      DBTables.email: email,
      DBTables.phone: phone,
      DBTables.accountType: accountType,
      DBTables.shopName: shopName,
      DBTables.coverImage: coverImage,
      DBTables.profileImage: profileImage,
      DBTables.isLive: isLive ? 1 : 0,
      DBTables.createdAt: createdAt,
    };
  }

  // ==========================
  // FROM MAP
  // ==========================

  factory UserModel.fromMap(Map<String, dynamic> map) {
    return UserModel(
      id: map[DBTables.id],

      firstName: map[DBTables.firstName],

      lastName: map[DBTables.lastName],

      email: map[DBTables.email],

      phone: map[DBTables.phone],

      accountType: map[DBTables.accountType],

      shopName: map[DBTables.shopName],

      coverImage: map[DBTables.coverImage],

      profileImage: map[DBTables.profileImage],

      isLive: ((map[DBTables.isLive] as num?) ?? 0) != 0,

      createdAt: map[DBTables.createdAt],
    );
  }

  // ==========================
  // FIRESTORE MAP (source of truth going forward)
  // ==========================

  Map<String, dynamic> toFirestoreMap() {
    return {
      'id': id,
      'firebaseUid': firebaseUid,
      'firstName': firstName,
      'lastName': lastName,
      'email': email,
      'phone': phone,
      'accountType': accountType,
      'gender': gender,
      'onboardingCompleted': onboardingCompleted,
      'shopName': shopName,
      'coverImage': coverImage,
      'profileImage': profileImage,
      'isLive': isLive,
      if (sellerVerification != null)
        'sellerVerification': sellerVerification!.toPublicMap(),
      'createdAt': createdAt,
      // Firebase Auth is the only credential store. UserModel contains no
      // password field, so neither local nor Firestore maps can persist one.
    };
  }

  factory UserModel.fromFirestoreMap(Map<String, dynamic> map) {
    return UserModel(
      id: map['id'] as int?,
      firebaseUid: map['firebaseUid'] as String?,
      firstName: map['firstName'] ?? '',
      lastName: map['lastName'] ?? '',
      email: map['email'] ?? '',
      phone: map['phone'],
      accountType: map['accountType'] ?? 'Customer',
      gender: map['gender'] as String?,
      onboardingCompleted: map['onboardingCompleted'] as bool? ?? true,
      shopName: map['shopName'],
      coverImage: map['coverImage'],
      profileImage: map['profileImage'],
      isLive: (map['isLive'] as bool?) ?? false,
      sellerVerification: map['sellerVerification'] is Map
          ? SellerVerificationModel.fromFirestoreMap(
              Map<String, dynamic>.from(map['sellerVerification'] as Map),
            )
          : null,
      isVerifiedSeller: map['isVerifiedSeller'] as bool? ?? false,
      sellerTier: (map['sellerTier'] as num?)?.toInt() ?? 1,
      schoolEmailVerified: map['schoolEmailVerified'] as bool? ?? false,
      verificationExpiry: map['verificationExpiry'] as String?,
      trustScore: (map['trustScore'] as num?)?.toDouble() ?? 0,
      createdAt: map['createdAt'] ?? DateTime.now().toIso8601String(),
    );
  }

  Map<String, dynamic> toSupabaseMap() {
    return {
      'first_name': firstName,
      'last_name': lastName,
      'email': email,
      'phone': phone,
      'account_type': accountType,
      'gender': gender,
      'onboarding_completed': onboardingCompleted,
      'shop_name': shopName,
      'cover_image': coverImage,
      'profile_image': profileImage,
      'is_live': isLive,
      'seller_verification': sellerVerification?.toPublicMap(),
    };
  }

  factory UserModel.fromSupabaseMap(Map<String, dynamic> map) {
    final verificationMap = map['seller_verification'] is Map
        ? Map<String, dynamic>.from(map['seller_verification'] as Map)
        : null;
    return UserModel(
      id: (map['id'] as num?)?.toInt(),
      firebaseUid: map['legacy_firebase_uid'] as String?,
      firstName: map['first_name'] as String? ?? '',
      lastName: map['last_name'] as String? ?? '',
      email: map['email'] as String? ?? '',
      phone: map['phone'] as String?,
      accountType: map['account_type'] as String? ?? 'Customer',
      gender: map['gender'] as String?,
      onboardingCompleted: map['onboarding_completed'] as bool? ?? true,
      shopName: map['shop_name'] as String?,
      coverImage: map['cover_image'] as String?,
      profileImage: map['profile_image'] as String?,
      isLive: map['is_live'] as bool? ?? false,
      sellerVerification: verificationMap != null
          ? SellerVerificationModel.fromFirestoreMap(verificationMap)
          : null,
      isVerifiedSeller:
          map['is_verified_seller'] as bool? ??
          (verificationMap?['isVerifiedSeller'] as bool? ?? false),
      sellerTier:
          (map['seller_tier'] as num?)?.toInt() ??
          (verificationMap?['sellerTier'] as num?)?.toInt() ??
          1,
      schoolEmailVerified: map['school_email_verified'] as bool? ?? false,
      verificationExpiry: map['verification_expiry']?.toString(),
      trustScore: (map['trust_score'] as num?)?.toDouble() ?? 0,
      createdAt:
          map['created_at'] as String? ?? DateTime.now().toIso8601String(),
    );
  }

  // ==========================
  // COPY WITH
  // ==========================

  UserModel copyWith({
    int? id,
    String? firebaseUid,
    String? firstName,
    String? lastName,
    String? email,
    String? phone,
    String? accountType,
    String? gender,
    bool? onboardingCompleted,
    String? shopName,
    String? coverImage,
    String? profileImage,
    bool? isLive,
    SellerVerificationModel? sellerVerification,
    bool? isVerifiedSeller,
    int? sellerTier,
    bool? schoolEmailVerified,
    String? verificationExpiry,
    double? trustScore,
    String? createdAt,
  }) {
    return UserModel(
      id: id ?? this.id,
      firebaseUid: firebaseUid ?? this.firebaseUid,

      firstName: firstName ?? this.firstName,

      lastName: lastName ?? this.lastName,

      email: email ?? this.email,

      phone: phone ?? this.phone,

      accountType: accountType ?? this.accountType,
      gender: gender ?? this.gender,
      onboardingCompleted: onboardingCompleted ?? this.onboardingCompleted,

      shopName: shopName ?? this.shopName,

      coverImage: coverImage ?? this.coverImage,

      profileImage: profileImage ?? this.profileImage,

      isLive: isLive ?? this.isLive,

      sellerVerification: sellerVerification ?? this.sellerVerification,

      isVerifiedSeller: isVerifiedSeller ?? this.isVerifiedSeller,

      sellerTier: sellerTier ?? this.sellerTier,

      schoolEmailVerified: schoolEmailVerified ?? this.schoolEmailVerified,

      verificationExpiry: verificationExpiry ?? this.verificationExpiry,

      trustScore: trustScore ?? this.trustScore,

      createdAt: createdAt ?? this.createdAt,
    );
  }
}
