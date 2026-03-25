import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;
import '../../core/services/session_service.dart';
import 'trial_service.dart';
import '../../core/services/stripe_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/premium_dialogs.dart';
import '../../core/services/auth_service.dart';

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
      'customLink': false,
      'maxServicePhotos': 1,
      'advancedScheduling': false,
      'features': ['scheduling'],
      'description': 'Ideal para conhecer a plataforma.',
    },
    SubscriptionPlan.start: {
      'name': 'Start',
      'price': 29.90,
      'employeeLimit': 2,
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
      'description': 'Perfeito para autônomos que estão começando.',
    },
    SubscriptionPlan.plus: {
      'name': 'Plus',
      'price': 59.90,
      'employeeLimit': 3,
      'clientLimit': 999999,
      'adEnabled': false,
      'onlinePayment': true,
      'financialModule': false,
      'commissionModule': true,
      'inventoryModule': true,
      'customLink': true,
      'maxServicePhotos': 5,
      'advancedScheduling': true,
      'features': [
        'Gestão de Estoque',
        'Cupons de Desconto',
        'Reajuste Automático de Valores',
        'Classificação de Clientes (VIP)',
        'Automações de Marketing'
      ],
      'description': 'Gestão completa com automações e estoque.',
    },
    SubscriptionPlan.pro: {
      'name': 'Pro',
      'price': 99.90,
      'employeeLimit': 5,
      'clientLimit': 999999,
      'adEnabled': false,
      'onlinePayment': true,
      'financialModule': true,
      'commissionModule': true,
      'inventoryModule': true,
      'customLink': true,
      'maxServicePhotos': 5,
      'advancedScheduling': true,
      'features': ['Painel Financeiro Completo (DRE/Caixa)', 'Todas as funções liberadas'],
      'description': 'Recursos ilimitados para o seu negócio.',
    },
  };

  /// Retorna o plano atual da loja logada
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
            return _parsePlanId(sub['plan_id'] as String?);
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
          return _parsePlanId(sub['plan_id'] as String?);
        }
        
        if (sub['status'] == 'canceled' || sub['status'] == 'cancelled') {
           final accessUntilStr = sub['access_until']?.toString();
           if (accessUntilStr != null) {
             final accessUntil = DateTime.parse(accessUntilStr);
             if (accessUntil.isAfter(DateTime.now())) {
               return _parsePlanId(sub['plan_id'] as String?);
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
            return _parsePlanId(sub['plan_id'] as String?);
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
              return _parsePlanId(sub['plan_id'] as String?);
            }
          }
        } else {
          // Ativa ou outros status que concedem plano
          final planFromSub = _parsePlanId(sub['plan_id'] as String?);
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
      BuildContext context, SubscriptionPlan plan, {
        String? affiliateId,
        String? affiliateCouponCode,
        String? commissionType,
      }) async {
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
        affiliateId: affiliateId,
        affiliateCouponCode: affiliateCouponCode,
        commissionType: commissionType,
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
      affiliateId: affiliateId,
      affiliateCouponCode: affiliateCouponCode,
      commissionType: commissionType,
    );
  }

  /// Chama o StripeService para ativar o plano via Payment Sheet Nativo.
  static Future<bool> _iniciarPagamentoAssinatura({
    required BuildContext context,
    required String shopId,
    required String planId,
    required String planName,
    required double planPrice,
    String? affiliateId,
    String? affiliateCouponCode,
    String? commissionType,
  }) async {
    try {
      final user = AuthService().currentUser;
      if (user == null || user.email == null) {
        throw Exception("Usuário não autenticado ou sem e-mail.");
      }

      PremiumDialogs.showLoading(context, "Preparando seu novo ambiente...");

      final success = await StripeService.instance.setupSubscriptionPayment(
        planId: planId,
        shopId: shopId,
        customerEmail: user.email!,
        affiliateId: affiliateId,
        affiliateCouponCode: affiliateCouponCode,
        commissionType: commissionType,
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
        PremiumDialogs.showError(
            context, "Não conseguimos iniciar seu sucesso agora: $e");
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
  }) async {
    try {
      final supabase = sb.Supabase.instance.client;
      final response = await supabase.functions.invoke('cancel-subscription', body: {'shop_id': shopId});
      
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
          SnackBar(
            content: Text('Erro no upgrade: $e'),
            backgroundColor: Colors.red,
          ),
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
