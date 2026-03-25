import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/session_service.dart';

class StripeService {
  static final StripeService instance = StripeService._();
  StripeService._();

  static final _supabase = Supabase.instance.client;

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

  /// Atualiza o plano no Supabase imediatamente após pagamento aprovado
  static Future<void> _updatePlanInSupabase(
    String planId, {
    String? stripeSubscriptionId,
    String? stripeCustomerId,
  }) async {
    try {
      String? shopId = await SessionService.getShopId();
      if (shopId == null) {
        final user = _supabase.auth.currentUser;
        if (user != null) {
          final userDoc = await _supabase
              .from('users')
              .select('shop_id')
              .eq('id', user.id)
              .maybeSingle();
          shopId = userDoc?['shop_id']?.toString();
        }
      }
      if (shopId == null) return;

      await _supabase.from('shops').update({
        'plan_id': planId,
        'trial_active': false,
        'subscription': {
          'plan_id': planId,
          'status': 'active',
          'payment_provider': 'stripe',
          if (stripeSubscriptionId != null)
            'stripe_subscription_id': stripeSubscriptionId,
          if (stripeCustomerId != null)
            'stripe_customer_id': stripeCustomerId,
          'updated_at': DateTime.now().toIso8601String(),
        },
      }).eq('id', shopId);

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
    String? affiliateId,
    String? affiliateCouponCode,
    String? commissionType,
  }) async {
    try {
      // 1. Chamar Supabase Function para criar o cliente/assinatura
      final response = await _supabase.functions.invoke('create-stripe-subscription', body: {
        'plan_id': planId,
        'shop_id': shopId,
        'email': customerEmail,
        'affiliate_id': affiliateId,
        'affiliate_coupon_code': affiliateCouponCode,
        'commission_type': commissionType,
      });

      if (response.status != 200) {
        final errMsg = response.data is Map
            ? (response.data['error'] ?? response.data['message'] ?? 'Erro ao criar assinatura no Stripe.')
            : 'Erro ao criar assinatura no Stripe.';
        throw Exception(errMsg);
      }

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
      if (kIsWeb) {
        debugPrint('[StripeService] PaymentSheet not supported on Web.');
        throw Exception('Pagamento via Modal não disponível na Web. Por favor, use o app ou entre em contato.');
      }
      await Stripe.instance.presentPaymentSheet();

      // 4. Pagamento aprovado — atualizar plano no Supabase imediatamente
      final String? subscriptionId = data['subscriptionId'];
      await _updatePlanInSupabase(
        planId,
        stripeSubscriptionId: subscriptionId,
        stripeCustomerId: customerId,
      );

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
    String? shopId,
  }) async {
    try {
      // 1. Chamar Supabase Function para criar o PaymentIntent
      final response = await _supabase.functions.invoke('create-stripe-payment-intent', body: {
        'amount': (amount * 100).toInt(), // Stripe usa centavos
        'currency': currency,
        'description': description,
        if (shopId != null) 'shop_id': shopId,
      });

      if (response.status != 200) {
        final errMsg = response.data is Map
            ? (response.data['error'] ?? response.data['message'] ?? 'Erro ao criar intenção de pagamento no Stripe.')
            : 'Erro ao criar intenção de pagamento no Stripe.';
        throw Exception(errMsg);
      }

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
      if (kIsWeb) {
        debugPrint('[StripeService] PaymentSheet (OneTime) not supported on Web.');
        throw Exception('Pagamento via Modal não disponível na Web.');
      }
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
