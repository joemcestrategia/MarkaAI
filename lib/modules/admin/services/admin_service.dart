import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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

  Future<Map<String, dynamic>> getAppointmentMetrics() async {
    final response = await _supabase
        .from('admin_appointment_metrics')
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
    // 1. Atualiza colunas nativas e JSONB de subscription
    await _supabase.from('shops').update({
      'plan_id': newPlan,
      'trial_active': false,
      'subscription': {
        'plan_id': newPlan,
        'plano': newPlan,
        'status': 'active',
        'updated_at': DateTime.now().toIso8601String(),
      }
    }).eq('id', shopId);

    // 2. Atualiza users.plan onde shop_id = shopId
    try {
      await _supabase.from('users').update({'plan': newPlan}).eq('shop_id', shopId);
    } catch (_) {}

    // 3. Record in history
    await _supabase.from('subscription_history').insert({
      'shop_id': shopId,
      'old_plan': oldPlan,
      'new_plan': newPlan,
      'changed_by': adminId,
      'reason': reason ?? 'Alteração manual via admin',
      'source': 'admin',
    });

    // 4. Log action
    await logAction(
      adminId: adminId,
      action: 'change_plan',
      targetType: 'shop',
      targetId: shopId,
      details: {'old_plan': oldPlan, 'new_plan': newPlan, 'reason': reason},
    );
  }

  /// Aplica um período de teste (trial) de qualquer plano à loja desejada
  Future<void> applyShopTrial({
    required String shopId,
    required String oldPlan,
    required String targetPlan,
    required int durationDays,
    required String adminId,
    String? reason,
  }) async {
    final now = DateTime.now();
    final endDate = now.add(Duration(days: durationDays));

    // 1. Atualiza na tabela shops com todas as colunas de sincronia
    await _supabase.from('shops').update({
      'plan_id': targetPlan,
      'trial_active': true,
      'has_used_trial': true,
      'subscription': {
        'plan_id': targetPlan,
        'plano': targetPlan,
        'status': 'trial',
        'trial_used': true,
        'trial_plan': targetPlan,
        'trial_start_date': now.toIso8601String(),
        'trial_end_date': endDate.toIso8601String(),
        'trial_ends_at': endDate.toIso8601String(),
        'updated_at': now.toIso8601String(),
      }
    }).eq('id', shopId);

    // 2. Atualiza users.plan
    try {
      await _supabase.from('users').update({'plan': targetPlan}).eq('shop_id', shopId);
    } catch (_) {}

    // 3. Registra no histórico de assinaturas
    await _supabase.from('subscription_history').insert({
      'shop_id': shopId,
      'old_plan': oldPlan,
      'new_plan': 'trial_$targetPlan',
      'changed_by': adminId,
      'reason': reason ?? 'Trial de $durationDays dias aplicado pelo admin',
      'source': 'admin_trial',
    });

    // 4. Registra no log de auditoria
    await logAction(
      adminId: adminId,
      action: 'apply_trial',
      targetType: 'shop',
      targetId: shopId,
      details: {
        'old_plan': oldPlan,
        'target_plan': targetPlan,
        'duration_days': durationDays,
        'expires_at': endDate.toIso8601String(),
        'reason': reason,
      },
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

  // --- Diagnóstico e Suporte de Autenticação de Usuários ---

  /// Retorna um mapa (userId -> dados resumidos de auth.users) para enriquecer a listagem do Admin
  Future<Map<String, Map<String, dynamic>>> getUsersAuthSummary() async {
    try {
      final res = await _supabase.functions.invoke(
        'admin-user-auth',
        body: {'action': 'summary'},
      );
      if (res.status == 200 && res.data is Map) {
        final rawUsers = res.data['users'];
        if (rawUsers is Map) {
          return rawUsers.map(
            (key, value) => MapEntry(
              key.toString(),
              Map<String, dynamic>.from(value as Map),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('[AdminService] Fallback RPC getUsersAuthSummary: $e');
    }

    try {
      final rpcRes = await _supabase.rpc('admin_get_users_auth_summary');
      if (rpcRes is List) {
        final map = <String, Map<String, dynamic>>{};
        for (final row in rpcRes) {
          final m = Map<String, dynamic>.from(row as Map);
          final uid = (m['user_id'] ?? m['id'] ?? '').toString();
          if (uid.isNotEmpty) {
            map[uid] = m;
          }
        }
        return map;
      }
    } catch (e) {
      debugPrint('[AdminService] Erro em admin_get_users_auth_summary: $e');
    }

    return {};
  }

  /// Retorna o diagnóstico completo de um usuário (Auth, Identidades, Resend Emails, Agendamentos e Lojas)
  Future<Map<String, dynamic>> getUserFullDiagnostics(String userId) async {
    try {
      final res = await _supabase.functions.invoke(
        'admin-user-auth',
        body: {'action': 'details', 'userId': userId},
      );
      if (res.status == 200 && res.data is Map) {
        return Map<String, dynamic>.from(res.data as Map);
      }
    } catch (e) {
      debugPrint('[AdminService] Fallback RPC getUserFullDiagnostics: $e');
    }

    try {
      final rpcRes = await _supabase.rpc(
        'admin_get_user_full_diagnostics',
        params: {'p_user_id': userId},
      );
      if (rpcRes is Map) {
        return Map<String, dynamic>.from(rpcRes);
      }
    } catch (e) {
      debugPrint('[AdminService] Erro em admin_get_user_full_diagnostics: $e');
    }

    return {};
  }

  /// Confirma manualmente o e-mail de um usuário no Supabase Auth e ativa no public.users
  Future<void> confirmUserEmailManually(String userId) async {
    final res = await _supabase.functions.invoke(
      'admin-user-auth',
      body: {'action': 'confirm_email', 'userId': userId},
    );
    if (res.status != 200) {
      final errMsg = (res.data is Map ? res.data['error'] : null) ?? 'Erro ao confirmar e-mail';
      throw Exception(errMsg);
    }
  }

  /// Define manualmente uma nova senha para o usuário no Supabase Auth (e confirma o e-mail automaticamente)
  Future<void> setUserPasswordManually(String userId, String newPassword) async {
    final res = await _supabase.functions.invoke(
      'admin-user-auth',
      body: {
        'action': 'set_password',
        'userId': userId,
        'password': newPassword,
      },
    );
    if (res.status != 200) {
      final errMsg = (res.data is Map ? res.data['error'] : null) ?? 'Erro ao definir nova senha';
      throw Exception(errMsg);
    }
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
      debugPrint('Erro ao registrar log de auditoria: $e');
    }
  }
}
