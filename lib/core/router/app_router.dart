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
import '../../core/services/session_service.dart';
import '../../core/services/auth_service.dart';
import '../widgets/splash_loading_widget.dart';

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

    // ── Rota de Reset de Senha (Supabase OTP) ──────────────────────────
    // O Supabase redireciona para /reset-password com ?code=... ou #access_token=...
    // O SDK Flutter/Web troca automaticamente o token e emite PASSWORD_RECOVERY.
    // Aqui apenas renderizamos o AuthGate que detecta o evento.
    if (cleanPath == 'reset-password') {
      return MaterialPageRoute(
        builder: (_) => const _PasswordRecoveryGate(),
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
      'payment-success',
      'reset-password', // Rota de redefinição de senha via Supabase OTP
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
    } else {
      // Mobile: fallback para evitar congelamento eterno em debug (F5) quando
      // o stream de auth do Supabase demora ou não emite o evento inicial.
      _fallbackTimer = Timer(const Duration(seconds: 8), () {
        if (mounted && !_timeoutReached) {
          setState(() => _timeoutReached = true);
          debugPrint('AuthGate: Mobile timeout atingido — forçando navegação.');
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
          if (_timeoutReached) {
            // Stream nunca emitiu (comum em debug/F5): usa sessão atual diretamente
            final session = supabase.auth.currentSession;
            if (session != null) {
              return AuthRedirect(user: session.user);
            }
            return const LoginPage();
          }
          return const SplashLoadingWidget();
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
            return const SplashLoadingWidget();
          }
        }
        
        // Se conseguirmos uma sessão válida (com ou sem código), limpamos o timer
        if (session != null) {
          _fallbackTimer?.cancel();
        }

        // Detecta evento de recuperação de senha → redireciona para tela de redefinição
        if (event == sb.AuthChangeEvent.passwordRecovery) {
          debugPrint('AuthGate: evento PASSWORD_RECOVERY detectado → ResetPasswordPage');
          // Limpa a URL do navegador
          if (kIsWeb) html.window.history.replaceState(null, '', '/reset-password');
          return const ResetPasswordPage(oobCode: '');
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
  bool _isNetworkError = false;
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
        _setError('Timeout: operação demorou mais de 10s. Verifique o console.', isNetwork: false);
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
        debugPrint('AuthRedirect: Perfil não encontrado para ${widget.user.email} — ativando fluxo de cadastro via LoginPage.');

        if (mounted) {
          // BUG 1 FIX: Retorna LoginPage sem parâmetros extras.
          // O initState do LoginPage detecta o usuário já autenticado (Google OAuth)
          // e chama _routeUser(user), que ao encontrar doc==null ativa _isRegistering=true,
          // mostrando o formulário de cadastro automaticamente.
          setState(() {
            _targetPage = const LoginPage();
          });
        }
        return;
      }

      final tipo = doc['role']?.toString();
      final phone = doc['phone']?.toString();
      debugPrint('AuthRedirect: Perfil encontrado. role="$tipo", phone="${phone != null ? "***" : "null"}", shop_id="${doc['shop_id']}"');

      // Verifica se o perfil está COMPLETO (role e phone preenchidos).
      // Usuários que entraram via Google OAuth têm linha criada pelo trigger
      // mas com phone=null e role='cliente' (padrão). Eles precisam completar o cadastro.
      final bool profileIncomplete = tipo == null || tipo.trim().isEmpty ||
                                     phone == null || phone.trim().isEmpty;

      if (profileIncomplete) {
        debugPrint('AuthRedirect: Perfil incompleto para ${widget.user.email} (phone ou role vazio) — ativando fluxo de cadastro.');
        if (mounted) {
          // LoginPage.initState() detecta o usuário autenticado e chama _routeUser(),
          // que verifica phone/role e ativa _isRegistering=true automaticamente.
          setState(() => _targetPage = const LoginPage());
        }
        return;
      }

      // Salva na sessão local (background)
      SessionService.saveLogin(
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
        final errStr = e.toString();
        final isNetwork = errStr.contains('SocketException') ||
            errStr.contains('Failed host lookup') ||
            errStr.contains('NetworkException') ||
            errStr.contains('Connection refused') ||
            errStr.contains('ClientException');
        _setError(
          isNetwork
              ? 'Sem conexão com a internet. Verifique sua rede e tente novamente.'
              : 'Erro ao carregar perfil: $e',
          isNetwork: isNetwork,
        );
      }
    }
  }

  void _setError(String message, {required bool isNetwork}) {
    setState(() {
      _error = true;
      _isNetworkError = isNetwork;
      _errorMessage = message;
    });
  }

  void _retry() {
    setState(() {
      _error = false;
      _isNetworkError = false;
      _errorMessage = '';
    });
    _resolve();
  }

  @override
  Widget build(BuildContext context) {
    if (_targetPage != null) return _targetPage!;

    if (_error) {
      if (_isNetworkError) {
        return Scaffold(
          backgroundColor: Colors.white,
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.wifi_off_rounded, size: 72, color: Colors.grey),
                  const SizedBox(height: 24),
                  const Text(
                    'Sem conexão',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF111827)),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _errorMessage,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 15, color: Colors.black54),
                  ),
                  const SizedBox(height: 32),
                  ElevatedButton.icon(
                    onPressed: _retry,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Tentar novamente'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryPurple,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }

      // Erros não-rede: mostra LoginPage com snackbar
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

    return const SplashLoadingWidget();
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

// ── Gate que aguarda o evento PASSWORD_RECOVERY do Supabase ──────────────────
// Renderizado quando o usuário acessa /reset-password vindo do e-mail.
// USA StatefulWidget para assinar o stream em initState (evita perder eventos
// emitidos logo após Supabase.initialize()) E chama getSessionFromUrl()
// explicitamente para o implicit flow com hash fragment #access_token=...
class _PasswordRecoveryGate extends StatefulWidget {
  const _PasswordRecoveryGate();

  @override
  State<_PasswordRecoveryGate> createState() => _PasswordRecoveryGateState();
}

class _PasswordRecoveryGateState extends State<_PasswordRecoveryGate> {
  bool _isRecovery = false;
  bool _ready = false;
  StreamSubscription<sb.AuthState>? _sub;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final supabase = sb.Supabase.instance.client;

    // 1. Assina o stream ANTES de qualquer await para não perder eventos futuros
    _sub = supabase.auth.onAuthStateChange.listen((state) {
      debugPrint('[PasswordRecoveryGate] evento: ${state.event}');
      if (state.event == sb.AuthChangeEvent.passwordRecovery ||
          state.event == sb.AuthChangeEvent.signedIn) {
        // Verifica se o tipo da sessão é recovery
        final isRecoverySession = state.event == sb.AuthChangeEvent.passwordRecovery;
        if (mounted && isRecoverySession) {
          setState(() {
            _isRecovery = true;
            _ready = true;
          });
        }
      }
    });

    // 2. Tenta processar o hash da URL explicitamente (implicit flow)
    // O hash terá o formato: #access_token=...&type=recovery
    if (kIsWeb) {
      try {
        final fragment = Uri.base.fragment;
        debugPrint('[PasswordRecoveryGate] Fragment da URL: $fragment');

        if (fragment.contains('type=recovery') || fragment.contains('access_token=')) {
          // Força o SDK a processar o hash e criar a sessão
          final response = await supabase.auth.getSessionFromUrl(Uri.base);
          debugPrint('[PasswordRecoveryGate] getSessionFromUrl OK, session: ${response.session.user.email}');

          if (mounted) {
            setState(() {
              _isRecovery = true;
              _ready = true;
            });
            // Limpa o hash da URL para não poluir
            html.window.history.replaceState(null, '', '/reset-password');
            return;
          }
        }
      } catch (e) {
        debugPrint('[PasswordRecoveryGate] getSessionFromUrl erro: $e');
      }
    }

    // 3. Se não encontrou o token no hash, marca como pronto (vai para login)
    if (mounted && !_isRecovery) {
      // Aguarda um breve momento para o stream emitir o evento PASSWORD_RECOVERY
      await Future.delayed(const Duration(milliseconds: 800));
      if (mounted && !_isRecovery) {
        setState(() => _ready = true);
      }
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Recovery confirmado → tela de nova senha
    if (_isRecovery) {
      return const ResetPasswordPage(oobCode: '');
    }

    // Ainda carregando
    if (!_ready) return const SplashLoadingWidget();

    // Nenhum token de recovery encontrado → login
    return const LoginPage();
  }
}
