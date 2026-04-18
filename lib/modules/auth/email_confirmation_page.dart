import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;
import '../../core/theme/app_colors.dart';
import '../../core/utils/html_stub.dart'
    if (dart.library.html) 'dart:html' as html;
import '../../core/services/session_service.dart';
import '../../modules/login/login_page.dart';

/// Página exibida quando o usuário clica no link de confirmação de e-mail
class EmailConfirmationPage extends StatefulWidget {
  const EmailConfirmationPage({super.key});

  @override
  State<EmailConfirmationPage> createState() => _EmailConfirmationPageState();
}

class _EmailConfirmationPageState extends State<EmailConfirmationPage> {
  bool _isLoading = true;
  bool _isConfirmed = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _checkEmailConfirmation();
  }

  Future<void> _checkEmailConfirmation() async {
    try {
      final supabase = sb.Supabase.instance.client;

      // Para implicit flow: tenta processar o fragment da URL explicitamente
      if (kIsWeb) {
        try {
          final fragment = Uri.base.fragment;
          if (fragment.contains('access_token')) {
            await supabase.auth.getSessionFromUrl(Uri.base);
          }
        } catch (_) {}
      }

      // Aguarda o SDK processar o token (aumentado para maior resiliência)
      await Future.delayed(const Duration(seconds: 2));

      // Verifica se há uma sessão ativa (email confirmado)
      final session = supabase.auth.currentSession;

      if (session != null && session.user.emailConfirmedAt != null) {
        // Migra dados pós-confirmação (ex: cria loja para donos)
        await _ensurePostSignupDataMigrated(session.user);

        if (mounted) {
          setState(() {
            _isLoading = false;
            _isConfirmed = true;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _isConfirmed = false;
            _errorMessage =
                'Não foi possível confirmar seu e-mail. O link pode ter expirado.';
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isConfirmed = false;
          _errorMessage =
              'Ocorreu um erro ao confirmar seu e-mail. Tente novamente.';
        });
      }
      debugPrint('[EmailConfirmation] Erro: $e');
    }
  }

  /// Garante que os dados pós-cadastro estejam no banco após confirmação de e-mail.
  /// Faz upsert de TODOS os campos do perfil a partir dos metadados do signUp(),
  /// garantindo que o perfil esteja completo independente do estado do trigger.
  Future<void> _ensurePostSignupDataMigrated(sb.User user) async {
    try {
      final metadata = user.userMetadata ?? {};
      final role = metadata['role']?.toString() ?? 'cliente';
      final supabase = sb.Supabase.instance.client;
      final uid = user.id;

      // Upsert completo do perfil para TODOS os tipos de usuário
      final profileData = <String, dynamic>{
        'id': uid,
        'email': user.email ?? '',
        'name': metadata['name']?.toString() ?? '',
        'role': role,
        'plan': metadata['plan']?.toString() ?? 'free',
        'verified': true,
      };

      final phone = metadata['phone']?.toString() ?? '';
      if (phone.isNotEmpty) profileData['phone'] = phone;

      final zipCode = metadata['zip_code']?.toString() ?? '';
      if (zipCode.isNotEmpty) profileData['zip_code'] = zipCode;

      final street = metadata['street']?.toString() ?? '';
      if (street.isNotEmpty) profileData['street'] = street;

      final neighborhood = metadata['neighborhood']?.toString() ?? '';
      if (neighborhood.isNotEmpty) profileData['neighborhood'] = neighborhood;

      final city = metadata['city']?.toString() ?? '';
      if (city.isNotEmpty) profileData['city'] = city;

      final state = metadata['state']?.toString() ?? '';
      if (state.isNotEmpty) profileData['state'] = state;

      final number = metadata['number']?.toString() ?? '';
      if (number.isNotEmpty) profileData['number'] = number;

      final birthDate = metadata['birth_date']?.toString() ?? '';
      if (birthDate.isNotEmpty) profileData['birth_date'] = birthDate;

      await supabase.from('users').upsert(profileData);
      debugPrint('[EmailConfirmation] Perfil upsertado para uid=$uid, role=$role');

      // Para donos: garante que a loja exista
      if (role == 'dono' || role == 'business') {
        final existing = await supabase
            .from('shops')
            .select('id')
            .eq('id', uid)
            .maybeSingle();

        if (existing == null) {
          final address = street.isNotEmpty
              ? '$street, $number'.trim().replaceAll(RegExp(r',\s*$'), '')
              : '';

          await supabase.from('shops').upsert({
            'id': uid,
            'name': (metadata['business_name']?.toString().isNotEmpty == true
                    ? metadata['business_name']
                    : metadata['name'])?.toString() ?? '',
            'phone': phone,
            'city': city,
            'state': state,
            'zip_code': zipCode,
            'address': address,
            'neighborhood': neighborhood,
            'owner_id': uid,
            'verified': false,
            'plan_id': 'free',
          });
          await supabase.from('users').update({'shop_id': uid}).eq('id', uid);
          debugPrint('[EmailConfirmation] Loja criada para dono=$uid via metadados.');
        }
      }
    } catch (e) {
      debugPrint('[EmailConfirmation] Aviso: falha ao migrar dados pós-confirmação: $e');
    }
  }

  /// Navega para a home reutilizando o fluxo padrão do AuthGate/AuthRedirect.
  Future<void> _enterApp() async {
    try {
      final supabase = sb.Supabase.instance.client;
      final session = supabase.auth.currentSession;

      if (session == null) {
        if (mounted) {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const LoginPage()),
            (_) => false,
          );
        }
        return;
      }

      // Salva sessão local
      final doc = await supabase
          .from('users')
          .select('role, shop_id')
          .eq('id', session.user.id)
          .maybeSingle();

      final tipo = doc?['role']?.toString() ?? 'cliente';
      await SessionService.saveLogin(
        userId: session.user.id,
        userType: tipo,
        shopId: (tipo == 'dono' || tipo == 'business')
            ? (doc?['shop_id']?.toString() ?? session.user.id)
            : null,
      );

      if (!mounted) return;

      // Limpa URL no Web antes de navegar para evitar re-trigger do AuthGate
      if (kIsWeb) html.window.history.replaceState(null, '', '/');

      Navigator.of(context).pushNamedAndRemoveUntil('/', (_) => false);
    } catch (e) {
      debugPrint('[EmailConfirmation] Erro ao entrar no app: $e');
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginPage()),
          (_) => false,
        );
      }
    }
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
              if (_isLoading) ...[
                const CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation(AppColors.primaryPurple),
                ),
                const SizedBox(height: 24),
                const Text(
                  'Confirmando seu e-mail...',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w500,
                    color: Colors.grey,
                  ),
                ),
              ] else if (_isConfirmed) ...[
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: AppColors.primaryPurple.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.check_circle_outline,
                    size: 80,
                    color: AppColors.primaryPurple,
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'E-mail confirmado com sucesso!',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primaryPurple,
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Sua conta está ativa. Clique no botão abaixo para começar a usar o MarkaAI.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.grey,
                  ),
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _enterApp,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryPurple,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      elevation: 2,
                    ),
                    child: const Text(
                      'Entrar no MarkaAI',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ),
              ] else ...[
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.amber.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.history_rounded,
                    size: 80,
                    color: Colors.amber[700],
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'O link expirou',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  _errorMessage ?? 'Este link expirou ou já foi usado. Por favor, solicite um novo link de confirmação.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 16,
                    color: Colors.grey,
                  ),
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.of(context).pushAndRemoveUntil(
                        MaterialPageRoute(builder: (context) => const LoginPage()),
                        (_) => false,
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryPurple,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      elevation: 2,
                    ),
                    child: const Text('Solicitar novo link'),
                  ),
                ),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pushAndRemoveUntil(
                      MaterialPageRoute(builder: (context) => const LoginPage()),
                      (_) => false,
                    );
                  },
                  child: const Text(
                    'Voltar para o login',
                    style: TextStyle(color: Colors.grey, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
