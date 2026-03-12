import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class MercadoPagoService {
  // Singleton do Firebase Functions
  static final FirebaseFunctions _functions = FirebaseFunctions.instance;

  // ===========================================================================
  // 1. GERAR PIX (Via Cloud Functions)
  // ===========================================================================
  static Future<Map<String, dynamic>> gerarPix({
    required String shopId,
    required double amount,
    required String emailCliente,
    required String description,
  }) async {
    try {
      debugPrint("â˜ï¸ [Service] Chamando Cloud Function: createPixPayment");

      final result = await _functions.httpsCallable('createPixPayment').call({
        'shopId': shopId, // Token lido no backend; nunca enviado pelo client
        'amount': amount,
        'email': emailCliente,
        'description': description,
      });

      return Map<String, dynamic>.from(result.data);
    } on FirebaseFunctionsException catch (e) {
      debugPrint("âŒ Erro na Cloud Function: ${e.code} - ${e.message}");
      debugPrint("âŒ Detalhes: ${e.details}");
      // Detect specific backend error for collector not enabled for PIX QR
      final detailsStr = (e.details ?? '').toString().toLowerCase();
      final messageStr = (e.message ?? '').toString().toLowerCase();
      if (messageStr.contains('collector_not_enabled_for_qr') ||
          detailsStr.contains('collector_not_enabled_for_qr') ||
          (detailsStr.contains('collector user') &&
              detailsStr.contains('qr'))) {
        throw Exception('collector_not_enabled_for_qr');
      }
      if (messageStr.contains('collector_no_pix_keys') ||
          detailsStr.contains('collector_no_pix_keys') ||
          detailsStr.contains('pix key') ||
          detailsStr.contains('chave pix') ||
          detailsStr.contains('chaves pix') ||
          detailsStr.contains('collector without pix')) {
        throw Exception('collector_no_pix_keys');
      }
      throw Exception(e.message ?? "Erro ao processar PIX no servidor.");
    } catch (e) {
      debugPrint("âŒ Erro local: $e");
      rethrow;
    }
  }

  // ===========================================================================
  // 2. VERIFICAR STATUS DO PIX
  // ===========================================================================
  static Future<String> verificarStatusPix({
    required String shopId,
    required String paymentId,
  }) async {
    try {
      final result = await _functions.httpsCallable('getPaymentStatus').call({
        'shopId': shopId, // Usado no backend para buscar o access_token
        'paymentId': paymentId,
      });

      final data = Map<String, dynamic>.from(result.data);
      return data['status']?.toString() ?? 'pending';
    } catch (e) {
      debugPrint("âš ï¸ Erro ao verificar status: $e");
      return 'unknown';
    }
  }

  // ===========================================================================
  // 3. COBRAR CARTÃO NOVO
  // ===========================================================================
  static Future<Map<String, dynamic>> cobrarCartao({
    required String accessToken,
    required String cardNumber,
    required String cardHolder,
    required int expirationMonth,
    required int expirationYear,
    required String securityCode,
    required double amount,
    required int installments,
    required String emailCliente,
    required String description,
  }) async {
    try {
      debugPrint("â˜ï¸ [Service] Chamando Cloud Function: cobrarCartao");

      final result = await _functions.httpsCallable('cobrarCartao').call({
        'accessToken': accessToken,
        'cardNumber': cardNumber,
        'cardHolder': cardHolder,
        'expirationMonth': expirationMonth,
        'expirationYear': expirationYear,
        'securityCode': securityCode,
        'amount': amount,
        'installments': installments,
        'emailCliente': emailCliente,
        'description': description,
      });

      return Map<String, dynamic>.from(result.data);
    } on FirebaseFunctionsException catch (e) {
      debugPrint("âŒ Erro Cartão: ${e.message}");
      throw Exception(e.message);
    } catch (e) {
      rethrow;
    }
  }

  // 8. BUSCAR PARCELAS
  static Future<List<Map<String, dynamic>>> buscarParcelas({
    required String accessToken,
    required double amount,
    required String bin, // 6 primeiros dígitos
  }) async {
    try {
      final result = await _functions.httpsCallable('getInstallments').call({
        'accessToken': accessToken,
        'amount': amount,
        'bin': bin,
      });

      if (result.data == null) return [];

      return List<Map<String, dynamic>>.from(result.data);
    } catch (e) {
      debugPrint("âš ï¸ Erro ao buscar parcelas: $e");
      return [];
    }
  }

  // ===========================================================================
  // 4. COBRAR CARTÃO SALVO
  static Future<Map<String, dynamic>> cobrarCartaoSalvo({
    required String accessToken,
    required String customerId,
    required String cardId,
    required double amount,
    required int installments,
    required String emailCliente,
    required String description,
    required String securityCode, // ðŸ”¥ ADICIONADO: Agora aceita o CVV
  }) async {
    try {
      debugPrint("â˜ï¸ Chamando Cloud Function: cobrarCartaoSalvo");

      final result = await _functions.httpsCallable('cobrarCartaoSalvo').call({
        'accessToken': accessToken,
        'customerId': customerId,
        'cardId': cardId,
        'amount': amount,
        'installments': installments,
        'email': emailCliente,
        'description': description,
        'securityCode': securityCode, // ðŸ”¥ ENVIA O CVV PRO BACKEND
      });

      return Map<String, dynamic>.from(result.data);
    } catch (e) {
      debugPrint("âŒ Erro Cartão Salvo: $e");
      rethrow;
    }
  }

  // ===========================================================================
  // 5. NATIVO: GERAR CARD TOKEN (DIRETO API MP)
  // ===========================================================================
  static Future<String> getCardToken({
    required String publicKey,
    required String cardNumber,
    required String cardholderName,
    required String expirationMonth,
    required String expirationYear,
    required String securityCode,
  }) async {
    try {
      final url =
          'https://api.mercadopago.com/v1/card_tokens?public_key=$publicKey';

      final body = {
        "card_number": cardNumber.replaceAll(' ', ''),
        "cardholder": {
          "name": cardholderName,
        },
        "expiration_month": int.parse(expirationMonth),
        "expiration_year": int.parse(expirationYear),
        "security_code": securityCode,
      };

      final response = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      );

      if (response.statusCode == 201 || response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['id'];
      } else {
        final data = jsonDecode(response.body);
        throw Exception(data['message'] ?? 'Erro ao gerar token do cartão');
      }
    } catch (e) {
      debugPrint("❌ Erro getCardToken: $e");
      rethrow;
    }
  }

  // ===========================================================================
  // 6. NATIVO: BUSCAR PARCELAS POR BIN (DIRETO API MP)
  // ===========================================================================
  static Future<List<dynamic>> getInstallmentsWithBin({
    required String publicKey,
    required double amount,
    required String bin,
  }) async {
    try {
      final url =
          'https://api.mercadopago.com/v1/payment_methods/installments?public_key=$publicKey&amount=$amount&bin=$bin';

      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as List<dynamic>;
        if (data.isNotEmpty) {
          return data[0]['payer_costs'] as List<dynamic>;
        }
      }
      return [];
    } catch (e) {
      debugPrint("❌ Erro getInstallmentsWithBin: $e");
      return [];
    }
  }

  // ===========================================================================
  // 7. NATIVO: IDENTIFICAR MÉTODO DE PAGAMENTO (BANDEIRA)
  // ===========================================================================
  static Future<String?> getPaymentMethodId({
    required String publicKey,
    required String bin,
  }) async {
    try {
      final url =
          'https://api.mercadopago.com/v1/payment_methods?public_key=$publicKey';
      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as List<dynamic>;
        // A lógica do MP geralmente requer bater o BIN contra uma lista ou usar endpoint específico.
        // Simplificando: o MP retorna o ID correto quando você tenta tokenizar ou via endpoint de guesser.
        // Como o foco é Stripe-like, podemos inferir localmente para UI ou usar o retorno da API.
        return null; // Implementaremos lógica de guesser se necessário ou usaremos o retorno do token
      }
      return null;
    } catch (e) {
      return null;
    }
  }
}
