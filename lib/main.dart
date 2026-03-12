import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'core/utils/url_strategy_stub.dart'
    if (dart.library.html) 'core/utils/url_strategy_web.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'core/theme/app_colors.dart';
import 'core/services/notification_service.dart';
import 'core/router/app_router.dart';
import 'modules/clients/appointment_confirmation_page.dart';
import 'modules/business/mobile_subscription_manager.dart';
import 'package:flutter_stripe/flutter_stripe.dart';

// ðŸš¨ IMPORTANTE: Importe o arquivo que o comando gerou
import 'firebase_options.dart';

// Handler para notificações em background (DEVE estar fora da main)
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await firebaseMessagingBackgroundHandler(message);
}

void main() async {
  try {
    WidgetsFlutterBinding.ensureInitialized();
    debugPrint("=== BOOT STEP 0: FlutterBinding Inicializado ===");

    // 1. Inicializar Firebase primeiro (essencial para quase tudo)
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    debugPrint("=== BOOT STEP 1: Firebase Inicializado ===");

    // 2. Configurar handler de background imediatamente após Firebase
    if (!kIsWeb) {
      FirebaseMessaging.onBackgroundMessage(
          _firebaseMessagingBackgroundHandler);
      debugPrint(
          "=== BOOT STEP 2: FCM Background Handler (Mobile) Configurado ===");
    } else {
      debugPrint("=== BOOT STEP 2: FCM Ignorado (Web) ===");
    }

    // 3. Inicializar Stripe
    if (!kIsWeb) {
      Stripe.publishableKey =
          'pk_live_51T97xzFzh8r5AMGzlcuoTt9mxupvYn3fD9UznF7pdPNxxZI4W0Jn6xb36tYKlSvtUnb7544CeIXtDX84XshUk6dF00d10axLwi';
      try {
        await Stripe.instance.applySettings();
        debugPrint("=== BOOT STEP 3: Stripe API (Mobile) Configurado ===");
      } catch (e) {
        debugPrint("=== BOOT STEP 3 ERRO: Stripe Falhou = $e ===");
      }
    } else {
      debugPrint("=== BOOT STEP 3: Stripe Configurado (Web key) ===");
    }

    // 4. Configure path-based URLs (remove #) on web hosting
    configurePathUrlStrategy();
    debugPrint("=== BOOT STEP 4: Path URL Strategy Configurado ===");

    // 5. Inicializar IAP (In-App Purchases) - Perigosíssimo no Web
    if (!kIsWeb) {
      try {
        await MobileSubscriptionManager.initialize();
        debugPrint("=== BOOT STEP 5: Mobile IAP Inicializado ===");
      } catch (e) {
        debugPrint("=== BOOT STEP 5 ERRO: Falha ao inicializar IAP = $e ===");
      }
    } else {
      debugPrint("=== BOOT STEP 5: Mobile IAP Ignorado (Web) ===");
    }

    // Configurar handler de notificações (deep link para confirmação de agendamento)
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      final appointmentId = message.data['appointmentId'];
      final type = message.data['type'];
      if (appointmentId != null && type == 'confirmacao') {
        // Navegar para página de confirmação quando app está em background e usuário clica na notificação
        WidgetsBinding.instance.addPostFrameCallback((_) {
          MarkaAIApp.navigatorKey.currentState?.push(
            MaterialPageRoute(
              builder: (_) =>
                  AppointmentConfirmationPage(appointmentId: appointmentId),
            ),
          );
        });
      }
    });

    // Notificação quando app está fechado e usuário abre via notificação
    FirebaseMessaging.instance
        .getInitialMessage()
        .then((RemoteMessage? message) {
      if (message != null) {
        final appointmentId = message.data['appointmentId'];
        final type = message.data['type'];
        if (appointmentId != null && type == 'confirmacao') {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            MarkaAIApp.navigatorKey.currentState?.push(
              MaterialPageRoute(
                builder: (_) =>
                    AppointmentConfirmationPage(appointmentId: appointmentId),
              ),
            );
          });
        }
      }
    });

    // Notificação recebida quando app está em foreground (tratada em cada página)
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      // Cada página (BusinessHomePage, ClientHomePage) trata suas próprias notificações
    });

    debugPrint("=== BOOT FINAL: Executando runApp ===");
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
      title: 'MarkaAI.app',
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
