import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/voucher_model.dart';

class FollowerCampaignAnalytics {
  final int newFollowers;
  final int claimed;
  final int redeemed;
  final double revenue;

  const FollowerCampaignAnalytics({
    required this.newFollowers,
    required this.claimed,
    required this.redeemed,
    required this.revenue,
  });

  static const empty = FollowerCampaignAnalytics(
    newFollowers: 0,
    claimed: 0,
    redeemed: 0,
    revenue: 0,
  );
}

class VoucherPage {
  final List<VoucherModel> items;
  final String? cursor;
  final bool hasMore;

  const VoucherPage({
    required this.items,
    required this.cursor,
    required this.hasMore,
  });
}

class VoucherRepository {
  SupabaseClient get _supabase => Supabase.instance.client;

  Future<Map<String, dynamic>?> getCampaign(int sellerId) async {
    final row = await _supabase
        .from('follower_campaigns')
        .select()
        .eq('seller_id', sellerId)
        .maybeSingle();
    return row == null ? null : _campaignMap(row);
  }

  Future<VoucherPage> walletPage(
    int customerId, {
    String? after,
    int pageSize = 20,
  }) async {
    var query = _supabase
        .from('customer_vouchers')
        .select()
        .eq('customer_id', customerId);
    if (after != null) query = query.lt('claimed_at', after);
    final rows = await query
        .order('claimed_at', ascending: false)
        .limit(pageSize + 1);
    final pageRows = rows.take(pageSize).toList();
    return VoucherPage(
      items: pageRows.map(_voucherFromRow).toList(),
      cursor: pageRows.isEmpty ? after : pageRows.last['claimed_at'] as String?,
      hasMore: rows.length > pageSize,
    );
  }

  Future<List<VoucherModel>> availableWallet(int customerId) async {
    final rows = await _supabase
        .from('customer_vouchers')
        .select()
        .eq('customer_id', customerId)
        .isFilter('order_id', null)
        .gt('expires_at', DateTime.now().toUtc().toIso8601String())
        .order('expires_at');
    return rows.map(_voucherFromRow).toList();
  }

  Future<int> availableVoucherCount(int customerId) async {
    return (await availableWallet(customerId)).length;
  }

  Future<FollowerCampaignAnalytics> getCampaignAnalytics(
    int sellerId,
    Map<String, dynamic> campaignData,
  ) async {
    final campaignId = campaignData['campaignId'] as String?;
    final startsAt = campaignData['startsAt'] as DateTime?;
    final expiresAt = campaignData['expiresAt'] as DateTime?;
    if (campaignId == null || startsAt == null || expiresAt == null) {
      return FollowerCampaignAnalytics.empty;
    }

    final vouchers = await _supabase
        .from('customer_vouchers')
        .select('order_id,revenue')
        .eq('seller_id', sellerId)
        .eq('campaign_id', campaignId);
    final followers = await _supabase
        .from('shop_follow_history')
        .select('customer_id')
        .eq('seller_id', sellerId)
        .gte('first_followed_at', startsAt.toUtc().toIso8601String())
        .lt('first_followed_at', expiresAt.toUtc().toIso8601String());
    final redeemed = vouchers.where((row) => row['order_id'] != null).toList();
    return FollowerCampaignAnalytics(
      newFollowers: followers.length,
      claimed: (campaignData['claimed'] as num?)?.toInt() ?? 0,
      redeemed: redeemed.length,
      revenue: redeemed.fold<double>(
        0,
        (total, row) => total + ((row['revenue'] as num?)?.toDouble() ?? 0),
      ),
    );
  }

  Future<void> createCampaign(int sellerId, Map<String, dynamic> config) async {
    final startsAt = config['startsAt'] as DateTime;
    final expiresAt = config['expiresAt'] as DateTime;
    final value = (config['value'] as num).toDouble();
    final minimum = (config['minimum'] as num).toDouble();
    final maximum = (config['maximum'] as num?)?.toDouble();
    if (!value.isFinite ||
        value <= 0 ||
        (config['type'] == 'percentage' && value > 100) ||
        !minimum.isFinite ||
        minimum < 0 ||
        (maximum != null && (!maximum.isFinite || maximum <= 0)) ||
        (config['quantity'] as int) <= 0 ||
        (config['validDays'] as int) <= 0 ||
        !expiresAt.isAfter(DateTime.now()) ||
        !expiresAt.isAfter(startsAt)) {
      throw ArgumentError('Check the campaign amounts, quantity and dates.');
    }
    await _supabase.rpc(
      'create_follower_campaign',
      params: {
        'config': {
          'type': config['type'],
          'value': value,
          'minimum': minimum,
          'maximum': maximum,
          'quantity': config['quantity'],
          'valid_days': config['validDays'],
          'starts_at': startsAt.toUtc().toIso8601String(),
          'expires_at': expiresAt.toUtc().toIso8601String(),
        },
      },
    );
  }

  Future<void> setStatus(int sellerId, String status) async {
    if (!['active', 'paused', 'ended'].contains(status)) {
      throw ArgumentError('Invalid status');
    }
    await _supabase
        .from('follower_campaigns')
        .update({'status': status})
        .eq('seller_id', sellerId)
        .neq('status', 'ended');
  }

  Future<({bool following, VoucherModel? voucher})> toggleFollow(
    int customerId,
    int sellerId,
  ) async {
    final raw = await _supabase.rpc(
      'toggle_shop_follow',
      params: {'target_seller_id': sellerId},
    );
    final data = Map<String, dynamic>.from(raw as Map);
    final voucherId = data['voucher_id'] as String?;
    VoucherModel? voucher;
    if (voucherId != null) {
      final row = await _supabase
          .from('customer_vouchers')
          .select()
          .eq('id', voucherId)
          .maybeSingle();
      if (row != null) voucher = _voucherFromRow(row);
    }
    return (following: data['following'] == true, voucher: voucher);
  }

  Map<String, dynamic> _campaignMap(Map<String, dynamic> row) => {
    'campaignId': row['campaign_id'],
    'sellerId': (row['seller_id'] as num).toInt(),
    'type': row['type'],
    'value': row['value'],
    'minimum': row['minimum'],
    'maximum': row['maximum'],
    'quantity': row['quantity'],
    'claimed': row['claimed'],
    'validDays': row['valid_days'],
    'status': row['status'],
    'startsAt': DateTime.parse(row['starts_at'] as String).toLocal(),
    'expiresAt': DateTime.parse(row['expires_at'] as String).toLocal(),
    'createdAt': DateTime.parse(row['created_at'] as String).toLocal(),
  };

  VoucherModel _voucherFromRow(Map<String, dynamic> row) {
    return VoucherModel(row['id'] as String, {
      'campaignId': row['campaign_id'],
      'customerId': (row['customer_id'] as num).toInt(),
      'sellerId': (row['seller_id'] as num).toInt(),
      'sellerName': row['seller_name'],
      'type': row['type'],
      'value': row['value'],
      'minimum': row['minimum'],
      'maximum': row['maximum'],
      'claimedAt': DateTime.parse(row['claimed_at'] as String).toLocal(),
      'expiresAt': DateTime.parse(row['expires_at'] as String).toLocal(),
      'orderId': row['order_id'],
      'redeemedAt': row['redeemed_at'] == null
          ? null
          : DateTime.parse(row['redeemed_at'] as String).toLocal(),
      'revenue': row['revenue'],
    });
  }
}
