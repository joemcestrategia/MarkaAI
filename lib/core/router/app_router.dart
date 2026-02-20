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

class AppRouter {
  static Route<dynamic> generateRoute(RouteSettings settings) {
    final uri = Uri.parse(settings.name ?? '/');
    final path = uri.path;

    // Remover barras extras
    final cleanPath =
        path.replaceAll(RegExp(r'^/+'), '').replaceAll(RegExp(r'/+$'), '');

    // 🆕 Suporte para redirecionamento via query param (evita loops de rewrite no Firebase)
    // Se a URL for /?s=afroed, tratamos como se fosse /afroed
    final querySlug = uri.queryParameters['s'];
    if (querySlug != null && querySlug.isNotEmpty) {
      return MaterialPageRoute(
        builder: (_) => PublicShopPage(slug: querySlug),
        settings: settings,
      );
    }

    // Se está vazio, é a home - usar o AuthGate
    if (cleanPath.isEmpty) {
      return MaterialPageRoute(
        builder: (_) => const AuthGate(),
        settings: settings,
      );
    }

    // Se tem apenas um segmento, pode ser um slug
    final segments = cleanPath.split('/');
    if (segments.length == 1) {
      final slug = segments[0];

      // Verificar se não é uma rota conhecida
      if (!_isKnownRoute(slug)) {
        // Trata como slug de loja
        return MaterialPageRoute(
          builder: (_) => PublicShopPage(slug: slug),
          settings: settings,
        );
      }
    }

    // Rotas fixas conhecidas (admin)
    if (cleanPath.toLowerCase() == 'inventory') {
      return MaterialPageRoute(
          builder: (_) => const InventoryHomePage(), settings: settings);
    }
    if (cleanPath.toLowerCase() == 'admin/plans') {
      return MaterialPageRoute(
          builder: (_) => const PlansPage(), settings: settings);
    }
    if (cleanPath.toLowerCase() == 'subscription_plans') {
      // Lazy import to avoid circular dependency if possible, or ensure import exists
      return MaterialPageRoute(
          builder: (_) => const SubscriptionPlansPage(), settings: settings);
    }
    if (cleanPath.toLowerCase() == 'admin') {
      return MaterialPageRoute(
          builder: (_) => const AdminPage(), settings: settings);
    }

    // Rota não encontrada
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
      'admin',
      'settings',
      'profile',
      'checkout',
      'payment',
      'success',
      'payment',
      'success',
      'error',
      'subscription_plans',
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

      final data = doc.data();
      final tipo = data?['tipo']?.toString() ?? 'cliente';

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

      // Se a rota atual não for a raiz, não redirecionamos automaticamente.
      // Usar Uri.base.path (funciona no web) como fonte mais confiável do caminho atual.
      final browserPath = Uri.base.path; // ex: '/afroed' ou '/'
      if (browserPath == '/' || browserPath.isEmpty) {
        // Garantir que o widget ainda está montado após possíveis 'await's acima
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
      } else {
        // Não forçar redirecionamento: respeitar URL atual (ex: /{slug})
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
