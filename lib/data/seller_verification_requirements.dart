class SellerTypeRequirements {
  final String key;
  final String label;
  final String description;
  final List<String> requirements;
  final Map<String, String> identityDocuments;

  const SellerTypeRequirements({
    required this.key,
    required this.label,
    required this.description,
    required this.requirements,
    required this.identityDocuments,
  });
}

const sellerTypeRequirements = <String, SellerTypeRequirements>{
  'student': SellerTypeRequirements(
    key: 'student',
    label: 'Student seller',
    description: 'For currently enrolled students selling their own crafts.',
    requirements: [
      'Valid photo ID and live face check',
      'Current school name and school email',
      'Student credential expiry or current registration proof',
    ],
    identityDocuments: {
      'student_id': 'Student ID',
      'national_id': 'National ID',
      'passport': 'Passport',
      'drivers_license': "Driver's license",
      'postal_id': 'Postal ID',
    },
  ),
  'individual': SellerTypeRequirements(
    key: 'individual',
    label: 'Individual seller',
    description: 'For a person selling independently under their own name.',
    requirements: [
      'Government-issued photo ID and live face check',
      'Legal name, date of birth, and current home address',
      'Payout account held in the same legal name',
    ],
    identityDocuments: {
      'national_id': 'National ID',
      'passport': 'Passport',
      'drivers_license': "Driver's license",
      'postal_id': 'Postal ID',
      'umid': 'UMID',
      'prc_id': 'PRC ID',
    },
  ),
  'business': SellerTypeRequirements(
    key: 'business',
    label: 'Registered business',
    description:
        'For a registered sole proprietorship, partnership, or company.',
    requirements: [
      'Authorized representative ID and live face check',
      'DTI, SEC, or CDA registration details',
      'Registered address, tax ID, and representative role',
    ],
    identityDocuments: {
      'national_id': 'Representative National ID',
      'passport': 'Representative Passport',
      'drivers_license': "Representative Driver's license",
      'umid': 'Representative UMID',
      'prc_id': 'Representative PRC ID',
    },
  ),
};
