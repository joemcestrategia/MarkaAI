import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../../core/services/session_service.dart';

enum SubscriptionPlan { free, starter, pro, vip }

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
      'customLink': true,
      'maxServicePhotos': 1,
      'advancedScheduling': false,
      'features': ['scheduling', 'custom_link', 'ads'],
      'description': 'Ideal para começar.',
    },
    SubscriptionPlan.starter: {
      'name': 'Starter',
      'price': 29.90,
      'employeeLimit': 3,
      'clientLimit': 100,
      'adEnabled': false,
      'onlinePayment': true,
      'financialModule': false,
      'commissionModule': false,
      'inventoryModule': false,
      'customLink': true,
      'maxServicePhotos': 5,
      'advancedScheduling': true,
      'features': ['online_payment', 'custom_link', 'no_ads'],
      'description': 'Mais recursos e equipe pequena.',
    },
    SubscriptionPlan.pro: {
      'name': 'Pro',
      'price': 59.90,
      'employeeLimit': 5,
      'clientLimit': 999999,
      'adEnabled': false,
      'onlinePayment': true,
      'financialModule': true,
      'commissionModule': true,
      'inventoryModule': false,
      'customLink': true,
      'maxServicePhotos': 5,
      'advancedScheduling': true,
      'features': ['all'],
      'description': 'Gestão completa com Financeiro.',
    },
    SubscriptionPlan.vip: {
      'name': 'VIP',
      'price': 99.90,
      'employeeLimit': 10,
      'clientLimit': 999999,
      'adEnabled': false,
      'onlinePayment': true,
      'financialModule': true,
      'commissionModule': true,
      'inventoryModule': true,
      'customLink': true,
      'maxServicePhotos': 5,
      'advancedScheduling': true,
      'features': ['all'],
      'description': 'Para grandes equipes. Até 10 profissionais.',
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

      if (shopId == null) return SubscriptionPlan.free;

      final doc = await FirebaseFirestore.instance
          .collection(_collection)
          .doc(shopId)
          .get();
      if (!doc.exists) return SubscriptionPlan.free;

      final data = doc.data();
      final sub = data?['subscription'] as Map<String, dynamic>?;

      if (sub == null) return SubscriptionPlan.free;

      // Verifica Trial
      if (sub['status'] == 'trial') {
        final end = (sub['trial_ends_at'] as Timestamp?)?.toDate();
        if (end != null && end.isAfter(DateTime.now())) {
          return SubscriptionPlan.vip; // Trial dá acesso total
        }
      }

      final planId = sub['plan_id'] as String?;
      return _parsePlanId(planId);
    } catch (e) {
      return SubscriptionPlan.free;
    }
  }

  static SubscriptionPlan _parsePlanId(String? id) {
    switch (id) {
      // IDs legados (antigos)
      case 'starter':
        return SubscriptionPlan.starter;
      case 'pro':
        return SubscriptionPlan.pro;
      case 'vip':
        return SubscriptionPlan.vip;
      // IDs Firestore (seedados via seedPlans: start/flex/plus/prime)
      case 'start':
        return SubscriptionPlan.starter;
      case 'flex':
        return SubscriptionPlan.starter;
      case 'plus':
        return SubscriptionPlan.pro;
      case 'prime':
        return SubscriptionPlan.vip;
      default:
        return SubscriptionPlan.free;
    }
  }

  static String _getPlanId(SubscriptionPlan plan) {
    if (plan == SubscriptionPlan.starter) return 'starter';
    if (plan == SubscriptionPlan.pro) return 'pro';
    if (plan == SubscriptionPlan.vip) return 'vip';
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
      if (!doc.exists) return SubscriptionPlan.free;
      final data = doc.data();
      final sub = data?['subscription'] as Map<String, dynamic>?;
      if (sub == null) return SubscriptionPlan.free;
      if (sub['status'] == 'trial') {
        final end = (sub['trial_ends_at'] as Timestamp?)?.toDate();
        if (end != null && end.isAfter(DateTime.now())) {
          return SubscriptionPlan.vip;
        }
      }
      return _parsePlanId(sub['plan_id'] as String?);
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

  /// CORREÇÃO 4: Inicia o fluxo de assinatura de um plano.
  /// Planos pagos requerem Mercado Pago conectado e cobram via Cloud Function.
  /// Plano gratuito é ativado diretamente no Firestore.
  static Future<bool> startPurchaseFlow(
      BuildContext context, SubscriptionPlan plan) async {
    final planDetails = _plans[plan]!;
    final planPrice = (planDetails['price'] as num).toDouble();
    final planName = planDetails['name'] as String;
    final planId = _getPlanId(plan);

    // Plano gratuito: ativar diretamente, sem cobrança
    if (planPrice <= 0) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text("Confirmar Plano Gratuito"),
          content: Text("Deseja ativar o plano '$planName'?"),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text("Cancelar"),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green, foregroundColor: Colors.white),
              child: const Text("Confirmar"),
            ),
          ],
        ),
      );
      if (confirm == true && context.mounted) {
        await _ativarPlanoGratuito(
            context: context, planId: planId, planName: planName);
        return true;
      }
      return false;
    }

    // PLANO PAGO: requer Mercado Pago configurado
    String? shopId = await SessionService.getShopId();
    if (shopId == null) {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();
        shopId = userDoc.data()?['shopId'];
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

    if (!context.mounted) return false;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text("Assinar Plano $planName"),
        content: Text(
          "Será cobrado R\$ ${planPrice.toStringAsFixed(2).replaceAll('.', ',')} "
          "mensalmente pelo plano '$planName'.\n\nDeseja confirmar a assinatura?",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Cancelar"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.deepPurple,
                foregroundColor: Colors.white),
            child: const Text("Confirmar"),
          ),
        ],
      ),
    );

    if (confirm != true || !context.mounted) return false;

    return await _iniciarPagamentoAssinatura(
      context: context,
      shopId: shopId,
      planId: planId,
      planName: planName,
      planPrice: planPrice,
    );
  }

  /// Chama Cloud Function createSubscription (onCall) para ativar o plano.
  static Future<bool> _iniciarPagamentoAssinatura({
    required BuildContext context,
    required String shopId,
    required String planId,
    required String planName,
    required double planPrice,
  }) async {
    try {
      final callable =
          FirebaseFunctions.instance.httpsCallable('createSubscription');
      final result = await callable.call({
        'shopId': shopId,
        'planId': planId,
        'planName': planName,
        'planPrice': planPrice,
        'billingCycle': 'monthly',
      });

      final success = result.data?['success'] == true;
      if (success) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("Plano $planName ativado com sucesso! 🚀"),
              backgroundColor: Colors.green,
            ),
          );
        }
        return true;
      } else {
        throw Exception(result.data?['message'] ?? 'Erro ao criar assinatura.');
      }
    } on FirebaseFunctionsException catch (e) {
      debugPrint(
          "_iniciarPagamentoAssinatura FirebaseFunctionsException: ${e.code} - ${e.message}");
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao processar assinatura: ${e.message}'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return false;
    } catch (e) {
      debugPrint("_iniciarPagamentoAssinatura error: $e");
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao processar assinatura: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
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
            content: Text("Plano $planName ativado! 🎉"),
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
                Text(result.data?['message'] ?? 'Assinatura reativada! 🚀'),
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
