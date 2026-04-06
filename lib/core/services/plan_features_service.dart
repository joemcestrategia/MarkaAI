import 'package:supabase_flutter/supabase_flutter.dart';

import '../constants/plan_features.dart';
import '../../modules/business/subscription_service.dart' show SubscriptionPlan;

class PlanFeaturesService {
  /// Retorna as features do usuário logado baseado em seu userMetadata do Supabase.
  /// 
  /// PRIORIDADE: Supabase metadata > Default Free
  static PlanFeatures getFeaturesForCurrentUser() {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return planFeaturesConfig[PlanKey.free]!;

    final metadata = user.userMetadata;
    final planString = metadata?['plan']?.toString().toLowerCase() ?? 'free';
    
    final key = parsePlanKey(planString);
    final baseFeatures = planFeaturesConfig[key]!;

    // REGRA DE NEGÓCIO: Aba Financeiro SÓ no plano Plus e Pro.
    // Se o plano for menor que Plus, desativamos as flags do financeiro.
    if (key == PlanKey.free || key == PlanKey.starter) {
      return _applyFinancialRestriction(baseFeatures);
    }

    return baseFeatures;
  }

  /// Retorna as features do plano atual baseado no documento da loja (uso por clientes/visitantes)
  static PlanFeatures getFeaturesForShop(Map<String, dynamic>? shopData) {
    if (shopData == null) return planFeaturesConfig[PlanKey.free]!;
    
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

    final baseFeatures = planFeaturesConfig[key]!;
    
    // Aplicamos a mesma restrição do financeiro para consistência
    if (key == PlanKey.free || key == PlanKey.starter) {
      return _applyFinancialRestriction(baseFeatures);
    }

    return baseFeatures;
  }

  /// Auxiliar para aplicar a restrição de "Financeiro só no Pro"
  static PlanFeatures _applyFinancialRestriction(PlanFeatures base) {
    return PlanFeatures(
      onlineBooking: base.onlineBooking,
      canDisableOnlineBooking: base.canDisableOnlineBooking,
      agendaInterval: base.agendaInterval,
      clientChoosesProfessional: base.clientChoosesProfessional,
      agendaOptimization: base.agendaOptimization,
      financialTab: false, // BLOQUEADO
      financialDashboard: false, // BLOQUEADO
      mercadoPagoIntegration: base.mercadoPagoIntegration,
      payments: base.payments,
      requireDeposit: base.requireDeposit,
      maxProfessionals: base.maxProfessionals,
      maxPhotosPerService: base.maxPhotosPerService,
      clientClassification: base.clientClassification,
      clientFilter: base.clientFilter,
      clientBlock: base.clientBlock,
      coupons: base.coupons,
      birthdayDiscount: base.birthdayDiscount,
      automationClientGone: base.automationClientGone,
      automationClientSawNoBook: base.automationClientSawNoBook,
      stockManagement: base.stockManagement,
      boosting: base.boosting,
      googleBackup: base.googleBackup,
      googleBusiness: base.googleBusiness,
      automaticPriceAdjustment: base.automaticPriceAdjustment,
      commissionView: base.commissionView,
      holidaysManagement: base.holidaysManagement,
      customHolidays: base.customHolidays,
      customLink: base.customLink,
      visitorsAnalytics: base.visitorsAnalytics,
    );
  }

  /// Converte valores de data (ISO String) para DateTime
  static DateTime? _toDateTime(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    // Removemos suporte legado para Timestamp do Firestore para limpeza total
    return null;
  }

  /// Detecta o plano e se o trial está ativo de forma centralizada
  static Map<String, dynamic> detectPlan(Map<String, dynamic>? shopData) {
    if (shopData == null) return {'plan': SubscriptionPlan.free, 'trial': false};

    SubscriptionPlan currentPlan = SubscriptionPlan.free;
    bool isTrial = false;

    // 1. Verifica Novo Sistema de Trial (trial data lives in subscription JSONB)
    final trialActive = shopData['trial_active'] == true;
    final sub = shopData['subscription'] as Map<String, dynamic>?;
    if (trialActive && sub != null) {
      final end = _toDateTime(sub['trial_end_date'] ?? sub['trial_ends_at']);
      if (end != null && end.isAfter(DateTime.now())) {
        currentPlan = parseSubscriptionPlan(sub['plan_id'] as String?);
        isTrial = true;
      }
    }

    // 2. Verifica Assinatura Ativa (Stripe/Nativa) se ainda não estiver em trial ativo
    if (currentPlan == SubscriptionPlan.free) {
      if (sub != null) {
        final status = sub['status']?.toString().toLowerCase();
        if (status == 'active' || status == 'trial') {
          if (status == 'trial') {
            final end = _toDateTime(sub['trial_ends_at']);
            if (end != null && end.isAfter(DateTime.now())) {
              currentPlan = SubscriptionPlan.pro;
              isTrial = true;
            }
          } else {
            final planId = sub['plan_id'] as String?;
            currentPlan = parseSubscriptionPlan(planId);
          }
        } else if (status == 'canceled' || status == 'cancelled') {
          // Acesso após cancelamento
          final accessUntil = _toDateTime(sub['access_until']);
          if (accessUntil != null && accessUntil.isAfter(DateTime.now())) {
            currentPlan = parseSubscriptionPlan(sub['plan_id'] as String?);
          }
        }
      }
    }

    // 3. Fallback final: plan_id na raiz (FK to plans table)
    if (currentPlan == SubscriptionPlan.free) {
      final rootPlanId = shopData['plan_id'] as String?;
      if (rootPlanId != null && rootPlanId != 'free') {
        currentPlan = parseSubscriptionPlan(rootPlanId);
      }
    }

    return {'plan': currentPlan, 'trial': isTrial};
  }

  /// Converte string para enum SubscriptionPlan (Backend shops table)
  static SubscriptionPlan parseSubscriptionPlan(String? id) {
    switch (id?.toLowerCase()) {
      case 'starter':
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

  /// Converte string para enum PlanKey (UI Features)
  static PlanKey parsePlanKey(String? id) {
    switch (id?.toLowerCase()) {
      case 'starter':
      case 'start':
        return PlanKey.starter;
      case 'plus':
        return PlanKey.plus;
      case 'pro':
        return PlanKey.pro;
      default:
        return PlanKey.free;
    }
  }

  /// Retorna um Stream do plano atual da loja (Supabase Realtime)
  static Stream<SubscriptionPlan> streamPlanByShopId(String shopId) {
    return Supabase.instance.client
        .from('shops')
        .stream(primaryKey: ['id'])
        .eq('id', shopId)
        .map((data) => detectPlan(data.isNotEmpty ? data.first : null)['plan'] as SubscriptionPlan);
  }

  /// Retorna um Stream das features da loja (Supabase Realtime)
  static Stream<PlanFeatures> streamFeaturesByShopId(String shopId) {
    return Supabase.instance.client
        .from('shops')
        .stream(primaryKey: ['id'])
        .eq('id', shopId)
        .map((data) => getFeaturesForShop(data.isNotEmpty ? data.first : null));
  }

  /// Extensão que permite carregar diretamente do cache/documento recebido (Supabase)
  static Future<PlanFeatures> loadFeaturesByShopId(String shopId) async {
    try {
      final data = await Supabase.instance.client
          .from('shops')
          .select()
          .eq('id', shopId)
          .maybeSingle();
          
      if (data == null) return planFeaturesConfig[PlanKey.free]!;
      return getFeaturesForShop(data);
    } catch (e) {
      return planFeaturesConfig[PlanKey.free]!;
    }
  }
}
