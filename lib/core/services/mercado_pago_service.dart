import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class MercadoPagoService {
  static final _supabase = Supabase.instance.client;

  // ===========================================================================
  // 1. GERAR PIX (Via Supabase Functions)
  // ===========================================================================
  static Future<Map<String, dynamic>> gerarPix({
    required String shopId,
    required double amount,
    required String emailCliente,
    required String description,
    String? externalReference,
  }) async {
    try {
      debugPrint("⚡ [Service] Chamando Supabase Function: create-pix-payment");

      final response = await _supabase.functions.invoke('create-pix-payment', body: {
        'shop_id': shopId,
        'amount': amount,
        'email': emailCliente,
        'description': description,
        'external_reference': externalReference,
      });

      if (response.status != 200) {
        throw Exception(response.data['message'] ?? 'Erro no servidor de pagamento.');
      }

      return Map<String, dynamic>.from(response.data);
    } on FunctionException catch (e) {
      debugPrint("❌ Erro na Supabase Function: ${e.status} - ${e.details}");
      // Detect specific backend error for collector not enabled for PIX QR
      final messageStr = (e.details ?? e.toString()).toLowerCase();
      if (messageStr.contains('collector_not_enabled_for_qr')) {
        throw Exception('collector_not_enabled_for_qr');
      }
      if (messageStr.contains('collector_no_pix_keys')) {
        throw Exception('collector_no_pix_keys');
      }
      throw Exception(e.details?.toString() ?? "Erro ao processar PIX no servidor.");
    } catch (e) {
      debugPrint("❌ Erro local: $e");
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
      final response = await _supabase.functions.invoke('get-payment-status', body: {
        'shop_id': shopId,
        'payment_id': paymentId,
      });

      if (response.status != 200) return 'unknown';

      final data = Map<String, dynamic>.from(response.data);
      return data['status']?.toString() ?? 'pending';
    } catch (e) {
      debugPrint("⚠️ Erro ao verificar status: $e");
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
      debugPrint("⚡ [Service] Chamando Supabase Function: cobrar-cartao");

      final response = await _supabase.functions.invoke('cobrar-cartao', body: {
        'access_token': accessToken,
        'card_number': cardNumber,
        'card_holder': cardHolder,
        'expiration_month': expirationMonth,
        'expiration_year': expirationYear,
        'security_code': securityCode,
        'amount': amount,
        'installments': installments,
        'email_cliente': emailCliente,
        'description': description,
      });

      if (response.status != 200) {
        throw Exception(response.data['message'] ?? 'Erro ao processar cartão.');
      }

      return Map<String, dynamic>.from(response.data);
    } catch (e) {
      debugPrint("❌ Erro Cartão: $e");
      rethrow;
    }
  }

  // 4. BUSCAR PARCELAS
  static Future<List<Map<String, dynamic>>> buscarParcelas({
    required String accessToken,
    required double amount,
    required String bin, // 6 primeiros dígitos
  }) async {
    try {
      final response = await _supabase.functions.invoke('get-installments', body: {
        'access_token': accessToken,
        'amount': amount,
        'bin': bin,
      });

      if (response.data == null) return [];

      return List<Map<String, dynamic>>.from(response.data);
    } catch (e) {
      debugPrint("⚠️ Erro ao buscar parcelas: $e");
      return [];
    }
  }

  // ===========================================================================
  // 5. COBRAR CARTÃO SALVO
  static Future<Map<String, dynamic>> cobrarCartaoSalvo({
    required String accessToken,
    required String customerId,
    required String cardId,
    required double amount,
    required int installments,
    required String emailCliente,
    required String description,
    required String securityCode,
  }) async {
    try {
      debugPrint("⚡ Chamando Supabase Function: cobrar-cartao-salvo");

      final response = await _supabase.functions.invoke('cobrar-cartao-salvo', body: {
        'access_token': accessToken,
        'customer_id': customerId,
        'card_id': cardId,
        'amount': amount,
        'installments': installments,
        'email_cliente': emailCliente,
        'description': description,
        'security_code': securityCode,
      });

      if (response.status != 200) {
        throw Exception(response.data['message'] ?? 'Erro ao processar cartão salvo.');
      }

      return Map<String, dynamic>.from(response.data);
    } catch (e) {
      debugPrint("❌ Erro Cartão Salvo: $e");
      rethrow;
    }
  }

  // ===========================================================================
  // 6. CRIAR PAGAMENTO COM CARTÃO (Via Supabase Functions)
  // ===========================================================================
  static Future<Map<String, dynamic>> criarPagamentoCartao({
    required String shopId,
    required String cardToken,
    required double amount,
    required int installments,
    required String email,
    required String description,
    required String cpf,
    String? paymentMethodId,
    String? issuerId,
  }) async {
    try {
      debugPrint("⚡ [Service] Chamando Supabase Function: criar-pagamento");

      final response = await _supabase.functions.invoke('criar-pagamento', body: {
        'shop_id': shopId,
        'card_token': cardToken,
        'amount': amount,
        'installments': installments,
        'email': email,
        'payer_email': email,
        'description': description,
        'cpf': cpf,
        'payer_cpf': cpf,
        'payment_method_id': paymentMethodId,
        'issuer_id': issuerId,
      });

      if (response.status != 200) {
        throw Exception(response.data['message'] ?? 'Erro ao processar pagamento com cartão.');
      }

      return Map<String, dynamic>.from(response.data);
    } on FunctionException catch (e) {
      debugPrint("❌ Erro na Supabase Function: ${e.status} - ${e.details}");
      throw Exception(e.details?.toString() ?? "Erro ao processar pagamento no servidor.");
    } catch (e) {
      debugPrint("❌ Erro Pagamento Cartão: $e");
      rethrow;
    }
  }

  // ===========================================================================
  // 7. NATIVO: GERAR CARD TOKEN (DIRETO API MP)
  // ===========================================================================
  static Future<Map<String, dynamic>> getCardToken({
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
        return {
          'id': data['id'],
          'payment_method_id': data['payment_method_id'],
          'issuer_id': data['issuer_id'],
        };
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
  // 7. NATIVO: BUSCAR PARCELAS POR BIN (DIRETO API MP)
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
  // 8. NATIVO: IDENTIFICAR MÉTODO DE PAGAMENTO (BANDEIRA)
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
        // final data = jsonDecode(response.body) as List<dynamic>;
        return null;
      }
      return null;
    } catch (e) {
      return null;
    }
  }
}
