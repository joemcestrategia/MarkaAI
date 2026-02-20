import 'package:flutter/material.dart';
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

// 🚨 IMPORTANTE: Importe o arquivo que o comando gerou
import 'firebase_options.dart';

// Handler para notificações em background (DEVE estar fora da main)
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await firebaseMessagingBackgroundHandler(message);
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Configure path-based URLs (remove #) on web hosting
  configurePathUrlStrategy();

  // Inicializar Firebase
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Inicializar IAP (In-App Purchases)
  // Importante estar aqui para escutar streams de compra restaurada/pendente
  // O Manager tem proteção interna para Web.

  // Inicializar IAP (In-App Purchases)
  await MobileSubscriptionManager.initialize();

  // Configurar handler de background ANTES de qualquer outra coisa
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

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
  FirebaseMessaging.instance.getInitialMessage().then((RemoteMessage? message) {
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

  runApp(const MarkaAIApp());
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
