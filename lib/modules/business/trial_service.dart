import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/services/session_service.dart';
import 'package:flutter/material.dart';

class TrialService {
  static const String _collection = 'shops';
  static const int trialDurationDays = 30;

  /// Retorna as informações do trial para a loja logada
  static Future<Map<String, dynamic>> getTrialStatus() async {
    try {
      final shopId = await SessionService.getShopId();
      if (shopId == null) return _defaultTrialStatus();

      final supabase = Supabase.instance.client;
      final data = await supabase
          .from(_collection)
          .select()
          .eq('id', shopId)
          .maybeSingle();
          
      if (data == null) return _defaultTrialStatus();

      final sub = data['subscription'] as Map<String, dynamic>? ?? {};
      bool trialUsed = sub['trial_used'] ?? false;
      bool trialActive = data['trial_active'] ?? false;
      String? trialPlan = sub['trial_plan'] ?? sub['plan_id'];
      String? trialEndDateStr = (sub['trial_end_date'] ?? sub['trial_ends_at'])?.toString();

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
        'canUseTrial': !trialUsed,
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
  static Future<void> checkAndDeactivateExpiredTrial() async {
    try {
      final shopId = await SessionService.getShopId();
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
      String? trialEndDateStr = (sub['trial_end_date'] ?? sub['trial_ends_at'])?.toString();

      if (trialActive && trialEndDateStr != null) {
        final endDate = DateTime.tryParse(trialEndDateStr);
        if (endDate != null && endDate.difference(DateTime.now()).isNegative) {
          // O Trial expirou! Atualizamos no banco
          await supabase
              .from(_collection)
              .update({
                'trial_active': false,
                'plan_id': 'free',
              })
              .eq('id', shopId);
          debugPrint("TrialService: Trial expirado e desativado com sucesso.");
        }
      }
    } catch (e) {
      debugPrint("Erro ao checar expiração de trial: $e");
    }
  }

  /// Ativa o Trial para o plano selecionado (agora fixo no Plus). Não pode ser desfeito.
  static Future<bool> activateTrial([String? _]) async {
    try {
      final shopId = await SessionService.getShopId();
      if (shopId == null) return false;

      const planId = 'plus'; // Único plano disponível para teste agora

      final supabase = Supabase.instance.client;
      final data = await supabase
          .from(_collection)
          .select()
          .eq('id', shopId)
          .maybeSingle();
          
      if (data == null) return false;

      final existingSub = data['subscription'] as Map<String, dynamic>? ?? {};
      if (existingSub['trial_used'] == true) {
        debugPrint("Tentativa inválida: Trial já foi utilizado.");
        return false;
      }

      final now = DateTime.now();
      final endDate = now.add(const Duration(days: trialDurationDays));

      await supabase
          .from(_collection)
          .update({
        'plan_id': planId,
        'trial_active': true,
        'subscription': {
          'status': 'trial',
          'plan_id': planId,
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
