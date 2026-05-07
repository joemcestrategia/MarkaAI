import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';
import '../widgets/coupon_invalid_modal.dart';

/// Resultado da validação de um cupom
class CouponValidationResult {
  final bool isValid;
  final String? message;
  final double? discountPercent;
  final String? couponId;
  final Map<String, dynamic>? couponData;
  final CouponErrorType? errorType;

  CouponValidationResult({
    required this.isValid,
    this.message,
    this.discountPercent,
    this.couponId,
    this.couponData,
    this.errorType,
  });

  factory CouponValidationResult.invalid(
    CouponErrorType type,
    String message,
  ) =>
      CouponValidationResult(
        isValid: false,
        message: message,
        errorType: type,
      );
}

class CouponService {
  static final _supabase = Supabase.instance.client;

  /// Verifica se um cliente é novo na loja (nunca teve agendamento confirmado e sem classificação manual)
  static Future<bool> checkIsNewClient({
    required String clientId,
    required String shopId,
    String? currentClassification,
  }) async {
    try {
      if (currentClassification != null && currentClassification.trim().isNotEmpty) {
        return false;
      }
      final result = await _supabase
          .from('appointments')
          .select('id')
          .eq('shop_id', shopId)
          .eq('client_id', clientId)
          .neq('status', 'cancelado')
          .neq('status', 'recusado')
          .limit(1);
      return (result as List).isEmpty;
    } catch (e) {
      if (kDebugMode) print('Erro ao verificar novo cliente: $e');
      return false;
    }
  }

  /// Valida um cupom para um determinado usuário e loja
  static Future<CouponValidationResult> validateCoupon({
    required String shopId,
    required String code,
    required String userId,
    String? serviceId,
    String? clientClassification,
    List<String>? clientManualTags,
    bool isNewClient = false,
    bool isVipClient = false,
    String? selectedPaymentMethod,
  }) async {
    try {
      final normalizedCode = code.trim().toUpperCase();
      if (normalizedCode.isEmpty) {
        return CouponValidationResult(
            isValid: false, message: 'Digite um código.');
      }

      // 1. Busca o cupom no Supabase
      final response = await _supabase
          .from('coupons')
          .select()
          .eq('shop_id', shopId)
          .eq('code', normalizedCode)
          .maybeSingle();

      if (response == null) {
        return CouponValidationResult(
            isValid: false,
            message: 'Cupom inválido.',
            errorType: CouponErrorType.notFound);
      }

      final couponData = response;
      final couponId = couponData['id'].toString();
 
      // 2. Verifica se está ativo
      if (couponData['is_active'] != true) {
        return CouponValidationResult(
            isValid: false,
            message: 'Este cupom não está mais ativo.',
            errorType: CouponErrorType.inactive);
      }

      // 3. Verifica restrição de serviço
      final List<dynamic>? serviceIds = couponData['service_ids'];
      if (serviceIds != null && serviceIds.isNotEmpty) {
        if (serviceId == null || !serviceIds.contains(serviceId)) {
          return CouponValidationResult(
              isValid: false,
              message: 'Este cupom não é válido para o serviço selecionado.',
              errorType: CouponErrorType.notForService);
        }
      }
 
      // 3b. Verifica se o desconto é válido (segurança contra dados corrompidos)
      final double discountValue = (couponData['discount_percent'] as num?)?.toDouble() ?? 0.0;
      if (discountValue <= 0 || discountValue > 100) {
        return CouponValidationResult(
            isValid: false,
            message: 'Cupom com desconto inválido.',
            errorType: CouponErrorType.generic);
      }

      // 4. Verifica validade (data) — usa fim do dia para incluir o dia inteiro
      final validUntilStr = couponData['valid_until'];
      if (validUntilStr != null) {
        final validUntil = DateTime.parse(validUntilStr.toString());
        final endOfDay = DateTime(validUntil.year, validUntil.month, validUntil.day, 23, 59, 59);
        if (endOfDay.isBefore(DateTime.now())) {
          return CouponValidationResult(
              isValid: false,
              message: 'Este cupom expirou.',
              errorType: CouponErrorType.expired);
        }
      }
 
      // 5. Verifica validade (mês específico)
      final validMonth = int.tryParse(couponData['valid_month']?.toString() ?? '');
      if (validMonth != null && DateTime.now().month != validMonth) {
        return CouponValidationResult(
            isValid: false,
            message: 'Este cupom não é válido neste mês.',
            errorType: CouponErrorType.notActiveMonth);
      }
 
      // 6. Verifica limite de uso global
      final int usageCount = int.tryParse(couponData['usage_count']?.toString() ?? '0') ?? 0;
      final int? maxUsage = int.tryParse(couponData['max_usage']?.toString() ?? '');
      
      if (maxUsage != null && maxUsage > 0 && usageCount >= maxUsage) {
        return CouponValidationResult(
            isValid: false,
            message: 'Este cupom atingiu o limite de usos.',
            errorType: CouponErrorType.limitReached);
      }
 
      // 7. Verifica se o usuário já usou este cupom
      final usageResponse = await _supabase
          .from('coupon_usage')
          .select()
          .eq('coupon_id', couponId)
          .eq('user_id', userId)
          .maybeSingle();
 
      if (usageResponse != null) {
        return CouponValidationResult(
            isValid: false,
            message: 'Você já utilizou este cupom.',
            errorType: CouponErrorType.alreadyUsed);
      }

      // 8. Busca dados de shop_clients se classification não foi fornecida
      String? resolvedClassification = clientClassification;
      List<String> resolvedManualTags = clientManualTags ?? [];
      if (resolvedClassification == null) {
        try {
          final shopClientData = await _supabase
              .from('shop_clients')
              .select('classification, manual_tags')
              .eq('user_id', userId)
              .eq('shop_id', shopId)
              .maybeSingle();
          if (shopClientData != null) {
            resolvedClassification = shopClientData['classification']?.toString();
            if (resolvedManualTags.isEmpty && shopClientData['manual_tags'] != null) {
              resolvedManualTags = List<String>.from(shopClientData['manual_tags']);
            }
          }
        } catch (e) {
          if (kDebugMode) print('Aviso: não foi possível carregar shop_clients: $e');
        }
      }

      // Verificação C — Forma de pagamento
      final List<dynamic> validPaymentMethods =
          couponData['valid_payment_methods'] as List<dynamic>? ?? [];
      if (validPaymentMethods.isNotEmpty && selectedPaymentMethod != null) {
        if (selectedPaymentMethod == 'local' ||
            !validPaymentMethods.contains(selectedPaymentMethod)) {
          return CouponValidationResult.invalid(
            CouponErrorType.onlinePaymentOnly,
            'Este cupom é válido apenas para pagamentos realizados online (Pix ou cartão). Selecione uma forma de pagamento online para utilizá-lo.',
          );
        }
      }

      // Verificação B — Categorias bloqueadas (comparação case-insensitive)
      final List<dynamic> blockedClassificationsRaw =
          couponData['blocked_classifications'] as List<dynamic>? ?? [];
      if (blockedClassificationsRaw.isNotEmpty) {
        final Set<String> blockedUpper = blockedClassificationsRaw
            .map((c) => c.toString().trim().toUpperCase())
            .where((c) => c.isNotEmpty)
            .toSet();
        if (resolvedClassification != null &&
            blockedUpper.contains(resolvedClassification.trim().toUpperCase())) {
          return CouponValidationResult.invalid(
            CouponErrorType.classificationBlocked,
            'Este cupom não está disponível para o seu perfil de cliente.',
          );
        }
        final hasBlockedTag = resolvedManualTags
            .any((tag) => blockedUpper.contains(tag.trim().toUpperCase()));
        if (hasBlockedTag) {
          return CouponValidationResult.invalid(
            CouponErrorType.classificationBlocked,
            'Este cupom não está disponível para o seu perfil de cliente.',
          );
        }
      }

      // Verificação A — Público-alvo
      final String targetAudience =
          couponData['target_audience']?.toString() ?? 'all';
      if (targetAudience == 'new_clients' && !isNewClient) {
        return CouponValidationResult.invalid(
          CouponErrorType.newClientsOnly,
          'Este cupom é válido apenas para quem está agendando pela primeira vez neste salão.',
        );
      }
      if (targetAudience == 'vip_only' && !isVipClient) {
        return CouponValidationResult.invalid(
          CouponErrorType.vipOnly,
          'Este cupom é válido apenas para clientes VIP do salão.',
        );
      }

      return CouponValidationResult(
        isValid: true,
        discountPercent: discountValue,
        couponId: couponId,
        couponData: couponData,
      );
    } catch (e) {
      if (kDebugMode) print('Erro ao validar cupom: $e');
      return CouponValidationResult(
          isValid: false, message: 'Erro ao validar cupom.');
    }
  }
 
  /// Registra o uso do cupom após o agendamento ser confirmado.
  /// A tabela coupon_usage possui UNIQUE(coupon_id, user_id), então
  /// tentativas duplicadas são rejeitadas no banco (proteção contra race condition).
  static Future<void> markCouponAsUsed({
    required String shopId,
    required String couponId,
    required String userId,
    required String appointmentId,
  }) async {
    try {
      // 1. Registra o uso na tabela coupon_usage
      //    Se houver UNIQUE violation, o cupom já foi usado por este usuário.
      await _supabase.from('coupon_usage').insert({
        'coupon_id': couponId,
        'user_id': userId,
        'appointment_id': appointmentId,
        'used_at': DateTime.now().toIso8601String(),
      });
 
      // 2. Incrementa o contador de uso global via RPC atômico
      //    A função verifica se max_usage não foi atingido antes de incrementar.
      try {
        await _supabase.rpc('increment_coupon_usage', params: {'coupon_id': couponId});
      } catch (e) {
        if (kDebugMode) print('Erro ao incrementar uso do cupom (RPC): $e');
      }
    } on PostgrestException catch (e) {
      // Código 23505 = unique_violation → cupom já usado por este usuário
      if (e.code == '23505') {
        if (kDebugMode) print('Cupom $couponId já foi utilizado pelo usuário $userId (unique constraint).');
      } else {
        if (kDebugMode) print('Erro PostgrestException ao marcar cupom: $e');
      }
    } catch (e) {
      if (kDebugMode) print('Erro ao marcar cupom como usado: $e');
    }
  }
}
