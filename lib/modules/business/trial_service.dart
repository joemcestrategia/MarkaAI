import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/services/session_service.dart';
import 'package:flutter/material.dart';

class TrialService {
  static const String _collection = 'shops';
  static const int trialDurationDays = 30;

  /// Retorna as informações do trial para a loja logada
  static Future<Map<String, dynamic>> getTrialStatus([String? explicitShopId]) async {
    try {
      final shopId = explicitShopId ?? await SessionService.getShopId();
      if (shopId == null) return _defaultTrialStatus();

      final supabase = Supabase.instance.client;
      final data = await supabase
          .from(_collection)
          .select()
          .eq('id', shopId)
          .maybeSingle();
          
      if (data == null) return _defaultTrialStatus();

      final sub = data['subscription'] as Map<String, dynamic>? ?? {};
      bool trialUsed = sub['trial_used'] == true || data['has_used_trial'] == true;
      bool trialActive = data['trial_active'] ?? false;
      String? trialPlan = sub['trial_plan'] ?? sub['plan_id'] ?? data['plan_id'];
      String? trialEndDateStr = (sub['trial_end_date'] ?? sub['trial_ends_at'] ?? data['trial_end'])?.toString();

      int daysRemaining = 0;
      bool trialExpired = false;
      DateTime? endDate;

      if (trialActive && trialEndDateStr != null) {
        endDate = DateTime.tryParse(trialEndDateStr);
        if (endDate != null) {
          final now = DateTime.now();
          final diff = endDate.difference(now);

          if (diff.isNegative) {
            trialExpired = true;
            trialActive = false; // Expirado localmente
          } else {
            daysRemaining = diff.inDays;
          }
        }
      }

      return {
        'canUseTrial': !trialUsed && (data['plan_id'] == 'free' || data['plan_id'] == null),
        'trialActive': trialActive,
        'trialExpired': trialExpired,
        'daysRemaining': daysRemaining,
        'trialPlan': trialPlan,
        'endDate': endDate,
      };
    } catch (e) {
      debugPrint("Erro ao obter status do trial: $e");
      return _defaultTrialStatus();
    }
  }

  /// Verifica e desativa um trial expirado lazily (chamado ao checar planos se estiver expirado)
  static Future<void> checkAndDeactivateExpiredTrial([String? explicitShopId]) async {
    try {
      final shopId = explicitShopId ?? await SessionService.getShopId();
      if (shopId == null) return;

      final supabase = Supabase.instance.client;
      final data = await supabase
          .from(_collection)
          .select()
          .eq('id', shopId)
          .maybeSingle();
          
      if (data == null) return;

      bool trialActive = data['trial_active'] ?? false;
      final sub = data['subscription'] as Map<String, dynamic>? ?? {};
      String? trialEndDateStr = (sub['trial_end_date'] ?? sub['trial_ends_at'] ?? data['trial_end'])?.toString();

      if (trialActive && trialEndDateStr != null) {
        final endDate = DateTime.tryParse(trialEndDateStr);
        if (endDate != null && endDate.difference(DateTime.now()).isNegative) {
          // O Trial expirou! Atualizamos no banco
          await supabase
              .from(_collection)
              .update({
                'trial_active': false,
                'plan_id': 'free',
                'subscription': {
                  ...sub,
                  'status': 'free',
                  'plan_id': 'free',
                  'plano': 'free',
                  'updated_at': DateTime.now().toIso8601String(),
                },
              })
              .eq('id', shopId);
          debugPrint("TrialService: Trial expirado e desativado com sucesso para shop $shopId.");
        }
      } else if (trialActive && (sub['status'] == 'free' || sub['plan_id'] == 'free' || sub['plano'] == 'free')) {
        // Se trial_active ficou órfão como true mas subscription é free
        await supabase
            .from(_collection)
            .update({
              'trial_active': false,
              'plan_id': 'free',
            })
            .eq('id', shopId);
        debugPrint("TrialService: trial_active órfão corrigido para shop $shopId.");
      }
    } catch (e) {
      debugPrint("Erro ao checar expiração de trial: $e");
    }
  }

  /// Ativa o Trial para o plano selecionado. Não pode ser desfeito.
  static Future<bool> activateTrial([
    String? planChoice,
    int durationDays = trialDurationDays,
    String? explicitShopId,
  ]) async {
    try {
      final shopId = explicitShopId ?? await SessionService.getShopId();
      if (shopId == null) return false;

      final planId = planChoice ?? 'plus';

      final supabase = Supabase.instance.client;
      final data = await supabase
          .from(_collection)
          .select()
          .eq('id', shopId)
          .maybeSingle();
          
      if (data == null) return false;

      final existingSub = data['subscription'] as Map<String, dynamic>? ?? {};
      if (existingSub['trial_used'] == true && explicitShopId == null) {
        debugPrint("Tentativa inválida: Trial já foi utilizado.");
        return false;
      }

      final now = DateTime.now();
      final endDate = now.add(Duration(days: durationDays));

      await supabase
          .from(_collection)
          .update({
        'plan_id': planId,
        'trial_active': true,
        'has_used_trial': true,
        'subscription': {
          'status': 'trial',
          'plan_id': planId,
          'plano': planId,
          'trial_used': true,
          'trial_plan': planId,
          'trial_start_date': now.toIso8601String(),
          'trial_end_date': endDate.toIso8601String(),
          'trial_ends_at': endDate.toIso8601String(),
          'updated_at': now.toIso8601String(),
        },
      }).eq('id', shopId);

      return true;
    } catch (e) {
      debugPrint("Erro ao ativar trial: $e");
      return false;
    }
  }

  static Map<String, dynamic> _defaultTrialStatus() {
    return {
      'canUseTrial': false, // Falha segura: nega o trial se der erro
      'trialActive': false,
      'trialExpired': false,
      'daysRemaining': 0,
      'trialPlan': null,
      'endDate': null,
    };
  }
}
