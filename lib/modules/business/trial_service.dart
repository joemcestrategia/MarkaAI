import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/services/session_service.dart';
import 'package:flutter/material.dart';

class TrialService {
  static const String _collection = 'shops';
  static const int trialDurationDays = 90;

  /// Retorna as informações do trial para a loja logada
  static Future<Map<String, dynamic>> getTrialStatus() async {
    try {
      final shopId = await SessionService.getShopId();
      if (shopId == null) return _defaultTrialStatus();

      final doc = await FirebaseFirestore.instance
          .collection(_collection)
          .doc(shopId)
          .get();
      if (!doc.exists) return _defaultTrialStatus();

      final data = doc.data()!;

      bool trialUsed = data['trial_used'] ?? false;
      bool trialActive = data['trial_active'] ?? false;
      String? trialPlan = data['trial_plan'];
      Timestamp? trialEndTimestamp = data['trial_end_date'];

      int daysRemaining = 0;
      bool trialExpired = false;

      if (trialActive && trialEndTimestamp != null) {
        final endDate = trialEndTimestamp.toDate();
        final now = DateTime.now();
        final diff = endDate.difference(now);

        if (diff.isNegative) {
          trialExpired = true;
          trialActive =
              false; // Deveria ser atualizado no backend, mas marcamos como expirado localmente
        } else {
          daysRemaining = diff.inDays;
        }
      }

      return {
        'canUseTrial': !trialUsed,
        'trialActive': trialActive,
        'trialExpired': trialExpired,
        'daysRemaining': daysRemaining,
        'trialPlan': trialPlan,
        'endDate': trialEndTimestamp?.toDate(),
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

      final doc = await FirebaseFirestore.instance
          .collection(_collection)
          .doc(shopId)
          .get();
      if (!doc.exists) return;

      final data = doc.data()!;
      bool trialActive = data['trial_active'] ?? false;
      Timestamp? trialEndTimestamp = data['trial_end_date'];

      if (trialActive && trialEndTimestamp != null) {
        final endDate = trialEndTimestamp.toDate();
        if (endDate.difference(DateTime.now()).isNegative) {
          // O Trial expirou! Atualizamos no banco
          await FirebaseFirestore.instance
              .collection(_collection)
              .doc(shopId)
              .update({
            'trial_active': false,
          });
          debugPrint("TrialService: Trial expirado e desativado com sucesso.");
        }
      }
    } catch (e) {
      debugPrint("Erro ao checar expiração de trial: $e");
    }
  }

  /// Ativa o Trial para o plano selecionado. Não pode ser desfeito.
  static Future<bool> activateTrial(String planId) async {
    try {
      final shopId = await SessionService.getShopId();
      if (shopId == null) return false;

      final doc = await FirebaseFirestore.instance
          .collection(_collection)
          .doc(shopId)
          .get();
      if (!doc.exists) return false;

      final data = doc.data()!;
      if (data['trial_used'] == true) {
        debugPrint("Tentativa inválida: Trial já foi utilizado.");
        return false;
      }

      final now = DateTime.now();
      final endDate = now.add(const Duration(days: trialDurationDays));

      await FirebaseFirestore.instance
          .collection(_collection)
          .doc(shopId)
          .update({
        'trial_used': true,
        'trial_plan': planId,
        'trial_active': true,
        'trial_start_date': FieldValue.serverTimestamp(),
        'trial_end_date': Timestamp.fromDate(endDate),
      });

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
