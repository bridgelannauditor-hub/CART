import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../constants/app_colors.dart';
import '../../database/database_helper.dart';
import '../../database/tables.dart';
import '../../services/session_service.dart';

/// Notification preferences for the signed-in account. Supabase is the
/// cross-device source of truth and sqflite keeps an offline mirror.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _isLoading = true;

  bool _pushEnabled = true;
  bool _emailEnabled = true;
  bool _orderUpdates = true;
  bool _promoOffers = true;

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

    final settings = await DatabaseHelper.instance.getUserSettings(userId);
    var pushEnabled =
        (settings[DBTables.settingsPushEnabled] as num? ?? 1) != 0;
    const emailEnabled = false;
    var orderUpdates =
        (settings[DBTables.settingsOrderUpdates] as num? ?? 1) != 0;
    var promoOffers =
        (settings[DBTables.settingsPromoOffers] as num? ?? 1) != 0;

    try {
      final profile = await Supabase.instance.client
          .from('profiles')
          .select('notification_preferences')
          .eq('id', userId)
          .maybeSingle();
      final preferences = profile?['notification_preferences'] as Map?;
      if (preferences != null) {
        pushEnabled = preferences['pushEnabled'] as bool? ?? pushEnabled;
        orderUpdates = preferences['orderUpdates'] as bool? ?? orderUpdates;
        promoOffers = preferences['promoOffers'] as bool? ?? promoOffers;
        await DatabaseHelper.instance.updateUserSettings(userId, {
          DBTables.settingsPushEnabled: pushEnabled ? 1 : 0,
          DBTables.settingsEmailEnabled: 0,
          DBTables.settingsOrderUpdates: orderUpdates ? 1 : 0,
          DBTables.settingsPromoOffers: promoOffers ? 1 : 0,
        });
      }
    } catch (_) {
      // The local mirror remains usable while offline.
    }

    if (!mounted) return;

    setState(() {
      _pushEnabled = pushEnabled;
      _emailEnabled = emailEnabled;
      _orderUpdates = orderUpdates;
      _promoOffers = promoOffers;
      _isLoading = false;
    });
  }

  Future<void> _update(String column, bool value) async {
    final userId = _userId;
    if (userId == null) return;

    await DatabaseHelper.instance.updateUserSettings(userId, {
      column: value ? 1 : 0,
    });

    try {
      await Supabase.instance.client
          .from('profiles')
          .update({
            'notification_preferences': {
              'pushEnabled': _pushEnabled,
              'emailEnabled': _emailEnabled,
              'orderUpdates': _orderUpdates,
              'promoOffers': _promoOffers,
            },
          })
          .eq('id', userId);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Preference saved on this device; cloud sync failed.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(
          "Settings",
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: _isLoading
            ? const Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 30),
                children: [
                  const _SectionHeader(label: "NOTIFICATIONS"),
                  const SizedBox(height: 10),

                  _SettingsGroup(
                    children: [
                      _SettingsSwitch(
                        icon: Icons.notifications_active_outlined,
                        title: "In-app Notifications",
                        subtitle: "Show alerts in your C+ART inbox",
                        value: _pushEnabled,
                        onChanged: (v) {
                          setState(() => _pushEnabled = v);
                          _update(DBTables.settingsPushEnabled, v);
                        },
                      ),
                      _SettingsSwitch(
                        icon: Icons.mark_email_unread_outlined,
                        title: "Email Notifications",
                        subtitle: "Coming soon",
                        value: false,
                        onChanged: null,
                      ),
                      _SettingsSwitch(
                        icon: Icons.local_shipping_outlined,
                        title: "Order Updates",
                        subtitle: "Status changes on your orders",
                        value: _orderUpdates,
                        onChanged: (v) {
                          setState(() => _orderUpdates = v);
                          _update(DBTables.settingsOrderUpdates, v);
                        },
                      ),
                      _SettingsSwitch(
                        icon: Icons.local_offer_outlined,
                        title: "Promos & Offers",
                        subtitle: "Deals from shops you follow",
                        value: _promoOffers,
                        onChanged: (v) {
                          setState(() => _promoOffers = v);
                          _update(DBTables.settingsPromoOffers, v);
                        },
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),

                  const _SectionHeader(label: "APP INFO"),
                  const SizedBox(height: 10),

                  _SettingsGroup(
                    children: [
                      _InfoRow(label: "App Version", value: "1.0.0"),
                      _InfoRow(
                        label: "Account Type",
                        value: SessionService.isSeller ? "Seller" : "Customer",
                      ),
                    ],
                  ),
                ],
              ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String label;

  const _SectionHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
          color: AppColors.textSecondary,
        ),
      ),
    );
  }
}

class _SettingsGroup extends StatelessWidget {
  final List<Widget> children;

  const _SettingsGroup({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppColors.dark.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (int i = 0; i < children.length; i++) ...[
            children[i],
            if (i != children.length - 1)
              const Divider(
                height: 1,
                thickness: 0.6,
                indent: 62,
                color: AppColors.lightGrey,
              ),
          ],
        ],
      ),
    );
  }
}

class _SettingsSwitch extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;

  const _SettingsSwitch({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 18, color: AppColors.primary),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            activeThumbColor: AppColors.primary,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
