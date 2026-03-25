import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';

/// Resultado da validação de um cupom
class CouponValidationResult {
  final bool isValid;
  final String? message;
  final double? discountPercent;
  final String? couponId;

  CouponValidationResult({
    required this.isValid,
    this.message,
    this.discountPercent,
    this.couponId,
  });
}

class CouponService {
  static final _supabase = Supabase.instance.client;

  /// Valida um cupom para um determinado usuário e loja
  static Future<CouponValidationResult> validateCoupon({
    required String shopId,
    required String code,
    required String userId,
    String? serviceId,
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
            isValid: false, message: 'Cupom inválido.');
      }

      final couponData = response as Map<String, dynamic>;
      final couponId = couponData['id'].toString();
 
      // 2. Verifica se está ativo
      if (couponData['is_active'] != true) {
        return CouponValidationResult(
            isValid: false, message: 'Este cupom não está mais ativo.');
      }

      // 3. Verifica restrição de serviço
      final List<dynamic>? serviceIds = couponData['service_ids'];
      if (serviceIds != null && serviceIds.isNotEmpty) {
        if (serviceId == null || !serviceIds.contains(serviceId)) {
          return CouponValidationResult(
              isValid: false,
              message: 'Este cupom não é válido para o serviço selecionado.');
        }
      }
 
      // 4. Verifica validade (data)
      final validUntilStr = couponData['valid_until'];
      if (validUntilStr != null) {
        final validUntil = DateTime.parse(validUntilStr.toString());
        if (validUntil.isBefore(DateTime.now())) {
          return CouponValidationResult(
              isValid: false, message: 'Este cupom expirou.');
        }
      }
 
      // 5. Verifica validade (mês específico)
      final validMonth = int.tryParse(couponData['valid_month']?.toString() ?? '');
      if (validMonth != null && DateTime.now().month != validMonth) {
        return CouponValidationResult(
            isValid: false, message: 'Este cupom não é válido neste mês.');
      }
 
      // 6. Verifica limite de uso global
      final int usageCount = int.tryParse(couponData['usage_count']?.toString() ?? '0') ?? 0;
      final int? maxUsage = int.tryParse(couponData['max_usage']?.toString() ?? '');
      
      if (maxUsage != null && maxUsage > 0 && usageCount >= maxUsage) {
        return CouponValidationResult(
            isValid: false, message: 'Este cupom atingiu o limite de usos.');
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
            isValid: false, message: 'Você já utilizou este cupom.');
      }
 
      return CouponValidationResult(
        isValid: true,
        discountPercent: (couponData['discount_percent'] as num?)?.toDouble() ?? 0.0,
        couponId: couponId,
      );
    } catch (e) {
      if (kDebugMode) print('Erro ao validar cupom: $e');
      return CouponValidationResult(
          isValid: false, message: 'Erro ao validar cupom.');
    }
  }
 
  /// Registra o uso do cupom após o agendamento ser confirmado
  static Future<void> markCouponAsUsed({
    required String shopId,
    required String couponId,
    required String userId,
    required String appointmentId,
  }) async {
    try {
      // 1. Registra o uso na tabela coupon_usage
      await _supabase.from('coupon_usage').insert({
        'coupon_id': couponId,
        'user_id': userId,
        'appointment_id': appointmentId,
        'used_at': DateTime.now().toIso8601String(),
      });
 
      // 2. Incrementa o contador de uso global
      try {
        await _supabase.rpc('increment_coupon_usage', params: {'coupon_id': couponId});
      } catch (e) {
        // Fallback: update manual
        final couponQuery = await _supabase.from('coupons').select('usage_count').eq('id', couponId).single();
        final currentCount = int.tryParse(couponQuery['usage_count']?.toString() ?? '0') ?? 0;
        await _supabase.from('coupons').update({'usage_count': currentCount + 1}).eq('id', couponId);
      }
    } catch (e) {
      if (kDebugMode) print('Erro ao marcar cupom como usado: $e');
    }
  }
}
