import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;
import '../../core/services/session_service.dart';
import 'trial_service.dart';
import '../../core/services/stripe_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/premium_dialogs.dart';
import '../../core/services/auth_service.dart';

class LiveSubscriptionStatus {
  final String status;
  final String planId;
  final DateTime? subscriptionStartedAt;
  final DateTime? currentPeriodEnd;
  final bool cancelAtPeriodEnd;
  final bool hasUsedTrial;
  final bool isLive;
  final bool isManual;

  LiveSubscriptionStatus({
    required this.status,
    required this.planId,
    this.subscriptionStartedAt,
    this.currentPeriodEnd,
    required this.cancelAtPeriodEnd,
    required this.hasUsedTrial,
    required this.isLive,
    this.isManual = false,
  });

  factory LiveSubscriptionStatus.fromMap(Map<String, dynamic> map, {bool isLive = true}) {
    return LiveSubscriptionStatus(
      status: map['status'] ?? 'free',
      planId: map['planId'] ?? map['plan_id'] ?? 'free',
      subscriptionStartedAt: map['subscriptionStartedAt'] != null 
          ? DateTime.tryParse(map['subscriptionStartedAt'].toString()) 
          : (map['subscription_started_at'] != null ? DateTime.tryParse(map['subscription_started_at'].toString()) : null),
      currentPeriodEnd: map['currentPeriodEnd'] != null 
          ? DateTime.tryParse(map['currentPeriodEnd'].toString())
          : (map['current_period_end'] != null ? DateTime.tryParse(map['current_period_end'].toString()) : null),
      cancelAtPeriodEnd: map['cancelAtPeriodEnd'] ?? map['cancel_at_period_end'] ?? false,
      hasUsedTrial: map['hasUsedTrial'] ?? map['has_used_trial'] ?? false,
      isLive: isLive,
      isManual: map['isManual'] ?? false,
    );
  }
}

enum SubscriptionPlan { free, start, plus, pro }

class SubscriptionService {
  static const String _collection = 'shops';

  // Definição dos Planos
  static final Map<SubscriptionPlan, Map<String, dynamic>> _plans = {
    SubscriptionPlan.free: {
      'name': 'Free',
      'price': 0.00,
      'employeeLimit': 1,
      'clientLimit': 50,
      'adEnabled': false,
      'onlinePayment': false,
      'financialModule': false,
      'commissionModule': false,
      'inventoryModule': false,
      'customLink': true,
      'maxServicePhotos': 1,
      'advancedScheduling': false,
      'features': ['scheduling'],
      'description': 'Experimente sem custo. Ideal para quem está começando.',
    },
    SubscriptionPlan.start: {
      'name': 'Start',
      'price': 29.90,
      'employeeLimit': 1,
      'clientLimit': 500,
      'adEnabled': false,
      'onlinePayment': true,
      'financialModule': false,
      'commissionModule': true,
      'inventoryModule': false,
      'customLink': true,
      'maxServicePhotos': 3,
      'advancedScheduling': false,
      'features': ['Agendamento Online', 'Pagamento via PIX', 'Visualizar Comissões'],
      'description': 'Receba via PIX, exija sinal e organize melhor a agenda.',
    },
    SubscriptionPlan.plus: {
      'name': 'Plus',
      'price': 59.90,
      'employeeLimit': 2,
      'clientLimit': 999999,
      'adEnabled': false,
      'onlinePayment': true,
      'financialModule': true,
      'commissionModule': true,
      'inventoryModule': false,
      'customLink': true,
      'maxServicePhotos': 5,
      'advancedScheduling': true,
      'features': [
        'Cupons de Desconto',
        'Reajuste Automático de Valores',
        'Classificação de Clientes (VIP)',
        'Desconto de Aniversário Automático',
        'Automações de Marketing'
      ],
      'description': 'Controle total: financeiro, feriados e descontos. Ideal para 2 profissionais.',
    },
    SubscriptionPlan.pro: {
      'name': 'Pro',
      'price': 99.90,
      'employeeLimit': 3,
      'clientLimit': 999999,
      'adEnabled': false,
      'onlinePayment': true,
      'financialModule': true,
      'commissionModule': true,
      'inventoryModule': true,
      'customLink': true,
      'maxServicePhotos': 5,
      'advancedScheduling': true,
      'nfseEmission': false,
      'features': [
        'Painel Financeiro Completo (DRE/Caixa)',
        'Gestão de Estoque Completa',
        'Lembrete Automático por WhatsApp',
        'Todas as funções liberadas'
      ],
      'description': '3 profissionais, estoque e WhatsApp. Máximo poder.',
    },
  };

  /// Busca o status ao vivo da Stripe API, com fallback pro cache
  static Future<LiveSubscriptionStatus> getLiveSubscriptionStatus({required String shopId}) async {
    final supabase = sb.Supabase.instance.client;
    try {
      // Timeout curto (5s) pra evitar travar a tela
      final response = await supabase.functions.invoke(
        'get-live-subscription-status',
        body: {'shopId': shopId},
      ).timeout(const Duration(seconds: 5));

      if (response.status == 200 && response.data != null) {
        return LiveSubscriptionStatus.fromMap(response.data as Map<String, dynamic>, isLive: true);
      }
    } catch (e) {
      debugPrint('getLiveSubscriptionStatus falhou (caindo pro fallback): $e');
    }

    // Fallback: lê a tabela shops
    try {
      final res = await supabase.from('shops').select('subscription, has_used_trial, plan_id, cancel_at_period_end, current_period_end, subscription_started_at').eq('id', shopId).maybeSingle();
      if (res != null) {
        final isManual = res['subscription'] == null || res['subscription']['stripe_subscription_id'] == null;
        return LiveSubscriptionStatus.fromMap({
          ...res,
          'status': res['subscription']?['status'],
          'isManual': isManual,
        }, isLive: false);
      }
    } catch (e) {
      debugPrint('Fallback do getLiveSubscriptionStatus também falhou: $e');
    }

    return LiveSubscriptionStatus(
      status: 'free',
      planId: 'free',
      cancelAtPeriodEnd: false,
      hasUsedTrial: false,
      isLive: false,
    );
  }

  /// Retorna o plano atual da loja logada (apenas para fallback antigo)
  static Future<SubscriptionPlan> getCurrentPlan() async {
    try {
      final supabase = sb.Supabase.instance.client;
      String? shopId = await SessionService.getShopId();

      if (shopId == null) {
        final user = AuthService().currentUser;
        if (user != null) {
          try {
            final userDoc = await supabase
                .from('users')
                .select('shop_id')
                .eq('id', user.id)
                .maybeSingle();
            
            shopId = userDoc?['shop_id'];
            if (shopId != null) {
              await SessionService.saveShopId(shopId);
            }
          } catch (e) {
            debugPrint("getCurrentPlan fallback failed: $e");
          }
        }
      }

      if (shopId == null) return SubscriptionPlan.free;

      final doc = await supabase
          .from(_collection)
          .select()
          .eq('id', shopId)
          .maybeSingle();
      
      if (doc == null) return SubscriptionPlan.free;

      final data = doc;
      final sub = data['subscription'] as Map<String, dynamic>?;

      // 1. Verifica Novo Sistema de Trial (Prioridade se não houver assinatura paga ativa)
      final trialActive = data['trial_active'] == true;
      if (trialActive && sub != null) {
        final endStr = (sub['trial_end_date'] ?? sub['trial_ends_at'])?.toString();
        if (endStr != null) {
          final end = DateTime.parse(endStr);
          if (end.isAfter(DateTime.now())) {
            return _parsePlanId(_readPlanKey(sub));
          } else {
            await TrialService.checkAndDeactivateExpiredTrial();
          }
        }
      }

      // 2. Verifica Assinatura Stripe/Paga (subscription object)
      if (sub != null) {
        // Verifica Trial Clássico (legado no objeto sub)
        if (sub['status'] == 'trial') {
          final endsAtStr = sub['trial_ends_at']?.toString();
          if (endsAtStr != null) {
             final end = DateTime.parse(endsAtStr);
             if (end.isAfter(DateTime.now())) {
               return SubscriptionPlan.pro;
             }
          }
        }

        if (sub['status'] == 'active') {
          return _parsePlanId(_readPlanKey(sub));
        }
        
        if (sub['status'] == 'canceled' || sub['status'] == 'cancelled') {
           final accessUntilStr = sub['access_until']?.toString();
           if (accessUntilStr != null) {
             final accessUntil = DateTime.parse(accessUntilStr);
             if (accessUntil.isAfter(DateTime.now())) {
               return _parsePlanId(_readPlanKey(sub));
             }
           }
        }
      }

      // 3. Fallback final: plan_id na raiz (FK to plans table)
      final rootPlanId = data['plan_id'] as String?;
      if (rootPlanId != null && rootPlanId != 'free') {
        return _parsePlanId(rootPlanId);
      }

      return SubscriptionPlan.free;
    } catch (e) {
      debugPrint("getCurrentPlan error: $e");
      return SubscriptionPlan.free;
    }
  }

  static String? _readPlanKey(Map<String, dynamic> sub) {
    return sub['plan_id'] as String? ?? sub['plano'] as String?;
  }

  static SubscriptionPlan _parsePlanId(String? id) {
    if (id == null) return SubscriptionPlan.free;
    switch (id.toLowerCase()) {
      case 'start':
      case 'starter':
        return SubscriptionPlan.start;
      case 'plus':
        return SubscriptionPlan.plus;
      case 'pro':
        return SubscriptionPlan.pro;
      default:
        // Assume Free plan for completely unmatching identities
        return SubscriptionPlan.free;
    }
  }

  static String _getPlanId(SubscriptionPlan plan) => getPlanId(plan);

  /// Converte enum para string do plano (público)
  static String getPlanId(SubscriptionPlan plan) {
    if (plan == SubscriptionPlan.start) return 'starter';
    if (plan == SubscriptionPlan.plus) return 'plus';
    if (plan == SubscriptionPlan.pro) return 'pro';
    return 'free';
  }

  /// Verifica se pode adicionar mais funcionários
  static Future<bool> canAddEmployee(int currentCount) async {
    final plan = await getCurrentPlan();
    final limit = _plans[plan]!['employeeLimit'] as int;
    return currentCount < limit;
  }

  /// Verifica se pode usar pagamento online
  static Future<bool> canUseOnlinePayment() async {
    final plan = await getCurrentPlan();
    return _plans[plan]!['onlinePayment'] as bool;
  }

  /// Verifica acesso ao Módulo Financeiro
  static Future<bool> canAccessFinancial() async {
    final plan = await getCurrentPlan();
    return _plans[plan]!['financialModule'] as bool;
  }

  /// Verifica acesso ao Controle de Comissões
  static Future<bool> canAccessCommissions() async {
    final plan = await getCurrentPlan();
    return _plans[plan]!['commissionModule'] as bool;
  }

  /// Verifica acesso ao Estoque
  static Future<bool> canAccessInventory() async {
    final plan = await getCurrentPlan();
    return _plans[plan]!['inventoryModule'] as bool;
  }

  /// Verifica se pode ter Link Personalizado
  static Future<bool> canCustomizeLink() async {
    final plan = await getCurrentPlan();
    return _plans[plan]!['customLink'] as bool;
  }

  /// Verifica se pode adicionar mais clientes
  static Future<bool> canAddClient(int currentCount) async {
    final plan = await getCurrentPlan();
    final limit = _plans[plan]!['clientLimit'] as int;
    return currentCount < limit;
  }

  /// Retorna o plano de uma loja específica (sem depender de sessão do usuário logado).
  /// Usado pelo checkout para verificar o plano do DONO da loja, não do cliente.
  static Future<SubscriptionPlan> getShopPlan(String shopId) async {
    try {
      final supabase = sb.Supabase.instance.client;
      final doc = await supabase
          .from(_collection)
          .select()
          .eq('id', shopId)
          .maybeSingle();

      if (doc == null) return SubscriptionPlan.free;
      final data = doc;
      final sub = data['subscription'] as Map<String, dynamic>?;

      // 1. Verifica Novo Sistema de Trial
      final trialActive = data['trial_active'] == true;
      if (trialActive && sub != null) {
        final endStr = (sub['trial_end_date'] ?? sub['trial_ends_at'])?.toString();
        if (endStr != null) {
          final end = DateTime.parse(endStr);
          if (end.isAfter(DateTime.now())) {
            return _parsePlanId(_readPlanKey(sub));
          } else {
            await TrialService.checkAndDeactivateExpiredTrial();
          }
        }
      }

      // 2. Verifica Assinatura
      if (sub != null) {
        // Legado: trial clássico
        if (sub['status'] == 'trial') {
          final endsAtStr = sub['trial_ends_at']?.toString();
          if (endsAtStr != null) {
             final end = DateTime.parse(endsAtStr);
             if (end.isAfter(DateTime.now())) {
               return SubscriptionPlan.pro;
             }
          }
        }

        // Assinatura cancelada
        if (sub['status'] == 'canceled' || sub['status'] == 'cancelled') {
          final accessUntilStr = sub['access_until']?.toString();
          if (accessUntilStr != null) {
            final accessUntil = DateTime.parse(accessUntilStr);
            if (accessUntil.isAfter(DateTime.now())) {
              return _parsePlanId(_readPlanKey(sub));
            }
          }
        } else {
          // Ativa ou outros status que concedem plano
          final planFromSub = _parsePlanId(_readPlanKey(sub));
          if (planFromSub != SubscriptionPlan.free) return planFromSub;
        }
      }

      // 3. Fallback final: plan_id na raiz (FK to plans table)
      final rootPlanId = data['plan_id'] as String?;
      return _parsePlanId(rootPlanId);
    } catch (e) {
      debugPrint('getShopPlan error: $e');
      return SubscriptionPlan.free;
    }
  }

  /// Verifica se o plano fornecido suporta pagamento online (PIX/cartão).
  static bool planSupportsOnlinePayment(SubscriptionPlan plan) {
    return _plans[plan]!['onlinePayment'] as bool;
  }

  /// Verifica se pode acessar relatórios avançados
  static Future<bool> canAccessReports() async {
    return await canAccessFinancial();
  }

  /// Verifica se pode adicionar mais fotos de serviço
  static Future<bool> canAddServicePhoto(int currentCount) async {
    final plan = await getCurrentPlan();
    final limit = _plans[plan]!['maxServicePhotos'] as int;
    return currentCount < limit;
  }

  /// Verifica se pode usar configurações avançadas de agenda
  static Future<bool> canUseAdvancedScheduling() async {
    final plan = await getCurrentPlan();
    return _plans[plan]!['advancedScheduling'] as bool;
  }

  /// Verifica se deve exibir anúncios
  static Future<bool> hasAds() async {
    final plan = await getCurrentPlan();
    return _plans[plan]!['adEnabled'] as bool;
  }

  /// Verifica se pode customizar a página (cores, capa, etc)
  static Future<bool> canCustomizePage() async {
    return await canCustomizeLink();
  }

  /// Retorna detalhes do plano para UI
  static Map<String, dynamic> getPlanDetails(SubscriptionPlan plan) {
    return _plans[plan]!;
  }

  /// Inicia o fluxo de assinatura, upgrade ou downgrade de plano.
  static Future<bool> startPurchaseFlow(
      BuildContext context, SubscriptionPlan plan) async {
    final planDetails = _plans[plan]!;
    final planPrice = (planDetails['price'] as num).toDouble();
    final planName = planDetails['name'] as String;
    final planId = _getPlanId(plan);

    // Busca shopId
    String? shopId = await SessionService.getShopId();
    if (shopId == null) {
      final user = AuthService().currentUser;
      if (user != null) {
        final supabase = sb.Supabase.instance.client;
        final userDoc = await supabase
            .from('users')
            .select('shop_id')
            .eq('id', user.id)
            .maybeSingle();
        shopId = userDoc?['shop_id'];
        if (shopId != null) await SessionService.saveShopId(shopId);
      }
    }
    if (shopId == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Não foi possível identificar sua loja.'),
          backgroundColor: Colors.red,
        ));
      }
      return false;
    }

    // Detecta plano atual e status de trial
    final supabase = sb.Supabase.instance.client;
    final doc = await supabase.from(_collection).select().eq('id', shopId).maybeSingle();
    final shopData = doc;
    final isTrial = shopData?['trial_active'] == true;
    
    final currentPlan = await getCurrentPlan();
    final currentPlanPrice = (_plans[currentPlan]!['price'] as num).toDouble();
    final isCurrentlyPaid = currentPlanPrice > 0 && !isTrial;

    // ── CENÁRIO 1: downgrade para FREE (cancelamento) ────────────────
    if (planPrice <= 0) {
      if (!context.mounted) return false;
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.warning_amber, color: Colors.orange),
              SizedBox(width: 8),
              Text('Fazer Downgrade?'),
            ],
          ),
          content: Text(
            isCurrentlyPaid
                ? 'Ao fazer downgrade para o plano gratuito, sua assinatura será cancelada '
                    'e você manterá acesso ao plano atual até o fim do período já pago.'
                : 'Deseja ativar o plano gratuito?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  foregroundColor: Colors.white),
              child: const Text('Confirmar Downgrade'),
            ),
          ],
        ),
      );
      if (confirm != true || !context.mounted) return false;

      if (isCurrentlyPaid) {
        // Cancela assinatura no Stripe e mantém acesso até fim do período
        return await cancelSubscription(context: context, shopId: shopId);
      } else {
        // Estava no free ou trial, ativa free diretamente
        await _ativarPlanoGratuito(
            context: context, planId: planId, planName: planName);
        return true;
      }
    }

    // ── CENÁRIO 2: Upgrade durante TRIAL ──────────────────────────────
    if (isTrial) {
      if (!context.mounted) return false;
      
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.info_outline, color: AppColors.primaryPurple),
              SizedBox(width: 8),
              Text('Ativar Assinatura?'),
            ],
          ),
          content: Text(
            'Você está em período de teste gratuito. Ao assinar o plano $planName agora, '
            'seu período de teste será encerrado e iniciaremos sua assinatura paga.\n\n'
            'Valor: R\$ ${planPrice.toStringAsFixed(2).replaceAll(".", ",")}/mês.'
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Voltar'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryPurple,
                foregroundColor: Colors.white,
              ),
              child: const Text('Confirmar e Assinar'),
            ),
          ],
        ),
      );
      if (confirm != true || !context.mounted) return false;

      // Desativa trial antes ou durante a assinatura? 
      // O melhor é deixar a ativação da assinatura sobrescrever o trial no backend via webhook do stripe,
      // mas aqui vamos tratar como uma "Nova Assinatura".
      return await _iniciarPagamentoAssinatura(
        context: context,
        shopId: shopId,
        planId: planId,
        planName: planName,
        planPrice: planPrice,
      );
    }

    // ── CENÁRIO 3: upgrade ou downgrade entre planos pagos ativos ───────────
    if (isCurrentlyPaid && currentPlan != plan) {
      if (!context.mounted) return false;
      final isUpgrade = planPrice > currentPlanPrice;
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Row(
            children: [
              Icon(isUpgrade ? Icons.rocket_launch : Icons.arrow_downward,
                  color: isUpgrade ? Colors.purple : Colors.orange),
              const SizedBox(width: 8),
              Text(isUpgrade ? 'Fazer Upgrade?' : 'Fazer Downgrade?'),
            ],
          ),
          content: Text(
            isUpgrade
                ? 'Você será cobrado proporcionalmente (pro-rata) pela diferença '
                    'até o fim do ciclo atual e depois R\$ ${planPrice.toStringAsFixed(2).replaceAll(".", ",")}/mês.'
                : 'Seu plano será reduzido para $planName. O crédito restante '
                    'será aplicado proporcionalmente no novo valor.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: isUpgrade ? Colors.purple : Colors.orange,
                foregroundColor: Colors.white,
              ),
              child:
                  Text(isUpgrade ? 'Confirmar Upgrade' : 'Confirmar Downgrade'),
            ),
          ],
        ),
      );
      if (confirm != true || !context.mounted) return false;

      return await upgradeSubscription(
        context: context,
        shopId: shopId,
        newPlanId: planId,
        newPlanName: planName,
        newPlanPrice: planPrice,
      );
    }

    // ── CENÁRIO 3: novo assinante (Free/Trial → Plano Pago) ──────────
    if (!context.mounted) return false;
    return await _iniciarPagamentoAssinatura(
      context: context,
      shopId: shopId,
      planId: planId,
      planName: planName,
      planPrice: planPrice,
    );
  }

  /// Chama o StripeService para ativar o plano via Payment Sheet Nativo.
  static Future<bool> _iniciarPagamentoAssinatura({
    required BuildContext context,
    required String shopId,
    required String planId,
    required String planName,
    required double planPrice,
  }) async {
    try {
      final user = AuthService().currentUser;
      if (user == null || user.email == null) {
        throw Exception("Usuário não autenticado ou sem e-mail.");
      }

      // Verifica se há sessão ativa antes de exibir o loading
      final currentSession = sb.Supabase.instance.client.auth.currentSession;
      if (currentSession == null) {
        if (context.mounted) {
          PremiumDialogs.showError(context,
              "Sua sessão expirou. Por favor, saia do aplicativo e faça login novamente para continuar.");
        }
        return false;
      }

      PremiumDialogs.showLoading(context, "Preparando seu novo ambiente...");

      // Garante que o JWT está atualizado antes de chamar a Edge Function do Stripe
      try {
        await sb.Supabase.instance.client.auth.refreshSession();
      } catch (refreshErr) {
        debugPrint('_iniciarPagamentoAssinatura: refresh session falhou ($refreshErr)');
        if (context.mounted) PremiumDialogs.hideLoading(context);
        if (context.mounted) {
          PremiumDialogs.showError(context,
              "Sua sessão expirou. Por favor, saia do aplicativo e faça login novamente para continuar.");
        }
        return false;
      }

      final success = await StripeService.instance.setupSubscriptionPayment(
        planId: planId,
        shopId: shopId,
        customerEmail: user.email!,
      );

      if (context.mounted) PremiumDialogs.hideLoading(context);

      if (success && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Sensacional! Sua marca agora é Premium. 🚀"),
            backgroundColor: AppColors.successGreen,
          ),
        );
        return true;
      } else if (!success && context.mounted) {
        // O StripeService já logou o erro
      }
      return success;
    } catch (e) {
      if (context.mounted) PremiumDialogs.hideLoading(context);
      debugPrint("_iniciarPagamentoAssinatura error: $e");
      if (context.mounted) {
        if (e.toString().contains('401') || e.toString().contains('Invalid JWT')) {
          PremiumDialogs.showError(
              context, "Sua sessão expirou por segurança. Por favor, saia do aplicativo (Logout) e faça login novamente para prosseguir com o pagamento.");
        } else {
          PremiumDialogs.showError(
              context, "Não conseguimos iniciar seu serviço agora: $e");
        }
      }
      return false;
    }
  }

  /// Ativa plano gratuito diretamente no Supabase, sem cobrança.
  static Future<void> _ativarPlanoGratuito({
    required BuildContext context,
    required String planId,
    required String planName,
  }) async {
    String? shopId = await SessionService.getShopId();
    if (shopId == null) {
      final user = sb.Supabase.instance.client.auth.currentUser;
      if (user != null) {
        final userDoc = await sb.Supabase.instance.client
            .from('users')
            .select('shop_id')
            .eq('id', user.id)
            .maybeSingle();
        shopId = userDoc?['shop_id'];
        if (shopId != null) await SessionService.saveShopId(shopId);
      }
    }

    if (shopId != null) {
      final supabase = sb.Supabase.instance.client;
      await supabase
          .from(_collection)
          .update({
        'plan_id': planId,
        'trial_active': false,
        'subscription': {
          'plan': 'free',
          'status': 'active',
          'plan_id': null,
          'trial_used': true,
          'billing_cycle': null,
          'updated_at': DateTime.now().toIso8601String(),
        },
      }).eq('id', shopId);

      // Atualiza também na tabela users (para sincronia do auth profile, se aplicável ao dono logado)
      final user = sb.Supabase.instance.client.auth.currentUser;
      if (user != null) {
        try {
          await supabase.from('users').update({'plan': planId}).eq('id', user.id);
        } catch (e) {
          debugPrint('Aviso: Falha ao atualizar plano na tabela users: $e');
        }
      }

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Plano $planName ativado!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } else {
      debugPrint("shopId is NULL. Cannot activate free plan.");
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Erro: Não foi possível identificar sua loja."),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Cancela a assinatura. Acesso mantido até fim do período atual.
  static Future<bool> cancelSubscription({
    required BuildContext context,
    required String shopId,
    String? reason,
  }) async {
    try {
      final supabase = sb.Supabase.instance.client;
      final body = {'shop_id': shopId};
      if (reason != null) {
        body['reason'] = reason;
      }
      final response = await supabase.functions.invoke('cancel-subscription', body: body);
      
      final success = response.status == 200;
      final data = response.data is Map<String, dynamic> ? response.data as Map<String, dynamic> : null;

      if (success && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(data?['message'] ?? 'Assinatura cancelada.'),
            backgroundColor: Colors.orange,
          ),
        );
      } else if (!success && context.mounted) {
        final errMsg = data?['error'] ?? 'Erro ao cancelar assinatura.';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(errMsg.toString()), backgroundColor: Colors.red),
        );
      }
      return success;
    } catch (e) {
      debugPrint('cancelSubscription error: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao cancelar: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return false;
    }
  }

  /// Faz upgrade de plano com crédito pro-rata calculado pelo backend.
  static Future<bool> upgradeSubscription({
    required BuildContext context,
    required String shopId,
    required String newPlanId,
    required String newPlanName,
    required double newPlanPrice,
  }) async {
    try {
      final supabase = sb.Supabase.instance.client;

      // Verifica sessão ativa antes de prosseguir
      final currentSession = supabase.auth.currentSession;
      if (currentSession == null) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Sua sessão expirou. Por favor, saia do aplicativo e faça login novamente.'),
            backgroundColor: Colors.red,
          ));
        }
        return false;
      }

      // Garante que o JWT está atualizado antes de chamar a Edge Function
      try {
        await supabase.auth.refreshSession();
      } catch (refreshErr) {
        debugPrint('upgradeSubscription: refresh session falhou ($refreshErr)');
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Sua sessão expirou. Por favor, saia do aplicativo e faça login novamente.'),
            backgroundColor: Colors.red,
          ));
        }
        return false;
      }

      final response = await supabase.functions.invoke('upgrade-subscription', body: {
        'shop_id': shopId,
        'new_plan_id': newPlanId,
        'new_plan_name': newPlanName,
        'new_plan_price': newPlanPrice,
      });

      final success = response.status == 200;
      final data = response.data is Map<String, dynamic> ? response.data as Map<String, dynamic> : null;

      if (success && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(data?['message'] ?? 'Plano atualizado!'),
            backgroundColor: Colors.green,
          ),
        );
      } else if (!success && context.mounted) {
        final errMsg = data?['error'] ?? 'Erro ao atualizar plano.';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(errMsg.toString()), backgroundColor: Colors.red),
        );
      }
      return success;
    } catch (e) {
      debugPrint('upgradeSubscription error: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao atualizar plano. Tente novamente.'), backgroundColor: Colors.red),
        );
      }
      return false;
    }
  }

  /// Agenda downgrade de plano para o próximo ciclo de cobrança.
  static Future<bool> scheduleDowngrade({
    required BuildContext context,
    required String shopId,
    required String newPlanId,
    String? newPlanName,
  }) async {
    try {
      final supabase = sb.Supabase.instance.client;
      final response = await supabase.functions.invoke('downgrade-subscription', body: {
        'shop_id': shopId,
        'new_plan_id': newPlanId,
        'new_plan_name': newPlanName ?? newPlanId,
      });

      final success = response.status == 200;
      final data = response.data is Map<String, dynamic> ? response.data as Map<String, dynamic> : null;

      if (success && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(data?['message'] ?? 'Downgrade agendado.'),
            backgroundColor: Colors.blue,
          ),
        );
      } else if (!success && context.mounted) {
        final errMsg = data?['error'] ?? 'Erro ao agendar downgrade.';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(errMsg.toString()), backgroundColor: Colors.red),
        );
      }
      return success;
    } catch (e) {
      debugPrint('scheduleDowngrade error: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao agendar downgrade: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return false;
    }
  }

  /// Reativa assinatura cancelada ou com downgrade pendente.
  static Future<bool> reactivateSubscription({
    required BuildContext context,
    required String shopId,
    String? planId,
    String? planName,
  }) async {
    try {
      final supabase = sb.Supabase.instance.client;
      final response = await supabase.functions.invoke('reactivate-subscription', body: {
        'shop_id': shopId,
        if (planId != null) 'new_plan_id': planId,
        if (planName != null) 'new_plan_name': planName,
      });

      final success = response.status == 200;
      final data = response.data is Map<String, dynamic> ? response.data as Map<String, dynamic> : null;

      if (success && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text(data?['message'] ?? 'Assinatura reativada! 🚀'),
            backgroundColor: Colors.green,
          ),
        );
      } else if (!success && context.mounted) {
        final errMsg = data?['error'] ?? 'Erro ao reativar assinatura.';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(errMsg.toString()), backgroundColor: Colors.red),
        );
      }
      return success;
    } catch (e) {
      debugPrint('reactivateSubscription error: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao reativar: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return false;
    }
  }
}
