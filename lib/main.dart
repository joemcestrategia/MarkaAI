import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'core/utils/url_strategy_stub.dart'
    if (dart.library.html) 'core/utils/url_strategy_web.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'core/theme/app_colors.dart';
import 'core/router/app_router.dart';
import 'modules/business/mobile_subscription_manager.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'core/constants/api_keys.dart';


import 'core/services/session_service.dart';
import 'core/services/shop_data_cache_service.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

void main() async {
  try {
    WidgetsFlutterBinding.ensureInitialized();
    print("=== BOOT STEP 0: v2 - FlutterBinding Inicializado ===");
    
    // 1. Inicializar Supabase (obrigatório antes de runApp)
    print("=== BOOT STEP 1.1: Iniciando Supabase ===");
    await Supabase.initialize(
      url: ApiKeys.supabaseUrl,
      anonKey: ApiKeys.supabaseAnonKey,
      authOptions: const FlutterAuthClientOptions(
        authFlowType: AuthFlowType.implicit,
      ),
    );
    print("=== BOOT STEP 1: Supabase Inicializado ===");

    // 2. Inicializar SessionService (obrigatório para roteamento)
    print("=== BOOT STEP 2: Iniciando SessionService ===");
    await SessionService.init();
    print("=== BOOT STEP 2: SessionService Inicializado ===");

    // 3. Configurar Stripe key (síncrono, não bloqueia)
    try {
      if (!kIsWeb) {
        print("=== BOOT STEP 3.1: Configurando Stripe Key (Mobile) ===");
        Stripe.publishableKey = ApiKeys.stripePublishableKey;
        print("=== BOOT STEP 3.2: Stripe Key Configurada (Mobile) ===");
      }
    } catch (e) {
      print("=== BOOT STEP 3.0 ERRO: Stripe Key Falhou = $e ===");
    }

    // 4. Configure path-based URLs (remove #) on web hosting
    print("=== BOOT STEP 4: Configurando Path Strategy ===");
    configurePathUrlStrategy();

    // ──────────────────────────────────────────────────────────────────────────
    // runApp() é chamado AGORA — a splash Flutter personalizada cobre a splash
    // nativa imediatamente, sem aguardar IAP / Ads / Cache.
    // ──────────────────────────────────────────────────────────────────────────
    ErrorWidget.builder = (FlutterErrorDetails details) {
      return Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'ERRO: ${details.exception}\n\n${details.stack}',
              style: const TextStyle(color: Colors.red, fontSize: 12),
            ),
          ),
        ),
      );
    };
    print("=== BOOT STEP 5: Executando runApp ===");
    runApp(const MarkaAIApp());

    // 5–7. Init pesados rodam em background (não bloqueiam a splash)
    if (!kIsWeb) {
      // Stripe applySettings
      Stripe.instance.applySettings().catchError((e) {
        print("=== BOOT BG: Stripe applySettings falhou = $e ===");
      });

      // IAP
      MobileSubscriptionManager.initialize().catchError((e) {
        print("=== BOOT BG: Mobile IAP falhou = $e ===");
      });

      // Mobile Ads
      MobileAds.instance.initialize().catchError((e) {
        print("=== BOOT BG: Mobile Ads falhou = $e ===");
        return InitializationStatus({});
      });
    }

    // Cache de dados da loja (não é bloqueante)
    ShopDataCacheService.init().catchError((e) {
      print("=== BOOT BG: ShopDataCacheService falhou = $e ===");
    });

    print("=== BOOT COMPLETO: init background disparado ===");
  } catch (globalError, stackTrace) {
    debugPrint("=== BOOT PARALISOU TOTALMENTE: $globalError ===");
    debugPrint(stackTrace.toString());
  }
}

class MarkaAIApp extends StatelessWidget {
  const MarkaAIApp({super.key});

  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'MarkaAI.com.br',
      debugShowCheckedModeBanner: false,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('pt', 'BR'),
      ],
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.primaryPurple,
          secondary: AppColors.gold,
        ),
        scaffoldBackgroundColor: AppColors.background,
      ),
      // Roteamento personalizado para suportar slugs
      onGenerateRoute: AppRouter.generateRoute,
    );
  }
}

// Comentado: Classes AuthGate e AuthRedirect movidas para app_router.dart
