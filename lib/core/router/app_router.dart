import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import '../../modules/login/login_page.dart';
import '../../modules/public/public_shop_page.dart';
import '../../modules/business/business_home_page.dart';
import '../../modules/clients/client_home_page.dart';
import '../../modules/admin/plans_page.dart';
import '../../modules/admin/admin_page.dart';
import '../../core/theme/app_colors.dart';
import '../../modules/inventory/inventory_home_page.dart';
import '../../modules/business/subscription_plans_page.dart';
import '../../modules/auth/reset_password_page.dart';
import '../../modules/clients/rescheduling_success_page.dart';

class AppRouter {
  static Route<dynamic> generateRoute(RouteSettings settings) {
    // 1. Determinar o caminho (path) real. No Web, Uri.base é mais confiável para deep links iniciais.
    String pathName = settings.name ?? '/';

    debugPrint('ðŸš© AppRouter: settings.name = "$pathName"');

    // Correção para Cold Boot no Web: se o path for '/', verificamos a URL real do browser
    if (pathName == '/') {
      final browserPath = Uri.base.path;
      debugPrint(
          'ðŸš© AppRouter: Web cold-boot detectado. Uri.base.path = "$browserPath"');
      if (browserPath != '/' && browserPath.isNotEmpty) {
        pathName = browserPath;
      }
    }

    final uri = Uri.parse(pathName);
    final path = uri.path;

    // Remover barras extras e normalizar
    final cleanPath = path
        .replaceAll(RegExp(r'^/+'), '')
        .replaceAll(RegExp(r'/+$'), '')
        .trim();

    debugPrint('ðŸš© AppRouter: Final cleanPath = "$cleanPath"');

    // 2. Traduzir query param 's' para slug (fallback/compatibilidade)
    final querySlug = uri.queryParameters['s'];
    if (querySlug != null && querySlug.isNotEmpty) {
      return MaterialPageRoute(
        builder: (_) => PublicShopPage(slug: querySlug),
        settings: settings,
      );
    }

    // Tratamento estrito do Firebase Link Action caso seja pego apenas aqui
    if (uri.path == '/__/') {
      final mode = uri.queryParameters['mode'];
      final oobCode = uri.queryParameters['oobCode'];
      if (mode == 'resetPassword' && oobCode != null) {
        return MaterialPageRoute(
          builder: (_) => ResetPasswordPage(oobCode: oobCode),
          settings: settings,
        );
      }
    }

    // Capture Firebase Action Link (Password Reset)
    final mode = uri.queryParameters['mode'];
    final oobCode = uri.queryParameters['oobCode'];

    if (mode == 'resetPassword' && oobCode != null && oobCode.isNotEmpty) {
      return MaterialPageRoute(
        builder: (_) => ResetPasswordPage(oobCode: oobCode),
        settings: settings,
      );
    }

    if (cleanPath == 'reschedule_success') {
      final args = settings.arguments as Map<String, dynamic>? ?? {};
      return MaterialPageRoute(
        builder: (_) => RescheduleSuccessPage(
          appointmentId: args['appointmentId'] ?? '',
          newDate: args['newDate'] ?? DateTime.now(),
          newProfessional: args['newProfessional'] ?? '',
          newServiceName: args['newServiceName'] ?? '',
          oldDate: args['oldDate'],
          oldProfessional: args['oldProfessional'] ?? '',
          oldServiceName: args['oldServiceName'] ?? '',
        ),
        settings: settings,
      );
    }

    // 3. Rota Raiz (Home)
    if (cleanPath.isEmpty) {
      return MaterialPageRoute(
        builder: (_) => const AuthGate(),
        settings: settings,
      );
    }

    // 3b. Rota client_home → vai direto para o AuthGate que redireciona o cliente logado
    if (cleanPath == 'client_home') {
      return MaterialPageRoute(
        builder: (_) => const AuthGate(),
        settings: settings,
      );
    }

    // 4. Tratamento de Slugs Dinâmicos (/:slug)
    final segments = cleanPath.split('/');
    if (segments.length == 1) {
      final slug = segments[0];

      // Se NÃO for uma rota fixa conhecida da aplicação, tratamos como slug de loja
      if (!_isKnownRoute(slug)) {
        return MaterialPageRoute(
          builder: (_) => PublicShopPage(slug: slug),
          settings: settings,
        );
      }
    }

    // 5. Verificar Rotas Conhecidas
    final baseRoute = cleanPath.split('/')[0].toLowerCase();

    // Rotas Admin/Inventory que NÃO precisam do AuthGate global aqui (já possuem interna ou via switch)
    if (baseRoute == 'inventory') {
      return MaterialPageRoute(
          builder: (_) => const InventoryHomePage(), settings: settings);
    }
    if (cleanPath.toLowerCase() == 'admin/plans') {
      return MaterialPageRoute(
          builder: (_) => const PlansPage(), settings: settings);
    }
    if (baseRoute == 'admin') {
      return MaterialPageRoute(
          builder: (_) => const AdminPage(), settings: settings);
    }
    if (baseRoute == 'subscription_plans') {
      return MaterialPageRoute(
          builder: (_) => const SubscriptionPlansPage(), settings: settings);
    }

    // 6. Outras Rotas Conhecidas que devem passar pelo AuthGate (login, home, business, client)
    if (_isKnownRoute(baseRoute)) {
      return MaterialPageRoute(
        builder: (_) => const AuthGate(),
        settings: settings,
      );
    }

    // 7. Rota não encontrada
    return MaterialPageRoute(
      builder: (_) => Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 80, color: Colors.grey),
              const SizedBox(height: 20),
              Text(
                'Página não encontrada',
                style:
                    const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              Text(
                path,
                style: const TextStyle(color: Colors.grey),
              ),
            ],
          ),
        ),
      ),
      settings: settings,
    );
  }

  static bool _isKnownRoute(String route) {
    const knownRoutes = [
      'login',
      'register',
      'home',
      'business',
      'client',
      'client_home',
      'admin',
      'settings',
      'profile',
      'checkout',
      'payment',
      'success',
      'error',
      'subscription_plans',
      'reschedule_success',
    ];
    return knownRoutes.contains(route.toLowerCase());
  }
}

// Auth Gate - gerencia autenticação e redirecionamento
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(color: AppColors.primaryPurple),
            ),
          );
        }

        if (snapshot.hasData) {
          return AuthRedirect(user: snapshot.data!);
        }

        return const LoginPage();
      },
    );
  }
}

// Auth Redirect - redireciona baseado no tipo de usuário
class AuthRedirect extends StatefulWidget {
  final User user;

  const AuthRedirect({super.key, required this.user});

  @override
  State<AuthRedirect> createState() => _AuthRedirectState();
}

class _AuthRedirectState extends State<AuthRedirect> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _resolve());
  }

  Future<void> _resolve() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.user.uid)
          .get();

      if (!mounted) return;

      if (!doc.exists) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const LoginPage()),
        );
        return;
      }

      final data = doc.data();
      final tipo = data?['tipo']?.toString();
      final telefone = data?['telefone']?.toString();

      if (tipo == null ||
          tipo.isEmpty ||
          telefone == null ||
          telefone.isEmpty) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const LoginPage()),
        );
        return;
      }

      // Registrar token FCM do dispositivo para notificações (se disponível)
      try {
        final token = await FirebaseMessaging.instance.getToken();
        if (token != null) {
          await FirebaseFirestore.instance
              .collection('users')
              .doc(widget.user.uid)
              .update({
            'fcmTokens': FieldValue.arrayUnion([token])
          });
        }
      } catch (_) {}

      // Forçar redirecionamento para Home do perfil logado
      if (!mounted) return;
      if (tipo == 'dono' || tipo == 'business') {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const BusinessHomePage()),
        );
      } else {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const ClientHomePage()),
        );
      }
    } catch (_) {
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const LoginPage()),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: CircularProgressIndicator(color: AppColors.primaryPurple),
      ),
    );
  }
}
