import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter/foundation.dart';

/// =====================================================
/// MERCADO PAGO CHECKOUT TRANSPARENTE SERVICE
/// =====================================================
///
/// Integração com Checkout Transparente
/// - Gera CardToken via MercadoPago.js (FRONTEND)
/// - Cria pagamento com token (BACKEND)
/// - Retorna parcelas automaticamente
/// =====================================================

class MercadoPagoCheckoutTransparenteService {
  static const String _baseUrl = 'https://api.mercadopago.com/v1/payments';
  static const String _baseUrlSandbox =
      'https://api.sandbox.mercadopago.com/v1/payments';

  /// Instancia MercadoPago.js no Flutter WebView
  static Future<String> inicializarMercadoPagoJs({
    required String publicKey,
  }) async {
    try {
      debugPrint(
          'ðŸ”§ Inicializando MercadoPago.js com Public Key: $publicKey');

      // Este seria chamado no WebView com:
      // window.mercadopago = new MercadoPago('PUBLIC_KEY', {...});

      return publicKey;
    } catch (e) {
      debugPrint('âŒ Erro ao inicializar: $e');
      rethrow;
    }
  }

  /// Cria pagamento com CardToken (chamado no BACKEND)
  static Future<Map<String, dynamic>> criarPagamentoComToken({
    required String accessToken,
    required String cardToken,
    required double valor,
    required int parcelas,
    required String clientEmail,
    required String descricao,
    required String paymentMethodId,
    bool isSandbox = true,
  }) async {
    try {
      final url = isSandbox ? _baseUrlSandbox : _baseUrl;

      debugPrint('ðŸ’³ Criando pagamento com CardToken');
      debugPrint('   Valor: R\$ $valor');
      debugPrint('   Parcelas: $parcelas');
      debugPrint('   Email: $clientEmail');

      final body = {
        'token': cardToken, // CardToken gerado no FRONTEND
        'amount': valor,
        'installments': parcelas,
        'payment_method_id': paymentMethodId, // 'credit_card' ou 'debit_card'
        'payer': {
          'email': clientEmail,
        },
        'description': descricao,
        'capture': true, // Captura automaticamente
        'statement_descriptor': 'MarkaAI Service',
      };

      debugPrint('ðŸ“¡ POST $url');
      debugPrint('   Body: ${jsonEncode(body)}');

      final response = await http.post(
        Uri.parse(url),
        headers: {
          'Authorization': 'Bearer $accessToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(body),
      );

      debugPrint('ðŸ“Š Response status: ${response.statusCode}');

      final responseData = jsonDecode(response.body) as Map<String, dynamic>;

      if (response.statusCode == 201 || response.statusCode == 200) {
        debugPrint('âœ… Pagamento criado com sucesso');
        debugPrint('   ID: ${responseData['id']}');
        debugPrint('   Status: ${responseData['status']}');

        return {
          'success': true,
          'payment_id': responseData['id'],
          'status': responseData['status'],
          'status_detail': responseData['status_detail'],
          'transaction_details': responseData['transaction_details'],
        };
      } else {
        debugPrint('âŒ Erro: ${response.statusCode}');
        debugPrint('   ${jsonEncode(responseData)}');

        return {
          'success': false,
          'error': responseData['message'] ?? 'Erro ao criar pagamento',
          'error_details': responseData['cause'] ?? [],
        };
      }
    } catch (e) {
      debugPrint('âŒ Erro: $e');
      rethrow;
    }
  }

  /// Busca parcelas disponíveis via API
  /// (DEPRECATED - Use MercadoPago.js no frontend em vez disso)
  static Future<List<Map<String, dynamic>>> buscarParcelas({
    required String publicKey,
    required double amount,
    required String bin,
    bool isSandbox = true,
  }) async {
    try {
      final url = isSandbox
          ? 'https://api.sandbox.mercadopago.com/v1/payment_methods/installments'
          : 'https://api.mercadopago.com/v1/payment_methods/installments';

      debugPrint('ðŸ” Buscando parcelas para BIN: $bin');

      final response = await http.get(
        Uri.parse(url).replace(
          queryParameters: {
            'public_key': publicKey,
            'amount': amount.toString(),
            'bin': bin,
          },
        ),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as List<dynamic>;

        // Formata resposta
        final parcelas = data
            .map((item) => {
                  'installments': item['installments'] ?? [],
                  'payment_method_id': item['payment_method_id'],
                  'payment_type_id': item['payment_type_id'],
                })
            .toList();

        debugPrint('âœ… Parcelas encontradas: ${parcelas.length}');
        return parcelas;
      } else {
        debugPrint('âŒ Erro ao buscar parcelas: ${response.statusCode}');
        return [];
      }
    } catch (e) {
      debugPrint('âŒ Erro: $e');
      return [];
    }
  }

  /// Obtém status de pagamento
  static Future<Map<String, dynamic>> obterStatusPagamento({
    required String accessToken,
    required String paymentId,
    bool isSandbox = true,
  }) async {
    try {
      final url = isSandbox
          ? 'https://api.sandbox.mercadopago.com/v1/payments/$paymentId'
          : 'https://api.mercadopago.com/v1/payments/$paymentId';

      final response = await http.get(
        Uri.parse(url),
        headers: {
          'Authorization': 'Bearer $accessToken',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return {
          'success': true,
          'payment_id': data['id'],
          'status': data['status'],
          'status_detail': data['status_detail'],
          'amount': data['transaction_details']?['net_received_amount'],
        };
      } else {
        throw Exception('Erro ao obter status: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('âŒ Erro: $e');
      rethrow;
    }
  }
}

/// =====================================================
/// ESTRUTURA DE RESPONSE - CRIAR PAGAMENTO
/// =====================================================
///
/// Sucesso (201):
/// {
///   "id": 12345678,
///   "status": "approved",
///   "status_detail": "accredited",
///   "transaction_details": {
///     "net_received_amount": 95.00,
///     "acquirer_reference": "123456789"
///   }
/// }
///
/// Erro (400):
/// {
///   "message": "Invalid request",
///   "cause": [
///     {
///       "code": "INVALID_INSTALLMENTS",
///       "description": "Installments must be between 1 and 12"
///     }
///   ]
/// }
///
