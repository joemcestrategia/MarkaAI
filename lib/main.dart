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



void main() async {
  try {
    WidgetsFlutterBinding.ensureInitialized();
    print("=== BOOT STEP 0: v2 - FlutterBinding Inicializado ===");
    
    // 1. Inicializar Supabase
    print("=== BOOT STEP 1.1: Iniciando Supabase ===");
    await Supabase.initialize(
      url: ApiKeys.supabaseUrl,
      anonKey: ApiKeys.supabaseAnonKey,
      authOptions: const FlutterAuthClientOptions(
        authFlowType: AuthFlowType.implicit,
      ),
    );
    print("=== BOOT STEP 1: Supabase Inicializado ===");

    // 3. Inicializar Stripe
    try {
      if (!kIsWeb) {
        print("=== BOOT STEP 3.1: Configurando Stripe Key (Mobile) ===");
        Stripe.publishableKey = ApiKeys.stripePublishableKey;
        print("=== BOOT STEP 3.2: Stripe Key Configurada (Mobile) ===");
      } else {
        print("=== BOOT STEP 3.1: Ignorando Stripe.publishableKey (Web) - Usando JS SDK ===");
      }
    } catch (e) {
      print("=== BOOT STEP 3.0 ERRO: Stripe Key Falhou = $e ===");
    }
    
    if (!kIsWeb) {
      try {
        print("=== BOOT STEP 3.3: Aplicando Configurações Stripe (Mobile) ===");
        await Stripe.instance.applySettings();
        print("=== BOOT STEP 3: Stripe API (Mobile) Configurado ===");
      } catch (e) {
        print("=== BOOT STEP 3 ERRO: Stripe Falhou = $e ===");
      }
    } else {
      print("=== BOOT STEP 3: Stripe Configurado (Web key) ===");
    }

    // 4. Configure path-based URLs (remove #) on web hosting
    print("=== BOOT STEP 4.1: Configurando Path Strategy ===");
    configurePathUrlStrategy();
    print("=== BOOT STEP 4: Path URL Strategy Configurado ===");

    // 5. Inicializar IAP (In-App Purchases) - Perigosíssimo no Web
    print("=== BOOT STEP 5.1: Checando IAP (kIsWeb=$kIsWeb) ===");
    if (!kIsWeb) {
      try {
        print("=== BOOT STEP 5.2: Inicializando Mobile IAP ===");
        await MobileSubscriptionManager.initialize();
        print("=== BOOT STEP 5: Mobile IAP Inicializado ===");
      } catch (e) {
        print("=== BOOT STEP 5 ERRO: Falha ao inicializar IAP = $e ===");
      }
    } else {
      print("=== BOOT STEP 5: Mobile IAP Ignorado (Web) ===");
    }

    print("=== BOOT STEP 6: Configurando ErrorWidget ===");
    print("=== BOOT FINAL: Executando runApp ===");
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
    runApp(const MarkaAIApp());
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
