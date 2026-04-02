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
              : Uri.base.origin)
          : 'markaai://login-callback';
      
      debugPrint('[AuthService] Iniciando OAuth Google. RedirectTo: $redirectUrl');

      await _supabase.auth.signInWithOAuth(
        sb.OAuthProvider.google,
        redirectTo: redirectUrl,
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
      return response;
    } on sb.AuthException catch (e) {
      _handleAuthError(e);
      rethrow;
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
      _handleAuthError(e);
      rethrow;
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

  /// Envia e-mail de recuperação de senha via Edge Function (Resend).
  /// Usa o mesmo provedor Resend das notificações de agendamento.
  Future<void> sendPasswordReset(String email) async {
    try {
      final response = await _supabase.functions.invoke(
        'sendPasswordReset',
        body: {'email': email.trim()},
      );

      if (response.status != 200) {
        final msg = (response.data is Map) ? response.data['error'] : null;
        throw Exception(msg ?? 'Erro ao enviar e-mail.');
      }
    } on sb.FunctionException catch (e) {
      // Trata erro técnico da Edge Function e tenta pegar a mensagem amigável
      final details = e.details;
      String? msg;
      if (details is Map && details.containsKey('error')) {
        msg = details['error'];
      }
      throw Exception(msg ?? 'Não foi possível completar a solicitação.');
    } catch (e) {
      debugPrint('[AuthService] Erro fatal em sendPasswordReset: $e');
      if (e.toString().contains('Exception: ')) {
        rethrow;
      }
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

  /// Tratamento padronizado de erros de autenticação do Supabase.
  void _handleAuthError(sb.AuthException e) {
    debugPrint('[AuthService] Erro Auth: Code=${e.statusCode}, Msg=${e.message}');
    
    // Tratamento de casos específicos conforme pedido na FASE 4 (MarkaAI)
    if (e.message.toLowerCase().contains('email already registered') || 
        e.message.toLowerCase().contains('user already exists')) {
      throw Exception('Este e-mail já está em uso.');
    }
    
    if (e.message.toLowerCase().contains('invalid login credentials') ||
        e.message.toLowerCase().contains('user not found')) {
      throw Exception('E-mail ou senha inválidos.');
    }

    if (e.message.toLowerCase().contains('session expired') || 
        e.message.toLowerCase().contains('refresh_token_not_found')) {
      throw Exception('Sessão expirada. Por favor, faça login novamente.');
    }

    throw Exception(e.message);
  }
}
