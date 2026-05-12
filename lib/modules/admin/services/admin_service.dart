import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:markaai/core/services/session_service.dart';

class AdminService {
  static final AdminService _instance = AdminService._internal();
  factory AdminService() => _instance;
  AdminService._internal();

  final _supabase = Supabase.instance.client;

  // --- Métricas ---
  Future<Map<String, dynamic>> getRevenueMetrics() async {
    final response = await _supabase
        .from('admin_revenue_metrics')
        .select()
        .single();
    return response;
  }

  Future<List<Map<String, dynamic>>> getGrowthDaily({int days = 90}) async {
    final response = await _supabase
        .from('admin_growth_daily')
        .select()
        .limit(days)
        .order('dia', ascending: false);
    return List<Map<String, dynamic>>.from(response);
  }

  // --- Tenants ---
  Future<void> changeShopPlan(String shopId, String oldPlan, String newPlan, String adminId, {String? reason}) async {
    // 1. Update shop subscription
    await _supabase.from('shops').update({
      'subscription': {
        'plano': newPlan,
        'status': 'active',
        'updated_at': DateTime.now().toIso8601String(),
      }
    }).eq('id', shopId);

    // 2. Record in history
    await _supabase.from('subscription_history').insert({
      'shop_id': shopId,
      'old_plan': oldPlan,
      'new_plan': newPlan,
      'changed_by': adminId,
      'reason': reason ?? 'Alteração manual via admin',
      'source': 'admin',
    });

    // 3. Log action
    await logAction(
      adminId: adminId,
      action: 'change_plan',
      targetType: 'shop',
      targetId: shopId,
      details: {'old_plan': oldPlan, 'new_plan': newPlan, 'reason': reason},
    );
  }

  Future<void> toggleShopBlock(String shopId, String ownerId, bool block, String adminId) async {
    // 1. Update user active status
    await _supabase.from('users').update({
      'is_active': !block,
    }).eq('id', ownerId);

    // 2. Log action
    await logAction(
      adminId: adminId,
      action: block ? 'block_shop' : 'unblock_shop',
      targetType: 'shop',
      targetId: shopId,
      details: {'owner_id': ownerId},
    );
  }

  // --- Feature Flags ---
  Future<List<Map<String, dynamic>>> getFeatureFlags() async {
    final response = await _supabase
        .from('feature_flags')
        .select()
        .order('label');
    return List<Map<String, dynamic>>.from(response);
  }

  Future<void> updateFeatureFlag(String flagId, Map<String, dynamic> updates, String adminId) async {
    await _supabase.from('feature_flags').update(updates).eq('id', flagId);
    
    await logAction(
      adminId: adminId,
      action: 'update_feature_flag',
      targetType: 'feature_flag',
      targetId: flagId,
      details: updates,
    );
  }

  // --- Auditoria ---
  Future<void> logAction({
    required String adminId,
    required String action,
    String? targetType,
    String? targetId,
    Map<String, dynamic>? details,
  }) async {
    try {
      await _supabase.from('admin_audit_log').insert({
        'admin_id': adminId,
        'action': action,
        'target_type': targetType,
        'target_id': targetId,
        'details': details,
      });
    } catch (e) {
      print('Erro ao registrar log de auditoria: $e');
    }
  }
}
