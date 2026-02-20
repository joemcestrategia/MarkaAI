import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
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

      // FALLBACK: Se shopId for null, tentar buscar via User (Igual ao _simulateSuccessfulPurchase)
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
      return SubscriptionPlan.free; // Fallback seguro
    }
  }

  static SubscriptionPlan _parsePlanId(String? id) {
    switch (id) {
      case 'starter':
        return SubscriptionPlan.starter;
      case 'pro':
        return SubscriptionPlan.pro;
      case 'vip':
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

  /// Verifica se pode acessar relatórios avançados
  static Future<bool> canAccessReports() async {
    // Relatórios avançados geralmente atrelados ao financeiro/comissões
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
    // Customizar página agora atrelado a Custom Link ou um feature separado?
    // Vamos assumir Custom Link = Branding
    return await canCustomizeLink();
  }

  /// Retorna detalhes do plano para UI
  static Map<String, dynamic> getPlanDetails(SubscriptionPlan plan) {
    return _plans[plan]!;
  }

  /// Processa a compra (Modo Simplificado para Testes)
  static Future<bool> startPurchaseFlow(
      BuildContext context, SubscriptionPlan plan) async {
    // Exibe diálogo de confirmação para trocar de plano imediatamente
    // Isso substitui o fluxo de pagamento real por enquanto
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Confirmar Troca de Plano"),
        content: Text(
            "Deseja migrar para o plano '${_plans[plan]!['name']}'?\n\n(Modo de Teste: Pagamento será simulado)"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Cancelar"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green, foregroundColor: Colors.white),
            child: const Text("Confirmar e Ativar"),
          ),
        ],
      ),
    );

    if (confirm == true) {
      if (context.mounted) {
        await _simulateSuccessfulPurchase(context, plan);
      }
      return true;
    }
    return false;
  }

  // Helper Simulação (Dev Only)
  // Helper Simulação (Dev Only)
  static Future<void> _simulateSuccessfulPurchase(
      BuildContext context, SubscriptionPlan plan) async {
    String? shopId = await SessionService.getShopId();

    // FALLBACK: Se shopId for null, tentar buscar via User
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
            // Salvar na sessão para próximas chamadas
            await SessionService.saveShopId(shopId);
          }
        } catch (e) {
          debugPrint("Error fetching shopId from user: $e");
        }
      }
    }

    if (shopId != null) {
      try {
        await FirebaseFirestore.instance
            .collection(_collection)
            .doc(shopId)
            .update({
          'subscription': {
            'plan_id': _getPlanId(plan),
            'status': 'active',
            'updated_at': FieldValue.serverTimestamp(),
          }
        });

        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text("Plano ${plan.name} ativado com sucesso! 🚀"),
                backgroundColor: Colors.green),
          );
        }
      } catch (e) {
        debugPrint("Error updating Firestore: $e");
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text("Erro ao ativar plano: $e"),
                backgroundColor: Colors.red),
          );
        }
      }
    } else {
      debugPrint(
          "shopId is NULL even after fallback. Cannot update subscription.");
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text("Erro: Não foi possível identificar sua loja."),
              backgroundColor: Colors.red),
        );
      }
    }
  }
}
