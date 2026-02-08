import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

class MercadoPagoService {
  // Singleton do Firebase Functions
  static final FirebaseFunctions _functions = FirebaseFunctions.instance;

  // ===========================================================================
  // 1. GERAR PIX (Via Cloud Functions)
  // ===========================================================================
  static Future<Map<String, dynamic>> gerarPix({
    required String accessToken,
    required double amount,
    required String emailCliente,
    required String description,
  }) async {
    try {
      debugPrint("☁️ [Service] Chamando Cloud Function: createPixPayment");
      
      final result = await _functions.httpsCallable('createPixPayment').call({
        'accessToken': accessToken,
        'amount': amount,
        'email': emailCliente,
        'description': description,
      });

      return Map<String, dynamic>.from(result.data);

    } on FirebaseFunctionsException catch (e) {
      debugPrint("❌ Erro na Cloud Function: ${e.code} - ${e.message}");
      debugPrint("❌ Detalhes: ${e.details}");
      throw Exception(e.message ?? "Erro ao processar PIX no servidor.");
    } catch (e) {
      debugPrint("❌ Erro local: $e");
      rethrow;
    }
  }

  // ===========================================================================
  // 2. VERIFICAR STATUS DO PIX
  // ===========================================================================
  static Future<String> verificarStatusPix({
    required String accessToken,
    required String paymentId,
  }) async {
    try {
      final result = await _functions.httpsCallable('getPaymentStatus').call({
        'accessToken': accessToken,
        'paymentId': paymentId,
      });
      
      final data = Map<String, dynamic>.from(result.data);
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
      debugPrint("☁️ [Service] Chamando Cloud Function: cobrarCartao");

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
      debugPrint("❌ Erro Cartão: ${e.message}");
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
      debugPrint("⚠️ Erro ao buscar parcelas: $e");
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
    required String securityCode, // 🔥 ADICIONADO: Agora aceita o CVV
  }) async {
    try {
      debugPrint("☁️ Chamando Cloud Function: cobrarCartaoSalvo");

      final result = await _functions.httpsCallable('cobrarCartaoSalvo').call({
        'accessToken': accessToken,
        'customerId': customerId,
        'cardId': cardId,
        'amount': amount,
        'installments': installments,
        'email': emailCliente,
        'description': description,
        'securityCode': securityCode, // 🔥 ENVIA O CVV PRO BACKEND
      });

      return Map<String, dynamic>.from(result.data);

    } catch (e) {
      debugPrint("❌ Erro Cartão Salvo: $e");
      rethrow;
    }
  }
}