import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../../core/services/session_service.dart';
import 'trial_service.dart';
import '../../core/services/stripe_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/premium_dialogs.dart';

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
      'adEnabled': true,
      'onlinePayment': false,
      'financialModule': false,
      'commissionModule': false,
      'inventoryModule': false,
      'customLink': false,
      'maxServicePhotos': 1,
      'advancedScheduling': false,
      'features': ['scheduling', 'ads'],
      'description': 'Ideal para conhecer a plataforma.',
    },
    SubscriptionPlan.start: {
      'name': 'Start',
      'price': 29.90,
      'employeeLimit': 3,
      'clientLimit': 500,
      'adEnabled': false,
      'onlinePayment': false,
      'financialModule': false,
      'commissionModule': false,
      'inventoryModule': false,
      'customLink': true,
      'maxServicePhotos': 3,
      'advancedScheduling': false,
      'features': ['scheduling', 'custom_link'],
      'description': 'Perfeito para autônomos.',
    },
    SubscriptionPlan.plus: {
      'name': 'Plus',
      'price': 59.90,
      'employeeLimit': 5,
      'clientLimit': 999999,
      'adEnabled': false,
      'onlinePayment': true,
      'financialModule': true,
      'commissionModule': false,
      'inventoryModule': true,
      'customLink': true,
      'maxServicePhotos': 5,
      'advancedScheduling': true,
      'features': ['scheduling', 'financial'],
      'description': 'Gestão completa com pagamentos online.',
    },
    SubscriptionPlan.pro: {
      'name': 'Pro',
      'price': 99.90,
      'employeeLimit': 15,
      'clientLimit': 999999,
      'adEnabled': false,
      'onlinePayment': true,
      'financialModule': true,
      'commissionModule': true,
      'inventoryModule': true,
      'customLink': true,
      'maxServicePhotos': 10,
      'advancedScheduling': true,
      'features': ['all'],
      'description': 'Recursos ilimitados para o seu negócio.',
    },
  };

  /// Retorna o plano atual da loja logada
  static Future<SubscriptionPlan> getCurrentPlan() async {
    try {
      String? shopId = await SessionService.getShopId();

      if (shopId == null) {
        final user = FirebaseAuth.instance.currentUser;
        if (user != null) {
          try {
            final userDoc = await FirebaseFirestore.instance
                .collection('users')
                .doc(user.uid)
                .get();
            shopId = userDoc.data()?['shopId'];
            if (shopId != null) {
              await SessionService.saveShopId(shopId);
            }
          } catch (e) {
            debugPrint("getCurrentPlan fallback failed: $e");
          }
        }
      }

      if (shopId == null) return SubscriptionPlan.start;

      final doc = await FirebaseFirestore.instance
          .collection(_collection)
          .doc(shopId)
          .get();
      if (!doc.exists) return SubscriptionPlan.start;

      final data = doc.data();
      final sub = data?['subscription'] as Map<String, dynamic>?;

      if (sub == null) {
        // Se a assinatura não existe, verifica o novo Sistema de Trial
        final trialStatus = await TrialService.getTrialStatus();
        if (trialStatus['trialActive'] == true) {
          return _parsePlanId(trialStatus['trialPlan']);
        }
        if (trialStatus['trialExpired'] == true) {
          await TrialService.checkAndDeactivateExpiredTrial(); // Lazy check
        }
        return SubscriptionPlan.start;
      }

      // Verifica Trial Clássico (legado)
      if (sub['status'] == 'trial') {
        final end = (sub['trial_ends_at'] as Timestamp?)?.toDate();
        if (end != null && end.isAfter(DateTime.now())) {
          return SubscriptionPlan.pro; // Trial dá acesso total
        }
      }

      final planId = sub['plan_id'] as String?;
      return _parsePlanId(planId);
    } catch (e) {
      return SubscriptionPlan.start;
    }
  }

  static SubscriptionPlan _parsePlanId(String? id) {
    switch (id) {
      case 'start':
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
    if (plan == SubscriptionPlan.start) return 'start';
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
      final doc = await FirebaseFirestore.instance
          .collection(_collection)
          .doc(shopId)
          .get();
      if (!doc.exists) return SubscriptionPlan.start;
      final data = doc.data();
      final sub = data?['subscription'] as Map<String, dynamic>?;

      if (sub == null) {
        // Se a assinatura não existe, verifica o novo Sistema de Trial
        final trialActive = data?['trial_active'] == true;
        if (trialActive) {
          Timestamp? end = data?['trial_end_date'];
          if (end != null && end.toDate().isAfter(DateTime.now())) {
            return _parsePlanId(data?['trial_plan'] as String?);
          } else if (end != null) {
            // Expirou
            await TrialService.checkAndDeactivateExpiredTrial();
          }
        }
        // Fallback: verifica campos plan/plan_id na raiz do documento
        // (salvos por upgradeSubscription e reactivateSubscription)
        final rootPlanId =
            (data?['plan'] as String?) ?? (data?['plan_id'] as String?);
        if (rootPlanId != null && rootPlanId != 'free') {
          return _parsePlanId(rootPlanId);
        }
        return SubscriptionPlan.start;
      }

      // Legado: trial clássico
      if (sub['status'] == 'trial') {
        final end = (sub['trial_ends_at'] as Timestamp?)?.toDate();
        if (end != null && end.isAfter(DateTime.now())) {
          return SubscriptionPlan.pro;
        }
      }

      // Assinatura cancelada: verificar se ainda está dentro do período de acesso
      if (sub['status'] == 'canceled' || sub['status'] == 'cancelled') {
        final accessUntil = (sub['access_until'] as Timestamp?)?.toDate();
        if (accessUntil != null && accessUntil.isAfter(DateTime.now())) {
          // Ainda tem acesso — retorna plano salvo
          return _parsePlanId(sub['plan_id'] as String?);
        }
        // Acesso expirado após cancelamento
        return SubscriptionPlan.start;
      }

      // Plano ativo: usa plan_id do subscription, com fallback para raiz do documento
      final planFromSub = _parsePlanId(sub['plan_id'] as String?);
      if (planFromSub != SubscriptionPlan.start) return planFromSub;

      // Fallback final: campo plan/plan_id na raiz (set por algunas Cloud Functions)
      final rootPlanId =
          (data?['plan'] as String?) ?? (data?['plan_id'] as String?);
      return _parsePlanId(rootPlanId);
    } catch (e) {
      debugPrint('getShopPlan error: $e');
      return SubscriptionPlan.start;
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
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();
        shopId = userDoc.data()?['shopId'];
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

    // Detecta plano atual
    final currentPlan = await getCurrentPlan();
    final currentPlanPrice = (_plans[currentPlan]!['price'] as num).toDouble();
    final isCurrentlyPaid = currentPlanPrice > 0;

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

    // ── CENÁRIO 2: upgrade ou downgrade entre planos pagos ───────────
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
      final user = FirebaseAuth.instance.currentUser;
      if (user == null || user.email == null) {
        throw Exception("Usuário não autenticado ou sem e-mail.");
      }

      PremiumDialogs.showLoading(context, "Preparando seu novo ambiente...");

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
        PremiumDialogs.showError(
            context, "Não conseguimos iniciar seu sucesso agora: $e");
      }
      return false;
    }
  }

  /// Ativa plano gratuito diretamente no Firestore, sem cobrança.
  static Future<void> _ativarPlanoGratuito({
    required BuildContext context,
    required String planId,
    required String planName,
  }) async {
    String? shopId = await SessionService.getShopId();
    if (shopId == null) {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();
        shopId = userDoc.data()?['shopId'];
        if (shopId != null) await SessionService.saveShopId(shopId);
      }
    }

    if (shopId != null) {
      await FirebaseFirestore.instance
          .collection(_collection)
          .doc(shopId)
          .update({
        'subscription': {
          'plan_id': planId,
          'status': 'active',
          'billing_cycle': null,
          'updated_at': FieldValue.serverTimestamp(),
        }
      });

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

  /// TESTE 12 — Cancela a assinatura. Acesso mantido até fim do período atual.
  static Future<bool> cancelSubscription({
    required BuildContext context,
    required String shopId,
  }) async {
    try {
      final callable =
          FirebaseFunctions.instance.httpsCallable('cancelSubscription');
      final result = await callable.call({'shopId': shopId});
      final success = result.data?['success'] == true;
      if (success && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.data?['message'] ?? 'Assinatura cancelada.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return success;
    } on FirebaseFunctionsException catch (e) {
      debugPrint('cancelSubscription error: ${e.code} - ${e.message}');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao cancelar: ${e.message}'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return false;
    } catch (e) {
      debugPrint('cancelSubscription error: $e');
      return false;
    }
  }

  /// TESTE 10 — Faz upgrade de plano com crédito pro-rata calculado pelo backend.
  static Future<bool> upgradeSubscription({
    required BuildContext context,
    required String shopId,
    required String newPlanId,
    required String newPlanName,
    required double newPlanPrice,
  }) async {
    try {
      final callable =
          FirebaseFunctions.instance.httpsCallable('upgradeSubscription');
      final result = await callable.call({
        'shopId': shopId,
        'newPlanId': newPlanId,
        'newPlanName': newPlanName,
        'newPlanPrice': newPlanPrice,
      });
      final success = result.data?['success'] == true;
      if (success && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.data?['message'] ?? 'Plano atualizado!'),
            backgroundColor: Colors.green,
          ),
        );
      }
      return success;
    } on FirebaseFunctionsException catch (e) {
      debugPrint('upgradeSubscription error: ${e.code} - ${e.message}');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro no upgrade: ${e.message}'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return false;
    } catch (e) {
      debugPrint('upgradeSubscription error: $e');
      return false;
    }
  }

  /// TESTE 11 — Agenda downgrade de plano para o próximo ciclo de cobrança.
  static Future<bool> scheduleDowngrade({
    required BuildContext context,
    required String shopId,
    required String newPlanId,
    String? newPlanName,
  }) async {
    try {
      final callable =
          FirebaseFunctions.instance.httpsCallable('downgradeSubscription');
      final result = await callable.call({
        'shopId': shopId,
        'newPlanId': newPlanId,
        'newPlanName': newPlanName ?? newPlanId,
      });
      final success = result.data?['success'] == true;
      if (success && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.data?['message'] ?? 'Downgrade agendado.'),
            backgroundColor: Colors.blue,
          ),
        );
      }
      return success;
    } on FirebaseFunctionsException catch (e) {
      debugPrint('scheduleDowngrade error: ${e.code} - ${e.message}');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao agendar downgrade: ${e.message}'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return false;
    } catch (e) {
      debugPrint('scheduleDowngrade error: $e');
      return false;
    }
  }

  /// TESTE 13 — Reativa assinatura cancelada ou com downgrade pendente.
  static Future<bool> reactivateSubscription({
    required BuildContext context,
    required String shopId,
    String? planId,
    String? planName,
  }) async {
    try {
      final callable =
          FirebaseFunctions.instance.httpsCallable('reactivateSubscription');
      final result = await callable.call({
        'shopId': shopId,
        if (planId != null) 'planId': planId,
        if (planName != null) 'planName': planName,
      });
      final success = result.data?['success'] == true;
      if (success && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text(result.data?['message'] ?? 'Assinatura reativada! ðŸš€'),
            backgroundColor: Colors.green,
          ),
        );
      }
      return success;
    } on FirebaseFunctionsException catch (e) {
      debugPrint('reactivateSubscription error: ${e.code} - ${e.message}');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao reativar: ${e.message}'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return false;
    } catch (e) {
      debugPrint('reactivateSubscription error: $e');
      return false;
    }
  }
}
