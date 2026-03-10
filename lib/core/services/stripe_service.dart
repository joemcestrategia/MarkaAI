import 'package:flutter/material.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/session_service.dart';

class StripeService {
  static final StripeService instance = StripeService._();
  StripeService._();

  /// Aparência do PaymentSheet no estilo MarkaAI (roxo)
  static PaymentSheetAppearance get _appAppearance =>
      const PaymentSheetAppearance(
        colors: PaymentSheetAppearanceColors(
          primary: Color(0xFF6B21A8), // roxo principal
          background: Color(0xFFF8F9FD), // fundo do app
          componentBackground: Colors.white,
          componentBorder: Color(0xFFE5E7EB),
          componentDivider: Color(0xFFE5E7EB),
          primaryText: Color(0xFF111827),
          secondaryText: Color(0xFF6B7280),
          componentText: Color(0xFF111827),
          placeholderText: Color(0xFF9CA3AF),
          icon: Color(0xFF6B21A8),
        ),
        shapes: PaymentSheetShape(
          borderRadius: 12,
          borderWidth: 1.5,
        ),
        primaryButton: PaymentSheetPrimaryButtonAppearance(
          colors: PaymentSheetPrimaryButtonTheme(
            light: PaymentSheetPrimaryButtonThemeColors(
              background: Color(0xFF6B21A8),
              text: Colors.white,
              border: Color(0xFF6B21A8),
            ),
          ),
        ),
      );

  /// Atualiza o plano no Firestore imediatamente após pagamento aprovado
  static Future<void> _updatePlanInFirestore(String planId) async {
    try {
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
      if (shopId == null) return;

      await FirebaseFirestore.instance.collection('shops').doc(shopId).set({
        'subscription': {
          'plan_id': planId,
          'status': 'active',
          'updated_at': FieldValue.serverTimestamp(),
          'payment_method': 'stripe',
        }
      }, SetOptions(merge: true));

      debugPrint('[StripeService] Plano atualizado para: $planId');
    } catch (e) {
      debugPrint('[StripeService] Erro ao atualizar plano: $e');
    }
  }

  /// Inicializa o Payment Sheet para uma Assinatura (Subscription)
  Future<bool> setupSubscriptionPayment({
    required String planId,
    required String shopId,
    required String customerEmail,
  }) async {
    try {
      // 1. Chamar Cloud Function para criar o cliente/assinatura
      final HttpsCallable callable =
          FirebaseFunctions.instance.httpsCallable('createStripeSubscription');

      final response = await callable.call({
        'planId': planId,
        'shopId': shopId,
        'email': customerEmail,
      });

      final data = response.data;
      final String? paymentIntentClientSecret =
          data['paymentIntentClientSecret'];
      final String? setupIntentClientSecret = data['setupIntentClientSecret'];
      final String customerId = data['customer'];
      final String ephemeralKeySecret = data['ephemeralKey'];

      // 2. Inicializar o Payment Sheet com tema visual do app
      await Stripe.instance.initPaymentSheet(
        paymentSheetParameters: SetupPaymentSheetParameters(
          paymentIntentClientSecret: paymentIntentClientSecret,
          setupIntentClientSecret: setupIntentClientSecret,
          customerEphemeralKeySecret: ephemeralKeySecret,
          customerId: customerId,
          merchantDisplayName: 'MarkaAI',
          billingDetails: BillingDetails(
            email: customerEmail,
          ),
          appearance: _appAppearance,
          style: ThemeMode.light,
        ),
      );

      // 3. Exibir o Payment Sheet
      await Stripe.instance.presentPaymentSheet();

      // 4. Pagamento aprovado — atualizar plano no Firestore imediatamente
      // (não dependemos do webhook que requer configuração extra no Stripe Dashboard)
      await _updatePlanInFirestore(planId);

      return true;
    } on StripeException catch (e) {
      // Usuário cancelou ou erro Stripe
      debugPrint(
          '[StripeService] StripeException: ${e.error.localizedMessage}');
      if (e.error.code == FailureCode.Canceled) {
        return false; // cancelamento não é erro
      }
      return false;
    } catch (e) {
      debugPrint('[StripeService] Error in setupSubscriptionPayment: $e');
      return false;
    }
  }

  /// Inicializa o Payment Sheet para uma compra avulsa (Boost)
  Future<bool> processOneTimePayment({
    required double amount,
    required String currency,
    required String description,
  }) async {
    try {
      // 1. Chamar Cloud Function para criar o PaymentIntent
      final HttpsCallable callable =
          FirebaseFunctions.instance.httpsCallable('createStripePaymentIntent');

      final response = await callable.call({
        'amount': (amount * 100).toInt(), // Stripe usa centavos
        'currency': currency,
        'description': description,
      });

      final clientSecret = response.data['clientSecret'];

      // 2. Inicializar o Payment Sheet com tema visual do app
      await Stripe.instance.initPaymentSheet(
        paymentSheetParameters: SetupPaymentSheetParameters(
          paymentIntentClientSecret: clientSecret,
          merchantDisplayName: 'MarkaAI',
          appearance: _appAppearance,
          style: ThemeMode.light,
        ),
      );

      // 3. Exibir o Payment Sheet
      await Stripe.instance.presentPaymentSheet();

      return true;
    } on StripeException catch (e) {
      debugPrint(
          '[StripeService] StripeException (one-time): ${e.error.localizedMessage}');
      return false;
    } catch (e) {
      debugPrint('[StripeService] Error in processOneTimePayment: $e');
      return false;
    }
  }
}
