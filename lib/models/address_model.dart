import '../database/tables.dart';

class AddressModel {
  final int? id;
  final int userId;
  final String fullName;
  final String phone;
  final String label;
  final String line1;
  final String? line2;
  final String city;
  final String province;
  final String? postalCode;
  final bool isDefault;

  const AddressModel({
    this.id,
    required this.userId,
    required this.fullName,
    required this.phone,
    this.label = "Home",
    required this.line1,
    this.line2,
    required this.city,
    required this.province,
    this.postalCode,
    this.isDefault = false,
  });

  /// One-line summary used in list rows / previews.
  String get shortAddress {
    final parts = [
      line1,
      if (line2 != null && line2!.trim().isNotEmpty) line2,
      city,
      province,
      if (postalCode != null && postalCode!.trim().isNotEmpty) postalCode,
    ];
    return parts.join(", ");
  }

  Map<String, dynamic> toMap() {
    return {
      DBTables.id: id,
      DBTables.addressUserId: userId,
      DBTables.addressFullName: fullName,
      DBTables.addressPhone: phone,
      DBTables.addressLabel: label,
      DBTables.addressLine1: line1,
      DBTables.addressLine2: line2,
      DBTables.addressCity: city,
      DBTables.addressProvince: province,
      DBTables.addressPostalCode: postalCode,
      DBTables.addressIsDefault: isDefault ? 1 : 0,
      DBTables.createdAt: DateTime.now().toIso8601String(),
    };
  }

  factory AddressModel.fromMap(Map<String, dynamic> map) {
    return AddressModel(
      id: map[DBTables.id],
      userId: map[DBTables.addressUserId],
      fullName: map[DBTables.addressFullName] ?? '',
      phone: map[DBTables.addressPhone] ?? '',
      label: map[DBTables.addressLabel] ?? 'Home',
      line1: map[DBTables.addressLine1] ?? '',
      line2: map[DBTables.addressLine2],
      city: map[DBTables.addressCity] ?? '',
      province: map[DBTables.addressProvince] ?? '',
      postalCode: map[DBTables.addressPostalCode],
      isDefault: ((map[DBTables.addressIsDefault] as num?) ?? 0) != 0,
    );
  }

  AddressModel copyWith({
    int? id,
    int? userId,
    String? fullName,
    String? phone,
    String? label,
    String? line1,
    String? line2,
    String? city,
    String? province,
    String? postalCode,
    bool? isDefault,
  }) {
    return AddressModel(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      fullName: fullName ?? this.fullName,
      phone: phone ?? this.phone,
      label: label ?? this.label,
      line1: line1 ?? this.line1,
      line2: line2 ?? this.line2,
      city: city ?? this.city,
      province: province ?? this.province,
      postalCode: postalCode ?? this.postalCode,
      isDefault: isDefault ?? this.isDefault,
    );
  }
}
