import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/session_service.dart';

class StripeService {
  static final StripeService instance = StripeService._();
  StripeService._();

  static final _supabase = Supabase.instance.client;

  /// URL base do Edge Function de sucesso do checkout
  static String get _successFunctionUrl {
    final supabaseUrl = _supabase.rest.url.replaceAll('/rest/v1', '');
    return '$supabaseUrl/functions/v1/stripe-checkout-success';
  }

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

  // A atualização do banco via app (_updatePlanInSupabase) foi REJEITADA.
  // Todo o fluxo de liberação do produto final agora é exclusivamente garantido
  // pelo 'stripe-webhook' rodando no servidor.  // ════════════════════════════════════════════════════════════
  //  WEB: Stripe Checkout Sessions (redirect para página hospedada)
  // ════════════════════════════════════════════════════════════

  /// Calcula a URL base do app para redirects (Web)
  static String _getAppBaseUrl() {
    // Em produção usa a URL do browser; fallback para Firebase Hosting
    try {
      final base = Uri.base;
      return '${base.scheme}://${base.host}${base.hasPort ? ':${base.port}' : ''}';
    } catch (_) {
      return 'https://wismart-118c3.web.app';
    }
  }

  /// Cria Checkout Session no Stripe e abre a página de pagamento (Web)
  Future<bool> _webCheckoutSubscription({
    required String planId,
    required String shopId,
    required String customerEmail,
  }) async {
    final appBaseUrl = _getAppBaseUrl();
    final successUrl =
        '$_successFunctionUrl?app_url=${Uri.encodeComponent('$appBaseUrl/payment-success')}';
    final cancelUrl = '$appBaseUrl/subscription_plans';

    final response = await _supabase.functions.invoke(
      'create-stripe-checkout-session',
      body: {
        'mode': 'subscription',
        'plan_id': planId,
        'shop_id': shopId,
        'email': customerEmail,
        'success_url': successUrl,
        'cancel_url': cancelUrl,
      },
    );

    if (response.status != 200) {
      final errMsg = response.data is Map
          ? (response.data['error'] ?? 'Erro ao criar sessão de checkout.')
          : 'Erro ao criar sessão de checkout.';
      throw Exception(errMsg);
    }

    final url = response.data['url'] as String?;
    if (url == null || url.isEmpty) {
      throw Exception('URL de checkout não retornada pelo servidor.');
    }

    debugPrint('[StripeService] Abrindo Stripe Checkout (Web): $url');
    final launched = await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.inAppBrowserView,
      webOnlyWindowName: '_self',
    );
    if (!launched) {
      throw Exception('Não foi possível abrir a página de pagamento.');
    }

    // Na Web, o redirect acontece na mesma aba. O retorno aqui não é alcançado
    // após o redirect, mas retornamos true para o caso de popups bloqueados etc.
    return true;
  }

  /// Cria Checkout Session para pagamento avulso e abre a página (Web)
  Future<bool> _webCheckoutOneTime({
    required double amount,
    required String currency,
    required String description,
    String? shopId,
    int? boostDays,
  }) async {
    final appBaseUrl = _getAppBaseUrl();
    final successUrl =
        '$_successFunctionUrl?app_url=${Uri.encodeComponent('$appBaseUrl/payment-success')}';
    final cancelUrl = appBaseUrl;

    final email = _supabase.auth.currentUser?.email;

    final response = await _supabase.functions.invoke(
      'create-stripe-checkout-session',
      body: {
        'mode': 'payment',
        'amount': (amount * 100).toInt(),
        'currency': currency,
        'description': description,
        'success_url': successUrl,
        'cancel_url': cancelUrl,
        if (shopId != null) 'shop_id': shopId,
        if (email != null) 'email': email,
        if (boostDays != null) 'boost_days': boostDays,
      },
    );

    if (response.status != 200) {
      final errMsg = response.data is Map
          ? (response.data['error'] ?? 'Erro ao criar sessão de checkout.')
          : 'Erro ao criar sessão de checkout.';
      throw Exception(errMsg);
    }

    final url = response.data['url'] as String?;
    if (url == null || url.isEmpty) {
      throw Exception('URL de checkout não retornada pelo servidor.');
    }

    debugPrint('[StripeService] Abrindo Stripe Checkout OneTime (Web): $url');
    final launched = await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.inAppBrowserView,
      webOnlyWindowName: '_self',
    );
    if (!launched) {
      throw Exception('Não foi possível abrir a página de pagamento.');
    }
    return true;
  }

  // ════════════════════════════════════════════════════════════
  //  MOBILE: Payment Sheet nativo (existente)
  // ════════════════════════════════════════════════════════════

  /// Inicializa o Payment Sheet para uma Assinatura (Subscription)
  Future<bool> setupSubscriptionPayment({
    required String planId,
    required String shopId,
    required String customerEmail,
  }) async {
    // ── WEB → Checkout Session com redirect ──────────────────
    if (kIsWeb) {
      return _webCheckoutSubscription(
        planId: planId,
        shopId: shopId,
        customerEmail: customerEmail,
      );
    }

    // ── MOBILE → Payment Sheet nativo ────────────────────────
    try {
      // 1. Chamar Supabase Function para criar o cliente/assinatura
      final response = await _supabase.functions.invoke('create-stripe-subscription', body: {
        'plan_id': planId,
        'shop_id': shopId,
        'email': customerEmail,
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
      await Stripe.instance.presentPaymentSheet();

      // 4. Pagamento processado na Stripe
      // O Edge Function `stripe-webhook` será engatilhado automaticamente
      // e o Client receberá as novidades via Stream Realtime do Supabase.

      return true;
    } on StripeException catch (e) {
      // Usuário cancelou ou erro Stripe
      debugPrint(
          '[StripeService] StripeException: ${e.error.localizedMessage}');
      if (e.error.code == FailureCode.Canceled) {
        return false; // cancelamento não é erro
      }
      rethrow;
    } catch (e) {
      debugPrint('[StripeService] Error in setupSubscriptionPayment: $e');
      rethrow;
    }
  }

  /// Inicializa o Payment Sheet para uma compra avulsa (Boost)
  Future<bool> processOneTimePayment({
    required double amount,
    required String currency,
    required String description,
    String? shopId,
    int? boostDays,
  }) async {
    // ── WEB → Checkout Session com redirect ──────────────────
    if (kIsWeb) {
      return _webCheckoutOneTime(
        amount: amount,
        currency: currency,
        description: description,
        shopId: shopId,
        boostDays: boostDays,
      );
    }

    // ── MOBILE → Payment Sheet nativo ────────────────────────
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
      await Stripe.instance.presentPaymentSheet();

      return true;
    } on StripeException catch (e) {
      debugPrint(
          '[StripeService] StripeException (one-time): ${e.error.localizedMessage}');
      if (e.error.code == FailureCode.Canceled) {
        return false; // cancelamento não é erro
      }
      rethrow;
    } catch (e) {
      debugPrint('[StripeService] Error in processOneTimePayment: $e');
      rethrow;
    }
  }

  /// Verifica o status de uma Checkout Session (chamado após redirect de sucesso)
  Future<Map<String, dynamic>?> verifyCheckoutSession(String sessionId) async {
    try {
      final response = await _supabase.functions.invoke(
        'stripe-checkout-success',
        body: {'session_id': sessionId},
      );
      if (response.status == 200 && response.data is Map) {
        return Map<String, dynamic>.from(response.data);
      }
      return null;
    } catch (e) {
      debugPrint('[StripeService] verifyCheckoutSession error: $e');
      return null;
    }
  }
}
