import 'package:cloud_firestore/cloud_firestore.dart';
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
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Valida um cupom para um determinado usuário e loja
  static Future<CouponValidationResult> validateCoupon({
    required String shopId,
    required String code,
    required String userId,
  }) async {
    try {
      final normalizedCode = code.trim().toUpperCase();
      if (normalizedCode.isEmpty) {
        return CouponValidationResult(
            isValid: false, message: 'Digite um código.');
      }

      // 1. Busca o cupom
      final couponQuery = await _firestore
          .collection('shops')
          .doc(shopId)
          .collection('coupons')
          .where('code', isEqualTo: normalizedCode)
          .limit(1)
          .get();

      if (couponQuery.docs.isEmpty) {
        return CouponValidationResult(
            isValid: false, message: 'Cupom inválido.');
      }

      final couponDoc = couponQuery.docs.first;
      final couponData = couponDoc.data();
      final couponId = couponDoc.id;

      // 2. Verifica se está ativo
      if (couponData['isActive'] != true) {
        return CouponValidationResult(
            isValid: false, message: 'Este cupom não está mais ativo.');
      }

      // 3. Verifica validade (data)
      final validUntil = couponData['validUntil'] as Timestamp?;
      if (validUntil != null && validUntil.toDate().isBefore(DateTime.now())) {
        return CouponValidationResult(
            isValid: false, message: 'Este cupom expirou.');
      }

      // 4. Verifica validade (mês específico)
      final validMonth = couponData['validMonth'] as int?;
      if (validMonth != null && DateTime.now().month != validMonth) {
        return CouponValidationResult(
            isValid: false, message: 'Este cupom não é válido neste mês.');
      }

      // 5. Verifica se o usuário já usou este cupom
      final usageDoc = await _firestore
          .collection('shops')
          .doc(shopId)
          .collection('coupons')
          .doc(couponId)
          .collection('usage')
          .doc(userId)
          .get();

      if (usageDoc.exists) {
        return CouponValidationResult(
            isValid: false, message: 'Você já utilizou este cupom.');
      }

      return CouponValidationResult(
        isValid: true,
        discountPercent:
            (couponData['discountPercent'] as num?)?.toDouble() ?? 0.0,
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
      final batch = _firestore.batch();

      // Registra o uso na subcoleção de usage
      final usageRef = _firestore
          .collection('shops')
          .doc(shopId)
          .collection('coupons')
          .doc(couponId)
          .collection('usage')
          .doc(userId);

      batch.set(usageRef, {
        'usedAt': FieldValue.serverTimestamp(),
        'appointmentId': appointmentId,
      });

      // Incrementa o contador de uso global do cupom
      final couponRef = _firestore
          .collection('shops')
          .doc(shopId)
          .collection('coupons')
          .doc(couponId);

      batch.update(couponRef, {
        'usageCount': FieldValue.increment(1),
      });

      await batch.commit();
    } catch (e) {
      if (kDebugMode) print('Erro ao marcar cupom como usado: $e');
    }
  }
}
