import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

class MobileSubscriptionManager {
  static InAppPurchase? _iapInstance;
  static InAppPurchase get _iap {
    _iapInstance ??= InAppPurchase.instance;
    return _iapInstance!;
  }

  static bool _available = false;
  static List<ProductDetails> _products = [];
  static StreamSubscription<List<PurchaseDetails>>? _subscription;

  // IDs dos produtos na loja (Apple/Google)
  static const Set<String> _kProductIds = {
    'marka_ai_starter', // Gratuito/Base
    'marka_ai_top_monthly',
    'marka_ai_vip_monthly',
    'marka_ai_total_monthly'
  };

  static Future<void> initialize() async {
    // Proteção para Web
    if (kIsWeb) return;

    try {
      _available = await _iap.isAvailable();
      if (_available) {
        // Escutar atualizações de compra
        final Stream<List<PurchaseDetails>> purchaseUpdated =
            _iap.purchaseStream;
        _subscription = purchaseUpdated.listen((purchaseDetailsList) {
          _listenToPurchaseUpdated(purchaseDetailsList);
        }, onDone: () {
          _subscription?.cancel();
        }, onError: (error) {
          debugPrint('Erro no stream de IAP: $error');
        });

        await _loadProducts();
      } else {
        debugPrint("InAppPurchase não disponível neste dispositivo.");
      }
    } catch (e) {
      debugPrint("Erro ao inicializar IAP: $e");
      _available = false;
    }
  }

  static Future<void> _loadProducts() async {
    try {
      final ProductDetailsResponse response =
          await _iap.queryProductDetails(_kProductIds);

      if (response.notFoundIDs.isNotEmpty) {
        debugPrint(
            'Produtos não encontrados na loja (IDs inválidos): ${response.notFoundIDs}');
      }

      _products = response.productDetails;
      debugPrint("Produtos IAP carregados: ${_products.length}");
      for (var p in _products) {
        debugPrint("Produto: ${p.id} - ${p.title} - ${p.price}");
      }
    } catch (e) {
      debugPrint("Erro ao carregar produtos IAP: $e");
    }
  }

  static Future<bool> buyPlan(String planId) async {
    if (kIsWeb || !_available) {
      debugPrint(
          "IAP não disponível (Web ou Falha na inicialização) - Tentando chamar buyPlan");
      return false;
    }

    try {
      // Mapear planId interno para productId da loja
      String productId = _mapPlanToProduct(planId);
      if (productId.isEmpty) {
        debugPrint("ID do plano desconhecido: $planId");
        return false;
      }

      // Procura o produto na lista carregada
      final productDetails = _products.firstWhere(
        (p) => p.id == productId,
        orElse: () {
          debugPrint(
              'Produto $productId não encontrado na lista carregada. Tente recarregar.');
          // Retorna um produto dummy ou lança erro. Aqui vamos retornar null check.
          throw Exception('Produto não disponível');
        },
      );

      final PurchaseParam purchaseParam =
          PurchaseParam(productDetails: productDetails);

      // Inicia o fluxo de compra na loja
      // Para assinaturas, usamos buyNonConsumable
      bool success = await _iap.buyNonConsumable(purchaseParam: purchaseParam);
      return success;
    } catch (e) {
      debugPrint("Erro ao iniciar compra: $e");
      return false;
    }
  }

  static String _mapPlanToProduct(String planId) {
    // Mapeamento simples. Ajuste conforme os IDs reais criados nas lojas.
    if (planId == 'starter') return 'marka_ai_starter';
    if (planId == 'top') return 'marka_ai_top_monthly';
    if (planId == 'vip') return 'marka_ai_vip_monthly';
    if (planId == 'total_pro') return 'marka_ai_total_monthly';
    return ''; // Retorna vazio se não mapeado
  }

  static Future<void> _listenToPurchaseUpdated(
      List<PurchaseDetails> purchaseDetailsList) async {
    for (var purchaseDetails in purchaseDetailsList) {
      if (purchaseDetails.status == PurchaseStatus.pending) {
        debugPrint("Compra pendente...");
      } else {
        if (purchaseDetails.status == PurchaseStatus.error) {
          debugPrint("Erro na compra: ${purchaseDetails.error}");
        } else if (purchaseDetails.status == PurchaseStatus.purchased ||
            purchaseDetails.status == PurchaseStatus.restored) {
          debugPrint(
              "Compra realizada/restaurada: ${purchaseDetails.productID}");

          final bool valid = await _verifyPurchase(purchaseDetails);
          if (valid) {
            debugPrint("Compra validada com sucesso!");
            // Aplica a lógica de liberar o conteudo aqui ou via stream global
          } else {
            debugPrint("Falha na validação da compra.");
          }
        }

        if (purchaseDetails.pendingCompletePurchase) {
          await _iap.completePurchase(purchaseDetails);
          debugPrint("Compra finalizada (completePurchase) na loja.");
        }
      }
    }
  }

  static Future<bool> _verifyPurchase(PurchaseDetails purchaseDetails) async {
    try {
      if (kDebugMode) {
        // Validation simulation for debug/test
        debugPrint(
            'Simulating server-side validation for: ${purchaseDetails.productID}');
        await Future.delayed(const Duration(milliseconds: 500));
        return true;
      }

      final response = await sb.Supabase.instance.client.functions.invoke(
        'verify-subscription',
        body: {
          'source': defaultTargetPlatform == TargetPlatform.iOS
              ? 'app_store'
              : 'google_play',
          'productId': purchaseDetails.productID,
          'verificationData':
              purchaseDetails.verificationData.serverVerificationData,
          'transactionId': purchaseDetails.purchaseID,
        },
      );

      if (response.status != 200) {
        debugPrint('Erro na função de validação: ${response.status}');
        return false;
      }

      final data = response.data as Map<String, dynamic>;
      final bool isValid = data['valid'] ?? false;
      debugPrint('Server validation result: $isValid');
      return isValid;
    } catch (e) {
      debugPrint("Error calling server validation: $e");
      return false;
    }
  }
}
