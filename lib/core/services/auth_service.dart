import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;
import 'shop_data_cache_service.dart';
import 'session_service.dart';

/// Serviço de Autenticação MarkaAI (Refatorado para Supabase)
/// 
/// Este serviço substitui o FirebaseAuth e gerencia a sessão, metadados
/// e controle de acesso baseado em planos (Feature Gating).
class AuthService {
  // Cliente do Supabase acessado via getter para evitar erro de inicialização estática
  sb.SupabaseClient get _supabase => sb.Supabase.instance.client;

  /// Stream do estado de autenticação (Equivalente ao Firebase authStateChanges)
  /// Permite que o AppRouter (AuthGate) reaja a mudanças de login/logout.
  Stream<sb.AuthState> get authStateChanges => _supabase.auth.onAuthStateChange;

  /// Retorna o usuário autenticado no momento.
  sb.User? get currentUser => _supabase.auth.currentUser;

  /// Retorna o ID único do usuário no Supabase.
  String? get userId => currentUser?.id;

  // --- GETTERS DE METADADOS (Substituem Custom Claims do Firebase) ---

  /// ID do estabelecimento (shopId) vinculado ao usuário.
  /// No MarkaAI, para donos, o establishment_id geralmente é o próprio UID.
  String? getEstablishmentId() {
    return _getMetadata('shop_id');
  }

  /// Plano do usuário (free, starter, plus, pro).
  String getPlano() {
    return _getMetadata('plan') ?? 'free';
  }

  /// Função do usuário no sistema (admin, dono, funcionario, cliente).
  String getRole() {
    return _getMetadata('role') ?? 'cliente';
  }

  // --- MÉTODOS DE AUTENTICAÇÃO ---

  /// Inicia o fluxo de login OAuth com Google (Recomendado para Web)
  Future<void> signInWithGoogleOAuth() async {
    try {
      // Define a URL de redirecionamento baseada na plataforma
      // No Web, usamos a origem atual (ex: markaai.com.br ou localhost)
      // No Mobile, usamos o deep link configurado no app
      final String redirectUrl = kIsWeb
          ? (kDebugMode
              ? 'http://localhost:3000'
              : '${Uri.base.origin}/login')
          : 'markaai://login-callback';
      
      if (defaultTargetPlatform == TargetPlatform.windows) {
        debugPrint('[AuthService] Windows detectado. Aguardando retorno em: $redirectUrl');
      }
      
      await _supabase.auth.signInWithOAuth(
        sb.OAuthProvider.google,
        redirectTo: redirectUrl,
        authScreenLaunchMode: sb.LaunchMode.externalApplication,
      );
    } catch (e) {
      debugPrint('[AuthService] Erro no OAuth Google: $e');
      rethrow;
    }
  }

  /// Realiza login com e-mail e senha.
  /// 
  /// Lança [AuthException] em caso de erro, permitindo tratamento na UI.
  Future<sb.AuthResponse> signIn({
    required String email,
    required String password,
  }) async {
    try {
      final response = await _supabase.auth.signInWithPassword(
        email: email.trim(),
        password: password,
      );
      
      // Verifica se o email foi confirmado
      if (response.user != null && response.user!.emailConfirmedAt == null) {
        // Faz logout para manter a sessão limpa
        await _supabase.auth.signOut();
        throw sb.AuthException('Email not confirmed');
      }
      
      return response;
    } on sb.AuthException catch (e) {
      throw sb.AuthException(mapSupabaseError(e));
    } catch (e) {
      debugPrint('[AuthService] Erro inesperado no login: $e');
      throw Exception('Erro de conexão ao tentar entrar.');
    }
  }

  /// Realiza login com Google.
  Future<sb.AuthResponse> signInWithGoogle({
    required String idToken,
    required String accessToken,
  }) async {
    try {
      final response = await _supabase.auth.signInWithIdToken(
        provider: sb.OAuthProvider.google,
        idToken: idToken,
        accessToken: accessToken,
      );
      return response;
    } on sb.AuthException catch (e) {
      _handleAuthError(e);
      rethrow;
    } catch (e) {
      debugPrint('[AuthService] Erro inesperado no login Google: $e');
      throw Exception('Erro ao conectar com Google via Supabase.');
    }
  }

  /// Cria um novo usuário com metadados iniciais.
  /// 
  /// Os metadados em [data] são sincronizados com a tabela `profiles` via Trigger SQL.
  Future<sb.AuthResponse> signUp({
    required String email,
    required String password,
    required String name,
    required String role,
    String? phone,
    String? zipCode,
    String? street,
    String? neighborhood,
    String? city,
    String? state,    // Adicionado
    String? address,  // Adicionado
    String? number,
    String? birthDate,
    String? establishmentId,
    String? businessName, // Adicionado
  }) async {
    try {
      final response = await _supabase.auth.signUp(
        email: email.trim(),
        password: password,
        emailRedirectTo: kIsWeb
            ? (kDebugMode
                ? 'http://localhost:3000/confirm-email'
                : '${Uri.base.origin}/confirm-email')
            : 'markaai://confirm-email',
        data: {
          'name': name,
          'role': role,
          'shop_id': establishmentId,
          if (businessName != null) 'business_name': businessName, // Adicionado
          'plan': 'free', // Inicia no plano gratuito por padrão
          'verified': true,
          if (phone != null) 'phone': phone,
          if (zipCode != null) 'zip_code': zipCode,
          if (street != null) 'street': street,
          if (neighborhood != null) 'neighborhood': neighborhood,
          if (city != null) 'city': city,
          if (state != null) 'state': state,       // Adicionado
          if (address != null) 'address': address, // Adicionado
          if (number != null) 'number': number,
          if (birthDate != null) 'birth_date': birthDate,
        },
      );
      return response;
    } on sb.AuthException catch (e) {
      throw sb.AuthException(mapSupabaseError(e));
    } catch (e) {
      debugPrint('[AuthService] Erro inesperado no cadastro: $e');
      throw Exception('Erro ao criar conta.');
    }
  }

  /// Finaliza a sessão atual.
  Future<void> signOut() async {
    try {
      // 1. Limpa cache de memória e SharedPreferences do ShopDataCache
      ShopDataCacheService().invalidateAll(null);
      
      // 2. Limpa SharedPreferences da SessionService
      await SessionService.logout();

      // 3. Sign out do Supabase
      await _supabase.auth.signOut();
    } catch (e) {
      debugPrint('[AuthService] Erro ao sair: $e');
    }
  }

  /// Envia e-mail de recuperação de senha via Supabase Auth.
  Future<void> sendPasswordReset(String email) async {
    try {
      final String redirectUrl = kIsWeb
          ? (kDebugMode
              ? 'http://localhost:3000/reset-password'
              : '${Uri.base.origin}/reset-password')
          : 'markaai://reset-password';
          
      await _supabase.auth.resetPasswordForEmail(
        email.trim(),
        redirectTo: redirectUrl,
      );
    } on sb.AuthException catch (e) {
      throw sb.AuthException(mapSupabaseError(e));
    } catch (e) {
      debugPrint('[AuthService] Erro fatal em sendPasswordReset: $e');
      throw Exception('Falha ao processar solicitação. Tente novamente.');
    }
  }

  // --- FEATURE GATING (Lógica de Planos) ---

  /// Verifica se o usuário atual tem acesso a uma funcionalidade específica.
  /// 
  /// Substitui a leitura de Custom Claims no Flutter.
  bool hasFeature(String featureKey) {
    if (currentUser == null) return false;
    
    final currentPlano = getPlano();

    // Matriz de Acesso por Plano (Exemplo de Gating)
    final Map<String, List<String>> featuresByPlan = {
      'free': ['appointments_basic'],
      'starter': ['appointments_basic', 'financial_lite'],
      'plus': ['appointments_advanced', 'financial_full', 'inventory'],
      'pro': ['appointments_advanced', 'financial_full', 'inventory', 'marketing', 'multi_employee'],
      'admin': ['*'], // Acesso total
    };

    if (currentPlano == 'admin') return true;

    final allowedFeatures = featuresByPlan[currentPlano] ?? [];
    return allowedFeatures.contains(featureKey);
  }

  // --- MÉTODOS INTERNOS ---

  /// Lê metadados do campo `user_metadata` do Supabase.
  String? _getMetadata(String key) {
    if (currentUser == null) return null;
    final metadata = currentUser!.userMetadata;
    return metadata?[key]?.toString();
  }

  /// Mapeamento de erros do Supabase para constantes amigáveis.
  String mapSupabaseError(sb.AuthException e) {
    // 1. Verifica pelo status code de Rate Limit
    if (e.statusCode == '429' || e.message.toLowerCase().contains('rate limit')) {
      return 'RATE_LIMIT';
    }

    final msg = e.message.toLowerCase();
    
    // 2. Verifica por mensagens específicas
    if (msg.contains('email not confirmed')) {
      return 'EMAIL_NOT_CONFIRMED';
    }
    if (msg.contains('invalid login credentials')) {
      return 'INVALID_CREDENTIALS';
    }
    if (msg.contains('user not found')) {
      return 'USER_NOT_FOUND';
    }
    if (msg.contains('user already registered') || msg.contains('user already exists')) {
      return 'EMAIL_ALREADY_EXISTS';
    }
    if (msg.contains('password should be at least')) {
      return 'WEAK_PASSWORD';
    }
    if (msg.contains('network') || msg.contains('connection')) {
      return 'NETWORK_ERROR';
    }
    
    return 'GENERIC_ERROR';
  }

  /// Tratamento padronizado de erros de autenticação do Supabase.
  void _handleAuthError(sb.AuthException e) {
    debugPrint('[AuthService] Erro Auth: Code=${e.statusCode}, Msg=${e.message}');
    throw Exception(mapSupabaseError(e));
  }
}
