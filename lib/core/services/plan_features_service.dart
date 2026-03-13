// lib/core/services/plan_features_service.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import '../../modules/business/subscription_service.dart';
import '../constants/plan_features.dart';

class PlanFeaturesService {
  /// Retorna as features do plano atual baseado no documento da loja
  static PlanFeatures getFeaturesForShop(Map<String, dynamic>? shopData) {
    final detection = detectPlan(shopData);
    final SubscriptionPlan currentPlan = detection['plan'];

    // Converte o enum do SubscriptionService para o PlanKey
    PlanKey key = PlanKey.free;
    switch (currentPlan) {
      case SubscriptionPlan.start:
        key = PlanKey.starter;
        break;
      case SubscriptionPlan.plus:
        key = PlanKey.plus;
        break;
      case SubscriptionPlan.pro:
        key = PlanKey.pro;
        break;
      case SubscriptionPlan.free:
        key = PlanKey.free;
        break;
    }

    return planFeaturesConfig[key]!;
  }

  /// Detecta o plano e se o trial está ativo de forma centralizada
  static Map<String, dynamic> detectPlan(Map<String, dynamic>? shopData) {
    if (shopData == null) return {'plan': SubscriptionPlan.free, 'trial': false};

    SubscriptionPlan currentPlan = SubscriptionPlan.free;
    bool isTrial = false;

    // 1. Verifica Novo Sistema de Trial
    final trialActive = shopData['trial_active'] == true;
    if (trialActive) {
      final end = (shopData['trial_end_date'] as Timestamp?)?.toDate();
      if (end != null && end.isAfter(DateTime.now())) {
        currentPlan = parsePlanId(shopData['trial_plan'] as String?);
        isTrial = true;
      }
    }

    // 2. Verifica Assinatura Ativa (Stripe/Nativa) se ainda não estiver em trial ativo
    if (currentPlan == SubscriptionPlan.free) {
      final sub = shopData['subscription'] as Map<String, dynamic>?;
      if (sub != null) {
        if (sub['status'] == 'active' || sub['status'] == 'trial') {
          if (sub['status'] == 'trial') {
            final end = (sub['trial_ends_at'] as Timestamp?)?.toDate();
            if (end != null && end.isAfter(DateTime.now())) {
              currentPlan = SubscriptionPlan.pro;
              isTrial = true;
            }
          } else {
            final planId = sub['plan_id'] as String?;
            currentPlan = parsePlanId(planId);
          }
        } else if (sub['status'] == 'canceled' || sub['status'] == 'cancelled') {
          // Acesso após cancelamento
          final accessUntil = (sub['access_until'] as Timestamp?)?.toDate();
          if (accessUntil != null && accessUntil.isAfter(DateTime.now())) {
            currentPlan = parsePlanId(sub['plan_id'] as String?);
          }
        }
      }
    }

    // 3. Fallback final: campos plan/plan_id na raiz (consistente com SubscriptionService)
    if (currentPlan == SubscriptionPlan.free) {
      final rootPlanId = (shopData['plan'] as String?) ?? (shopData['plan_id'] as String?);
      if (rootPlanId != null && rootPlanId != 'free') {
        currentPlan = parsePlanId(rootPlanId);
      }
    }

    return {'plan': currentPlan, 'trial': isTrial};
  }

  static SubscriptionPlan parsePlanId(String? id) {
    switch (id) {
      case 'start':
        return SubscriptionPlan.start;
      case 'plus':
        return SubscriptionPlan.plus;
      case 'pro':
        return SubscriptionPlan.pro;
      default:
        return SubscriptionPlan.free;
    }
  }

  /// Retorna um Stream das features da loja
  static Stream<PlanFeatures> streamFeaturesByShopId(String shopId) {
    return FirebaseFirestore.instance
        .collection('shops')
        .doc(shopId)
        .snapshots()
        .map((doc) => getFeaturesForShop(doc.data()));
  }

  /// Extensão que permite carregar diretamente do cache/documento recebido
  static Future<PlanFeatures> loadFeaturesByShopId(String shopId) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('shops')
          .doc(shopId)
          .get();
      if (!doc.exists) return planFeaturesConfig[PlanKey.free]!;
      return getFeaturesForShop(doc.data());
    } catch (e) {
      return planFeaturesConfig[PlanKey.free]!;
    }
  }
}
