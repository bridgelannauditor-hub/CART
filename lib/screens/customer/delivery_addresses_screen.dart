import 'package:flutter/material.dart';

import '../../constants/app_colors.dart';
import '../../database/database_helper.dart';
import '../../models/address_model.dart';
import '../../services/session_service.dart';
import 'add_edit_address_screen.dart';

/// Lists the customer's saved delivery addresses, letting them add,
/// edit, delete, or change which one is the default.
class DeliveryAddressesScreen extends StatefulWidget {
  const DeliveryAddressesScreen({super.key});

  @override
  State<DeliveryAddressesScreen> createState() =>
      _DeliveryAddressesScreenState();
}

class _DeliveryAddressesScreenState extends State<DeliveryAddressesScreen> {
  List<AddressModel> _addresses = [];
  bool _isLoading = true;

  int? get _userId => SessionService.userId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final userId = _userId;
    if (userId == null) {
      setState(() => _isLoading = false);
      return;
    }

    setState(() => _isLoading = true);

    final rows = await DatabaseHelper.instance.getAddressesForUser(userId);

    if (!mounted) return;

    setState(() {
      _addresses = rows.map((e) => AddressModel.fromMap(e)).toList();
      _isLoading = false;
    });
  }

  Future<void> _openAddEdit({AddressModel? address}) async {
    final userId = _userId;
    if (userId == null) return;

    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => AddEditAddressScreen(userId: userId, address: address),
      ),
    );

    if (result == true) _load();
  }

  Future<void> _setDefault(AddressModel address) async {
    final userId = _userId;
    if (userId == null || address.id == null) return;

    await DatabaseHelper.instance.setDefaultAddress(userId, address.id!);
    _load();
  }

  Future<void> _delete(AddressModel address) async {
    final userId = _userId;
    if (userId == null || address.id == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text("Remove this address?"),
        content: Text(
          "\"${address.label}\" — ${address.shortAddress} will be removed "
          "from your saved addresses.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text("Remove"),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    await DatabaseHelper.instance.deleteAddress(userId, address.id!);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(
          "Delivery Addresses",
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        centerTitle: true,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openAddEdit(),
        backgroundColor: AppColors.primary,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text(
          "Add Address",
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
      ),
      body: SafeArea(
        child: _isLoading
            ? const Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              )
            : _addresses.isEmpty
            ? _EmptyState(onAdd: () => _openAddEdit())
            : RefreshIndicator(
                color: AppColors.primary,
                onRefresh: _load,
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 90),
                  itemCount: _addresses.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final address = _addresses[index];
                    return _AddressCard(
                      address: address,
                      onEdit: () => _openAddEdit(address: address),
                      onDelete: () => _delete(address),
                      onSetDefault: () => _setDefault(address),
                    );
                  },
                ),
              ),
      ),
    );
  }
}

class _AddressCard extends StatelessWidget {
  final AddressModel address;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onSetDefault;

  const _AddressCard({
    required this.address,
    required this.onEdit,
    required this.onDelete,
    required this.onSetDefault,
  });

  IconData get _labelIcon {
    switch (address.label) {
      case "Work":
        return Icons.work_outline_rounded;
      case "Other":
        return Icons.place_outlined;
      default:
        return Icons.home_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: address.isDefault
            ? Border.all(color: AppColors.primary, width: 1.4)
            : null,
        boxShadow: [
          BoxShadow(
            color: AppColors.dark.withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(_labelIcon, size: 17, color: AppColors.primary),
              ),
              const SizedBox(width: 10),
              Text(
                address.label,
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              if (address.isDefault) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.secondary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    "DEFAULT",
                    style: TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w800,
                      color: AppColors.secondary,
                      letterSpacing: 0.4,
                    ),
                  ),
                ),
              ],
              const Spacer(),
              PopupMenuButton<String>(
                icon: const Icon(
                  Icons.more_vert,
                  color: AppColors.textSecondary,
                  size: 20,
                ),
                onSelected: (value) {
                  if (value == "edit") onEdit();
                  if (value == "delete") onDelete();
                  if (value == "default") onSetDefault();
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(value: "edit", child: Text("Edit")),
                  if (!address.isDefault)
                    const PopupMenuItem(
                      value: "default",
                      child: Text("Set as default"),
                    ),
                  const PopupMenuItem(
                    value: "delete",
                    child: Text(
                      "Delete",
                      style: TextStyle(color: AppColors.error),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            "${address.fullName} · ${address.phone}",
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            address.shortAddress,
            style: const TextStyle(
              fontSize: 12.5,
              color: AppColors.textSecondary,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onAdd;

  const _EmptyState({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 84,
              height: 84,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.primary.withValues(alpha: 0.08),
              ),
              child: const Icon(
                Icons.location_on_outlined,
                size: 36,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              "No saved addresses yet",
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              "Add a delivery address to check out faster next time.",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 20),
            TextButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add, color: AppColors.primary),
              label: const Text(
                "Add Address",
                style: TextStyle(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
