import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../utils/html_stub.dart' if (dart.library.html) 'dart:html' as html;
import 'package:supabase_flutter/supabase_flutter.dart' as sb;
import '../../modules/login/login_page.dart';
import '../../modules/public/public_shop_page.dart';
import '../../modules/business/business_home_page.dart';
import '../../modules/clients/client_home_page.dart';
import '../../modules/auth/reset_password_page.dart';
import '../../core/theme/app_colors.dart';
import '../../modules/inventory/inventory_home_page.dart';
import '../../modules/business/subscription_plans_page.dart';
import '../../modules/clients/rescheduling_success_page.dart';
import '../../modules/business/price_adjustment_page.dart';
import '../../modules/admin/admin_dashboard_page.dart';
import '../../modules/admin/admin_setup_page.dart';
import '../../modules/clients/client_affiliate_page.dart';
import '../../core/services/session_service.dart';
import '../../core/services/auth_service.dart';
import '../../modules/public/affiliate_landing_page.dart';

class AppRouter {
  static Route<dynamic> generateRoute(RouteSettings settings) {
    // 1. Determinar o caminho (path) real. No Web, Uri.base é mais confiável para deep links iniciais.
    String pathName = settings.name ?? '/';

    debugPrint('AppRouter: settings.name = "$pathName"');

    // Correção para Cold Boot no Web: se o path for '/', verificamos a URL real do browser
    if (pathName == '/') {
      final browserPath = Uri.base.path;
      debugPrint(
          'AppRouter: Web cold-boot detectado. Uri.base.path = "$browserPath"');
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

    debugPrint('AppRouter: Final cleanPath = "$cleanPath"');

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
    if (baseRoute == 'admin') {
      return MaterialPageRoute(
          builder: (_) => const AdminAuthGate(), settings: settings);
    }
    if (cleanPath == 'setup-admin-secret') {
      return MaterialPageRoute(
          builder: (_) => const AdminSetupPage(), settings: settings);
    }
    if (cleanPath == 'afiliados') {
      return MaterialPageRoute(
          builder: (_) => const AffiliateLandingPage(), settings: settings);
    }
    if (cleanPath == 'afiliados/painel') {
      return MaterialPageRoute(
          builder: (_) => const ClientAffiliatePage(), settings: settings);
    }

    if (baseRoute == 'subscription_plans') {
      return MaterialPageRoute(
          builder: (_) => const SubscriptionPlansPage(), settings: settings);
    }
    if (cleanPath == 'payment-success') {
      return MaterialPageRoute(
          builder: (_) => const _PaymentSuccessPage(), settings: settings);
    }
    if (cleanPath == 'business/price_adjustment') {
      return MaterialPageRoute(
          builder: (_) => const PriceAdjustmentPage(), settings: settings);
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
      'business/price_adjustment',
      'setup-admin-secret',
      'afiliados',
      'afiliados/painel',
      'payment-success',
    ];
    return knownRoutes.contains(route.toLowerCase());
  }
}

// Auth Gate - gerencia autenticação e redirecionamento
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  Timer? _fallbackTimer;
  bool _timeoutReached = false;

  @override
  void initState() {
    super.initState();
    // Se estivermos na Web, iniciamos um timer de fallback para evitar 
    // congelamento eterno na tela de _SplashLoading() caso o SDK trave.
    if (kIsWeb) {
      _fallbackTimer = Timer(const Duration(seconds: 4), () {
        if (mounted) {
          setState(() {
            _timeoutReached = true;
          });
          debugPrint('AuthGate: Timeout atingido ao aguardar processamento da sessão inicial.');
          // Remove código da URL que possa estar travando o estado no navegador
          if (Uri.base.queryParameters.containsKey('code')) {
            html.window.history.replaceState(null, '', '/');
          }
        }
      });
    }
  }

  @override
  void dispose() {
    _fallbackTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final supabase = sb.Supabase.instance.client;

    return StreamBuilder<sb.AuthState>(
      stream: supabase.auth.onAuthStateChange,
      builder: (context, snapshot) {
        // Ainda carregando — aguarda o SDK processar
        if (!snapshot.hasData) {
          return const _SplashLoading();
        }

        final event = snapshot.data!.event;
        final session = snapshot.data!.session;

        // Limpa o ?code= da URL após o login (SIGNED_IN) no Web
        if (event == sb.AuthChangeEvent.signedIn && kIsWeb) {
          html.window.history.replaceState(null, '', '/');
        }

        // Detecta se há um código PKCE na URL (apenas no Web para evitar loop infinito na tela roxa)
        final bool hasCodeInUrl = kIsWeb && Uri.base.queryParameters.containsKey('code');

        // INITIAL_SESSION sem sessão = SDK ainda trocando o ?code= (SE hover code na URL)
        // NÃO redireciona para /login aqui para evitar flicker
        if (event == sb.AuthChangeEvent.initialSession && session == null && hasCodeInUrl) {
          // Mas caso o timeout do fallback já tenha estourado, seguimos em frente
          if (!_timeoutReached) {
            debugPrint('AuthGate: Aguardando processamento da sessão inicial (event=AuthChangeEvent.initialSession)...');
            return const _SplashLoading();
          }
        }
        
        // Se conseguirmos uma sessão válida (com ou sem código), limpamos o timer
        if (session != null) {
          _fallbackTimer?.cancel();
        }

        // Sem sessão e já passou do initial ou não tem code na URL, ou superou Timeout = deslogado
        if (session == null) {
          return const LoginPage();
        }

        // Sessão válida = vai para home
        return AuthRedirect(user: session.user);
      },
    );
  }
}

class _SplashLoading extends StatelessWidget {
  const _SplashLoading();
  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFF0A0A0F),
      body: Center(
        child: CircularProgressIndicator(color: Color(0xFF7C3AED)),
      ),
    );
  }
}

// Auth Redirect - gerencia redirecionamento baseado no tipo de usuário sem causar loops
class AuthRedirect extends StatefulWidget {
  final sb.User user;

  const AuthRedirect({super.key, required this.user});

  @override
  State<AuthRedirect> createState() => _AuthRedirectState();
}

class _AuthRedirectState extends State<AuthRedirect> {
  Widget? _targetPage;
  bool _error = false;
  String _errorMessage = '';

  bool _resolved = false;

  @override
  void initState() {
    super.initState();
    if (!_resolved) {
      _resolved = true;
      _resolve();
    }
    Future.delayed(const Duration(seconds: 10), () {
      if (mounted && _targetPage == null && !_error) {
        _setError('Timeout: operação demorou mais de 10s. Verifique o console.');
      }
    });
  }

  Future<void> _resolve() async {
    try {
      final supabase = sb.Supabase.instance.client;
      debugPrint('AuthRedirect: Buscando perfil para userId=${widget.user.id}');

      debugPrint('AuthRedirect: Executando SELECT...');
      final doc = await supabase
          .from('users')
          .select()
          .eq('id', widget.user.id)
          .maybeSingle();
      
      debugPrint('AuthRedirect: Resultado: $doc');

      if (!mounted) return;

      if (doc == null) {
        debugPrint('AuthRedirect: Perfil não encontrado ou incompleto para ${widget.user.email} — redirecionando temporariamente para login.');
        
        if (mounted) {
          setState(() {
            _targetPage = const LoginPage(
            contextMessage: 'Por favor, edite seu perfil para continuar.',
            );
          });
        }
        return;
      }

      final tipo = doc['role']?.toString();
      debugPrint('AuthRedirect: Perfil encontrado. role="$tipo", shop_id="${doc['shop_id']}"');

      // O campo 'role' é obrigatório para saber para onde redirecionar
      if (tipo == null || tipo.isEmpty) {
        debugPrint(
            'AuthRedirect: ERRO - Campo "role" ausente para userId=${widget.user.id}. '
            'Doc completo: $doc');
        _setError('Tipo de usuário não definido. Entre em contato com o suporte.');
        return;
      }

      // Salva na sessão local
      await SessionService.saveLogin(
        userId: widget.user.id,
        userType: tipo,
        // Usar shop_id do banco (snake_case)
        shopId: (tipo == 'dono' || tipo == 'business' || tipo == 'admin')
            ? (doc['shop_id']?.toString() ?? widget.user.id)
            : null,
      );

      if (!mounted) return;

      debugPrint('AuthRedirect: Redirecionando userId=${widget.user.id} com tipo="$tipo"');

      // Define visualmente para onde ir
      if (tipo == 'dono' || tipo == 'business') {
        setState(() => _targetPage = const BusinessHomePage());
      } else if (tipo == 'admin') {
        setState(() => _targetPage = const BusinessHomePage());
      } else {
        setState(() => _targetPage = const ClientHomePage());
      }
    } catch (e, stack) {
      debugPrint('AuthRedirect ERRO TIPO: ${e.runtimeType}');
      debugPrint('AuthRedirect ERRO: $e');
      debugPrint('AuthRedirect STACK: $stack');
      if (mounted) {
        _setError('Erro: $e');
      }
    }
  }

  void _setError(String message) {
    setState(() {
      _error = true;
      _errorMessage = message;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_targetPage != null) return _targetPage!;

    if (_error) {
      // ✅ FIX: Mostra LoginPage mas exibe snackbar informativo ao invés de tela cinza
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _errorMessage.isNotEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(_errorMessage),
              backgroundColor: Colors.red.shade700,
              duration: const Duration(seconds: 5),
            ),
          );
        }
      });
      return const LoginPage();
    }

    // ✅ FIX: Fundo branco (não cinza) durante o carregamento
    return const Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: CircularProgressIndicator(color: AppColors.primaryPurple),
      ),
    );
  }
}


// Admin Auth Gate - ensures user is logged in before reaching AdminDashboardPage
class AdminAuthGate extends StatelessWidget {
  const AdminAuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<sb.AuthState>(
      stream: AuthService().authStateChanges,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(color: AppColors.primaryPurple),
            ),
          );
        }

        final session = snapshot.data?.session;
        if (session != null) {
          return const AdminDashboardPage();
        }

        return const LoginPage(redirectPath: '/admin');
      },
    );
  }
}

/// Página de sucesso após pagamento Stripe Checkout (redirect de volta ao app)
class _PaymentSuccessPage extends StatefulWidget {
  const _PaymentSuccessPage();

  @override
  State<_PaymentSuccessPage> createState() => _PaymentSuccessPageState();
}

class _PaymentSuccessPageState extends State<_PaymentSuccessPage> {
  bool _redirecting = false;

  @override
  void initState() {
    super.initState();
    // Redireciona automaticamente para a home após 3 segundos
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted && !_redirecting) {
        _redirecting = true;
        Navigator.of(context).pushNamedAndRemoveUntil('/', (_) => false);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: AppColors.primaryPurple.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check_circle,
                    color: AppColors.primaryPurple, size: 48),
              ),
              const SizedBox(height: 24),
              const Text(
                'Pagamento Confirmado!',
                style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF111827)),
              ),
              const SizedBox(height: 12),
              const Text(
                'Sua assinatura foi ativada com sucesso.\nRedirecionando...',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, color: Color(0xFF6B7280)),
              ),
              const SizedBox(height: 32),
              const CircularProgressIndicator(color: AppColors.primaryPurple),
              const SizedBox(height: 24),
              TextButton(
                onPressed: () {
                  if (!_redirecting) {
                    _redirecting = true;
                    Navigator.of(context)
                        .pushNamedAndRemoveUntil('/', (_) => false);
                  }
                },
                child: const Text('Ir para o início',
                    style: TextStyle(color: AppColors.primaryPurple)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
