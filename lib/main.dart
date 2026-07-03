import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:windows_single_instance/windows_single_instance.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'core/utils/url_strategy_stub.dart'
    if (dart.library.html) 'core/utils/url_strategy_web.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'core/theme/app_colors.dart';
import 'core/router/app_router.dart';
import 'modules/business/mobile_subscription_manager.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'core/constants/api_keys.dart';
import 'package:app_links/app_links.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'modules/business/business_schedule_page.dart';

import 'core/services/session_service.dart';
import 'core/services/shop_data_cache_service.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'core/widgets/ios_pwa_install_banner.dart';

void main(List<String> args) async {
  try {
    WidgetsFlutterBinding.ensureInitialized();

    // Bloqueia logs de debug em produção (evita vazamento de dados via logcat/console)
    if (kReleaseMode) {
      debugPrint = (String? message, {int? wrapWidth}) {};
    }

    debugPrint("=== BOOT STEP 0: v2 - FlutterBinding Inicializado ===");
    
    // === BOOT STEP 0.5: Iniciando Firebase ===
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    print('=== BOOT STEP 0.5: Firebase Inicializado ===');

    // 1. Inicializar Supabase (obrigatório antes de runApp)
    print("=== BOOT STEP 1.1: Iniciando Supabase ===");
    await Supabase.initialize(
      url: ApiKeys.supabaseUrl,
      anonKey: ApiKeys.supabaseAnonKey,
      authOptions: const FlutterAuthClientOptions(
        authFlowType: AuthFlowType.pkce,
      ),
    );
    print("=== BOOT STEP 1: Supabase Inicializado ===");

    // 1.5 Inicializar Deep Links (OAuth Callback)
    print("=== BOOT STEP 1.5: Configurando Deep Links ===");

    // Função auxiliar centralizada para processar o link e fazer login
    Future<void> handleAuthLink(Uri uri) async {
      final String uriString = uri.toString();
      debugPrint("\n\n=== [DEEP LINK RECEBIDO] ===");
      debugPrint("URL Completa: $uriString");

      try {
        if (uriString.contains('code=') || uriString.contains('access_token=') || uriString.contains('refresh_token=')) {
          debugPrint("=== [DEEP LINK] Iniciando recuperação de sessão Supabase... ===");
          await Supabase.instance.client.auth.getSessionFromUrl(uri);
          debugPrint("=== [DEEP LINK] SUCESSO: Sessão recuperada! ===");
        }
      } catch (e) {
        debugPrint("=== [DEEP LINK] ERRO ao processar link: $e ===");
      }
      debugPrint("==============================\n\n");
    }

    if (kIsWeb) {
      // No Web o Supabase lida automaticamente com o fragmento da URL
    } else if (Platform.isWindows) {
      // --- LÓGICA SINGLE INSTANCE (WINDOWS) ---
      await WindowsSingleInstance.ensureSingleInstance(
        args,
        "markaai_unique_instance_id",
        onSecondWindow: (newArgs) async {
          debugPrint("=== [SINGLE INSTANCE] Segunda janela detectada com args: $newArgs ===");
          if (newArgs.isNotEmpty) {
            final url = newArgs.first;
            if (url.startsWith('markaai://')) {
              await handleAuthLink(Uri.parse(url));
            }
          }
        },
      );

      // Trata Cold Start no Windows (quando o app abre pelo link)
      if (args.isNotEmpty) {
        final url = args.first;
        if (url.startsWith('markaai://')) {
          debugPrint("=== [DEEP LINK] Windows Cold Start detectado ===");
          await handleAuthLink(Uri.parse(url));
        }
      }
    } else {
      // --- LÓGICA MOBILE (ANDROID/IOS) ---
      final appLinks = AppLinks();
      
      // Captura URI que abriu o app (cold start mobile)
      try {
        final initialUri = await appLinks.getInitialLink();
        if (initialUri != null) {
          debugPrint("=== [DEEP LINK] Mobile Cold Start detectado ===");
          await handleAuthLink(initialUri);
        }
      } catch (e) {
        debugPrint("=== [DEEP LINK] Erro ao obter link inicial mobile: $e ===");
      }

      // Captura URI com app já aberto (mobile stream)
      appLinks.uriLinkStream.listen((uri) async {
        debugPrint("=== [DEEP LINK] Mobile recebeu link via stream ===");
        await handleAuthLink(uri);
      });
    }

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

    // 4.5 Configurar tap em notificações nativas (Firebase Messaging)
    if (!kIsWeb && defaultTargetPlatform != TargetPlatform.windows) {
      try {
        FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) async {
          debugPrint("=== ON MESSAGE OPENED APP (Notificação Clicada) ===");
          final String? dateStr = message.data['scheduled_at'] ?? message.data['appointmentDate'] ?? message.data['date'];
          final String? appointmentId = message.data['appointment_id'];
          if (dateStr != null && dateStr.isNotEmpty) {
            final DateTime? date = DateTime.tryParse(dateStr);
            if (date != null) {
              final shopId = await SessionService.getShopId();
              if (shopId != null && shopId.isNotEmpty) {
                // Navega para a agenda abrindo no agendamento exato
                MarkaAIApp.navigatorKey.currentState?.push(
                  MaterialPageRoute(
                    builder: (context) => BusinessSchedulePage(
                      shopId: shopId,
                      initialDate: date,
                      initialAppointmentId: appointmentId,
                    ),
                  ),
                );
              }
            }
          }
        });
        
        // Handle terminated state (cold boot)
        FirebaseMessaging.instance.getInitialMessage().then((RemoteMessage? message) async {
          if (message != null) {
            debugPrint("=== GET INITIAL MESSAGE (Notificação Clicada c/ app fechado) ===");
            final String? dateStr = message.data['scheduled_at'] ?? message.data['appointmentDate'] ?? message.data['date'];
            final String? appointmentId = message.data['appointment_id'];
            if (dateStr != null && dateStr.isNotEmpty) {
              final DateTime? date = DateTime.tryParse(dateStr);
              if (date != null) {
                // Aguarda roteamento inicial da auth resolver e puxa a tela
                Future.delayed(const Duration(seconds: 4), () async {
                  final shopId = await SessionService.getShopId();
                  if (shopId != null && shopId.isNotEmpty) {
                    MarkaAIApp.navigatorKey.currentState?.push(
                      MaterialPageRoute(
                        builder: (context) => BusinessSchedulePage(
                          shopId: shopId,
                          initialDate: date,
                          initialAppointmentId: appointmentId,
                        ),
                      ),
                    );
                  }
                });
              }
            }
          }
        });
      } catch (e) {
        debugPrint("=== erro no firebase messaging listen: $e ===");
      }
    }

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
    if (!kIsWeb && defaultTargetPlatform != TargetPlatform.windows) {
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
      builder: (context, child) {
        return IosPwaInstallBanner(child: child ?? const SizedBox.shrink());
      },
    );
  }
}

// Comentado: Classes AuthGate e AuthRedirect movidas para app_router.dart
