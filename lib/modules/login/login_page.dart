import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:mask_text_input_formatter/mask_text_input_formatter.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;

import '../../core/theme/app_colors.dart';
import '../business/business_home_page.dart';
import '../clients/client_home_page.dart';

// --- SERVIÇO AUXILIAR (MANTIDO) ---
class ViaCepService {
  static Future<Map<String, dynamic>?> buscarCep(String cep) async {
    String cepLimpo = cep.replaceAll(RegExp(r'[^0-9]'), '');
    if (cepLimpo.length != 8) return null;
    try {
      final url = Uri.parse('https://viacep.com.br/ws/$cepLimpo/json/');
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final dados = jsonDecode(response.body);
        return dados.containsKey('erro') ? null : dados;
      }
    } catch (e) {
      return null;
    }
    return null;
  }
}

class LoginPage extends StatefulWidget {
  final bool returnOnSuccess;
  final String? contextMessage;
  const LoginPage(
      {super.key, this.returnOnSuccess = false, this.contextMessage});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage>
    with SingleTickerProviderStateMixin {
  // Estados
  bool _isLoading = false;
  bool _isRegistering = false;
  bool _obscurePassword = true;
  bool _obscurePasswordConfirm = true;
  bool _acceptedTerms = false;
  bool _acceptedPrivacy = false;
  String? _selectedRole;
  int _currentStep =
      0; // 0: Credenciais, 1: Perfil, 2: Dados Pessoais, 3: Endereço

  // Controllers
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _passConfirmCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _cepCtrl = TextEditingController();
  final _ruaCtrl = TextEditingController();
  final _bairroCtrl = TextEditingController();
  final _numCtrl = TextEditingController();
  final _birthCtrl = TextEditingController();
  final _bizCtrl = TextEditingController();
  final _cidadeCtrl = TextEditingController();

  // Máscaras
  final _phoneMask = MaskTextInputFormatter(
      mask: '(##) #####-####', filter: {"#": RegExp(r'[0-9]')});
  final _cepMask = MaskTextInputFormatter(
      mask: '#####-###', filter: {"#": RegExp(r'[0-9]')});
  final _dateMask = MaskTextInputFormatter(
      mask: '##/##/####', filter: {"#": RegExp(r'[0-9]')});

  @override
  void initState() {
    super.initState();
    // Verificação inicial de sessão
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        _routeUser(user);
      }
    });
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _passConfirmCtrl.dispose();
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _cepCtrl.dispose();
    _ruaCtrl.dispose();
    _bairroCtrl.dispose();
    _numCtrl.dispose();
    _birthCtrl.dispose();
    _bizCtrl.dispose();
    _cidadeCtrl.dispose();
    super.dispose();
  }

  // --- ðŸ›¡ï¸ MOTOR DE ROTEAMENTO (MANTIDO E BLINDADO) ---
  Future<void> _routeUser(User user) async {
    setState(() => _isLoading = true);
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      bool needsRegistration = false;
      Map<String, dynamic>? data;

      if (!doc.exists) {
        needsRegistration = true;
      } else {
        data = doc.data();
        // Verifica integridade
        if (data == null ||
            !data.containsKey('tipo') ||
            !data.containsKey('telefone')) {
          needsRegistration = true;
        }
      }

      if (needsRegistration) {
        if (mounted) {
          // Auto-preenchimento vindo do Provider (Google)
          _nameCtrl.text = user.displayName ?? _nameCtrl.text;
          _emailCtrl.text = user.email ?? _emailCtrl.text;

          setState(() {
            _isRegistering = true;
            _currentStep = 1; // Começa no passo de perfil
            _isLoading = false;
          });

          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Quase lá! Finalize seu cadastro para continuar."),
              backgroundColor: AppColors.primaryPurple,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }

      // Roteamento Sucesso
      String tipo = data?['tipo'] ?? 'cliente';

      if (mounted) {
        if (widget.returnOnSuccess) {
          Navigator.pop(context, true);
          return;
        }

        if (tipo == 'dono' || tipo == 'business') {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => const BusinessHomePage()),
          );
        } else {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => const ClientHomePage()),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        _showError("Erro de conexão: $e");
      }
    }
  }

  // --- LÃ“GICA DE CEP ---
  Future<void> _handleCepSearch(String value) async {
    if (value.length == 9) {
      setState(() => _isLoading = true);
      final dados = await ViaCepService.buscarCep(value);
      setState(() => _isLoading = false);

      if (dados != null && mounted) {
        setState(() {
          _ruaCtrl.text = dados['logradouro'] ?? '';
          _bairroCtrl.text = dados['bairro'] ?? '';
          _cidadeCtrl.text = "${dados['localidade']} - ${dados['uf']}";
        });
      }
    }
  }

  // --- VALIDAÇÃO DE SENHA ---
  bool _validatePassword() {
    if (_passCtrl.text.isEmpty) {
      _showError("Por favor, insira uma senha.");
      return false;
    }
    if (_passCtrl.text.length < 6) {
      _showError("A senha deve ter pelo menos 6 caracteres.");
      return false;
    }
    if (_passCtrl.text != _passConfirmCtrl.text) {
      _showError("As senhas não correspondem.");
      return false;
    }
    return true;
  }

  // --- NAVEGAÇÃO ENTRE ETAPAS ---
  void _nextStep() {
    if (_currentStep == 0) {
      // Validar credenciais
      if (_emailCtrl.text.isEmpty) {
        _showError("Por favor, insira um e-mail.");
        return;
      }
      if (!_emailCtrl.text.contains('@')) {
        _showError("Por favor, insira um e-mail válido.");
        return;
      }
      if (!_validatePassword()) return;

      setState(() => _currentStep = 1);
    } else if (_currentStep == 1) {
      // Validar perfil
      if (_selectedRole == null) {
        _showError("Por favor, selecione um perfil.");
        return;
      }
      setState(() => _currentStep = 2);
    } else if (_currentStep == 2) {
      // Validar dados pessoais
      if (_nameCtrl.text.isEmpty) {
        _showError("Por favor, insira seu nome.");
        return;
      }
      if (_phoneCtrl.text.isEmpty) {
        _showError("Por favor, insira seu telefone.");
        return;
      }
      if (_selectedRole == 'cliente' && _birthCtrl.text.isEmpty) {
        _showError("Por favor, insira sua data de nascimento.");
        return;
      }
      if (_selectedRole == 'dono' && _bizCtrl.text.isEmpty) {
        _showError("Por favor, insira o nome da sua barbearia/salão.");
        return;
      }
      setState(() => _currentStep = 3);
    }
  }

  void _previousStep() {
    if (_currentStep > 0) {
      setState(() => _currentStep--);
    }
  }

  // --- AUTENTICAÇÃO ---
  Future<void> _handleAuth() async {
    if (_currentStep < 3) {
      _nextStep();
      return;
    }

    // Validar última etapa (endereço)
    if (_cepCtrl.text.isEmpty ||
        _ruaCtrl.text.isEmpty ||
        _bairroCtrl.text.isEmpty ||
        _cidadeCtrl.text.isEmpty ||
        _numCtrl.text.isEmpty) {
      _showError("Por favor, preencha todos os dados de endereço.");
      return;
    }

    if (!_acceptedTerms || !_acceptedPrivacy) {
      _showError(
          "Você precisa aceitar os Termos e a Política de Privacidade para continuar.");
      return;
    }

    setState(() => _isLoading = true);

    try {
      User? user = FirebaseAuth.instance.currentUser;

      // Se não veio do Google, cria conta
      if (user == null) {
        UserCredential res = await FirebaseAuth.instance
            .createUserWithEmailAndPassword(
                email: _emailCtrl.text.trim(), password: _passCtrl.text.trim());
        user = res.user;
      }

      // Null check explícito para evitar crash
      if (user == null) {
        _showError("Falha ao criar a conta. Tente novamente.");
        setState(() => _isLoading = false);
        return;
      }

      // Salva dados no Firestore
      final uid = user.uid;
      Map<String, dynamic> data = {
        'uid': uid,
        'nome': _nameCtrl.text.trim(),
        'email': _emailCtrl.text.trim(),
        'telefone': _phoneCtrl.text.replaceAll(RegExp(r'\D'), ''),
        'tipo': _selectedRole,
        'verified': true,
        // Campos raiz para facilitar queries
        'bairro': _bairroCtrl.text,
        'cidade': _cidadeCtrl.text,
        'criado_em': FieldValue.serverTimestamp(),
        'endereco': {
          'cep': _cepCtrl.text,
          'rua': _ruaCtrl.text,
          'bairro': _bairroCtrl.text,
          'cidade': _cidadeCtrl.text,
          'numero': _numCtrl.text
        }
      };

      if (_selectedRole == 'cliente') {
        data['aniversario'] = _birthCtrl.text;
      } else {
        data['nome_negocio'] = _bizCtrl.text;
        data['shopId'] = uid;
      }

      await FirebaseFirestore.instance.collection('users').doc(uid).set(data);
      await _routeUser(user);
    } on FirebaseAuthException catch (e) {
      _handleFirebaseError(e);
    } catch (e, st) {
      print('[SIGNUP-ERR] ${e.runtimeType}: $e\n$st');
      _showError('[${e.runtimeType}] ${e.toString()}');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleGoogle() async {
    setState(() => _isLoading = true);
    try {
      final GoogleSignInAccount? gUser = await GoogleSignIn().signIn();
      if (gUser == null) {
        setState(() => _isLoading = false);
        return;
      }

      final GoogleSignInAuthentication gAuth = await gUser.authentication;
      final AuthCredential credential = GoogleAuthProvider.credential(
          accessToken: gAuth.accessToken, idToken: gAuth.idToken);

      final UserCredential uCred =
          await FirebaseAuth.instance.signInWithCredential(credential);
      // Check if user document exists and is complete; if not, force registration flow
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uCred.user!.uid)
          .get();
      bool needsRegistration = false;
      if (!doc.exists) {
        needsRegistration = true;
      } else {
        final data = doc.data();
        if (data == null ||
            !data.containsKey('tipo') ||
            !data.containsKey('telefone')) {
          needsRegistration = true;
        }
      }
      if (needsRegistration) {
        if (mounted) {
          // Reuse the built registration flow instead of showing a separate modal.
          _nameCtrl.text = uCred.user?.displayName ?? _nameCtrl.text;
          _emailCtrl.text = uCred.user?.email ?? _emailCtrl.text;
          setState(() {
            _isRegistering = true;
            _currentStep = 1; // start at role selection
            _isLoading = false;
          });
        }
        return;
      }
      await _routeUser(uCred.user!);
    } catch (e) {
      _showError("Não foi possível conectar com Google.");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _handleFirebaseError(FirebaseAuthException e) {
    String msg = "Erro na autenticação";
    if (e.code == 'user-not-found') {
      msg = "E-mail não cadastrado.";
    } else if (e.code == 'wrong-password') {
      msg = "Senha incorreta.";
    } else if (e.code == 'email-already-in-use') {
      msg = "Este e-mail já está em uso.";
    } else if (e.code == 'weak-password') {
      msg = "A senha deve ter pelo menos 6 caracteres.";
    }
    _showError(msg);
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: Colors.redAccent,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    bool isDesktop = size.width > 900;

    return Scaffold(
      backgroundColor: Colors.white,
      body: Row(
        children: [
          // ðŸ’» PAINEL ESQUERDO (Apenas Desktop)
          if (isDesktop)
            Expanded(
              flex: 5,
              child: Stack(
                children: [
                  Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [AppColors.primaryPurple, Color(0xFF4B0082)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                  ),
                  Positioned(
                    top: -100,
                    right: -100,
                    child: Container(
                      width: 400,
                      height: 400,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withValues(alpha: 0.05),
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: -50,
                    left: -50,
                    child: Container(
                      width: 300,
                      height: 300,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withValues(alpha: 0.05),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(60.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Image.asset('assets/images/logo_white.png',
                            height: 120, fit: BoxFit.contain),
                        const SizedBox(height: 18),
                        const SizedBox(height: 12),
                        const Text(
                          "Domine sua agenda â€” organize seu negócio e aumente seu faturamento.",
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 32,
                              fontWeight: FontWeight.w700,
                              height: 1.2),
                        ),
                        const SizedBox(height: 30),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 10),
                          decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.2))),
                          child: const Text(
                              "ðŸš€ Agendamento Inteligente â€¢ Gestão Financeira",
                              style:
                                  TextStyle(color: Colors.white, fontSize: 14)),
                        )
                      ],
                    ),
                  ),
                ],
              ),
            ),

          // ðŸ“± PAINEL DIREITO (Formulário)
          Expanded(
            flex: isDesktop ? 6 : 1,
            child: Container(
              color: Colors.white,
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(30),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 500),
                    child: _isRegistering
                        ? _buildRegistrationFlow()
                        : _buildLoginForm(),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- FORMULÃRIO DE LOGIN (SIMPLES E ELEGANTE) ---
  Widget _buildLoginForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Mostrar logo no painel branco apenas em telas móveis (quando não é desktop)
        Builder(builder: (context) {
          final size = MediaQuery.of(context).size;
          final isDesktop = size.width > 900;
          if (!isDesktop) {
            return Center(
              child: Column(
                children: [
                  Image.asset('assets/images/logo_purple.png',
                      height: 96, fit: BoxFit.contain),
                  const SizedBox(height: 12),
                ],
              ),
            );
          }
          return const SizedBox(height: 8);
        }),
        const SizedBox(height: 20),
        const Text("Bem-vindo(a)!",
            style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: Colors.black87)),
        const Text("Insira suas credenciais para continuar.",
            style: TextStyle(color: Colors.grey)),
        const SizedBox(height: 30),
        _ModernInput(
            controller: _emailCtrl,
            label: "E-mail",
            icon: Icons.email_outlined),
        const SizedBox(height: 16),
        _ModernInput(
          controller: _passCtrl,
          label: "Senha",
          icon: Icons.lock_outline,
          isPassword: true,
          obscure: _obscurePassword,
          onObscurePressed: () =>
              setState(() => _obscurePassword = !_obscurePassword),
        ),
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: _showResetPasswordDialog,
            child: const Text("Esqueceu a senha?",
                style: TextStyle(
                    color: AppColors.primaryPurple,
                    fontWeight: FontWeight.w600)),
          ),
        ),
        const SizedBox(height: 20),
        _PrimaryButton(
            text: "ENTRAR",
            isLoading: _isLoading,
            onPressed: _handleLoginClick),
        const SizedBox(height: 20),
        _DividerOr(),
        const SizedBox(height: 20),
        _GoogleButton(onPressed: _handleGoogle),
        const SizedBox(height: 30),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text("Não tem uma conta?",
                style: TextStyle(color: Colors.grey)),
            TextButton(
              onPressed: () => setState(() => _isRegistering = true),
              child: const Text("Cadastre-se",
                  style: TextStyle(
                      color: AppColors.primaryPurple,
                      fontWeight: FontWeight.bold)),
            ),
          ],
        )
      ],
    );
  }

  void _handleLoginClick() async {
    if (_emailCtrl.text.isEmpty || _passCtrl.text.isEmpty) {
      _showError("Por favor, preencha e-mail e senha.");
      return;
    }

    setState(() => _isLoading = true);

    try {
      UserCredential res = await FirebaseAuth.instance
          .signInWithEmailAndPassword(
              email: _emailCtrl.text.trim(), password: _passCtrl.text.trim());
      await _routeUser(res.user!);
    } on FirebaseAuthException catch (e) {
      // If user not found, switch to the existing registration flow (no extra modal)
      if (e.code == 'user-not-found') {
        setState(() {
          _isRegistering = true;
          _currentStep = 1; // show role selection step
          _emailCtrl.text = _emailCtrl.text.trim();
          _isLoading = false;
        });
      } else {
        _handleFirebaseError(e);
        setState(() => _isLoading = false);
      }
    } catch (e) {
      _showError("Erro ao fazer login.");
      setState(() => _isLoading = false);
    }
  }

  Future<void> _showResetPasswordDialog() async {
    final ctrl = TextEditingController(text: _emailCtrl.text.trim());
    final formKey = GlobalKey<FormState>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Recuperar senha'),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: ctrl,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
              labelText: 'E-mail',
              hintText: 'seu@email.com',
            ),
            validator: (v) {
              final value = (v ?? '').trim();
              if (value.isEmpty) return 'Informe seu e-mail';
              if (!value.contains('@')) return 'E-mail inválido';
              return null;
            },
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () {
              if (formKey.currentState?.validate() != true) return;
              Navigator.pop(ctx, true);
            },
            child: const Text('Enviar'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _isLoading = true);
    try {
      await FirebaseAuth.instance
          .sendPasswordResetEmail(email: ctrl.text.trim());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Enviamos um e-mail para redefinir sua senha.'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } on FirebaseAuthException catch (e) {
      _handleFirebaseError(e);
    } catch (e) {
      _showError('Erro ao enviar e-mail de recuperação.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // --- FLUXO DE REGISTRO EM ETAPAS ---
  Widget _buildRegistrationFlow() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Header
        Row(
          children: [
            if (_currentStep > 0)
              IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: _previousStep,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            if (_currentStep > 0) const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_getStepTitle(),
                      style: const TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87)),
                  const SizedBox(height: 5),
                  Text(_getStepSubtitle(),
                      style: const TextStyle(color: Colors.grey, fontSize: 13)),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 25),

        // Progresso (Dots)
        _buildProgressDots(),
        const SizedBox(height: 30),

        // Conteúdo da Etapa Atual
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          transitionBuilder: (child, animation) {
            return FadeTransition(opacity: animation, child: child);
          },
          child: _buildStepContent(),
        ),

        const SizedBox(height: 30),

        // Botões de Ação
        Row(
          children: [
            if (_currentStep > 0)
              Expanded(
                child: OutlinedButton(
                  onPressed: _previousStep,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    side:
                        const BorderSide(color: Color(0xFFEEEEEE), width: 1.5),
                  ),
                  child: const Text("VOLTAR",
                      style: TextStyle(
                          color: Colors.black87, fontWeight: FontWeight.bold)),
                ),
              ),
            if (_currentStep > 0) const SizedBox(width: 10),
            Expanded(
              child: _PrimaryButton(
                text: _currentStep == 3 ? "CRIAR CONTA" : "PRÃ“XIMO",
                isLoading: _isLoading,
                onPressed: _handleAuth,
              ),
            ),
          ],
        ),

        const SizedBox(height: 20),

        // Link para voltar ao login
        if (_currentStep == 0)
          Center(
            child: TextButton(
              onPressed: () => setState(() => _isRegistering = false),
              child: const Text("Já tem uma conta? Faça login",
                  style: TextStyle(
                      color: AppColors.primaryPurple,
                      fontWeight: FontWeight.w600)),
            ),
          ),
      ],
    );
  }

  // --- CONSTRUTOR DE CONTEÚDO POR ETAPA ---
  Widget _buildStepContent() {
    switch (_currentStep) {
      case 0:
        return _buildStep0Credentials();
      case 1:
        return _buildStep1RoleSelection();
      case 2:
        return _buildStep2PersonalData();
      case 3:
        return _buildStep3Address();
      default:
        return const SizedBox();
    }
  }

  String _getStepTitle() {
    switch (_currentStep) {
      case 0:
        return "Credenciais de Acesso";
      case 1:
        return "Qual seu perfil?";
      case 2:
        return "Dados Pessoais";
      case 3:
        return "Endereço";
      default:
        return "";
    }
  }

  String _getStepSubtitle() {
    switch (_currentStep) {
      case 0:
        return "Crie suas credenciais para acessar a plataforma";
      case 1:
        return "Selecione se você é cliente ou dono de negócio";
      case 2:
        return "Preencha seus dados pessoais";
      case 3:
        return "Finalize com seu endereço";
      default:
        return "";
    }
  }

  // --- ETAPA 0: CREDENCIAIS ---
  Widget _buildStep0Credentials() {
    return Column(
      key: const ValueKey(0),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ModernInput(
          controller: _emailCtrl,
          label: "E-mail",
          icon: Icons.email_outlined,
          keyboardType: TextInputType.emailAddress,
        ),
        const SizedBox(height: 16),
        _ModernInput(
          controller: _passCtrl,
          label: "Senha",
          icon: Icons.lock_outline,
          isPassword: true,
          obscure: _obscurePassword,
          onObscurePressed: () =>
              setState(() => _obscurePassword = !_obscurePassword),
        ),
        const SizedBox(height: 16),
        _ModernInput(
          controller: _passConfirmCtrl,
          label: "Confirmar Senha",
          icon: Icons.lock_outline,
          isPassword: true,
          obscure: _obscurePasswordConfirm,
          onObscurePressed: () => setState(
              () => _obscurePasswordConfirm = !_obscurePasswordConfirm),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.blue[50],
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.blue[200]!),
          ),
          child: Row(
            children: [
              Icon(Icons.info, color: Colors.blue[700], size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  "Senha deve ter no mínimo 6 caracteres",
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.blue[900],
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // --- ETAPA 1: SELEÇÃO DE PERFIL ---
  Widget _buildStep1RoleSelection() {
    return Column(
      key: const ValueKey(1),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: _RoleCard(
                title: "Cliente",
                subtitle: "Quero agendar",
                icon: Icons.person_outline,
                isSelected: _selectedRole == 'cliente',
                onTap: () => setState(() => _selectedRole = 'cliente'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _RoleCard(
                title: "Negócio",
                subtitle: "",
                icon: Icons.storefront,
                isSelected: _selectedRole == 'dono',
                onTap: () => setState(() => _selectedRole = 'dono'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // --- ETAPA 2: DADOS PESSOAIS ---
  Widget _buildStep2PersonalData() {
    return Column(
      key: const ValueKey(2),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ModernInput(
          controller: _nameCtrl,
          label: "Nome Completo",
          icon: Icons.person,
          keyboardType: TextInputType.name,
        ),
        const SizedBox(height: 16),
        _ModernInput(
          controller: _phoneCtrl,
          label: "WhatsApp",
          icon: Icons.phone,
          mask: _phoneMask,
          keyboardType: TextInputType.phone,
        ),
        const SizedBox(height: 16),
        if (_selectedRole == 'cliente')
          _ModernInput(
            controller: _birthCtrl,
            label: "Data de Nascimento",
            icon: Icons.cake,
            mask: _dateMask,
            keyboardType: TextInputType.number,
          )
        else
          _ModernInput(
            controller: _bizCtrl,
            label: "Nome da Barbearia/Salão",
            icon: Icons.content_cut,
          ),
      ],
    );
  }

  // --- ETAPA 3: ENDEREÇO ---
  Widget _buildStep3Address() {
    return Column(
      key: const ValueKey(3),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: _ModernInput(
                controller: _cepCtrl,
                label: "CEP",
                icon: Icons.map,
                mask: _cepMask,
                keyboardType: TextInputType.number,
                onChanged: _handleCepSearch,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _ModernInput(
                controller: _numCtrl,
                label: "Número",
                icon: Icons.tag,
                keyboardType: TextInputType.number,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _ModernInput(
          controller: _ruaCtrl,
          label: "Rua",
          icon: Icons.location_on_outlined,
          readOnly: true,
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _ModernInput(
                controller: _bairroCtrl,
                label: "Bairro",
                icon: Icons.holiday_village,
                readOnly: true,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _ModernInput(
                controller: _cidadeCtrl,
                label: "Cidade",
                icon: Icons.location_city,
                readOnly: true,
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        // --- Termos e Política de Privacidade ---
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.grey[50],
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey[200]!),
          ),
          child: Column(
            children: [
              InkWell(
                onTap: () => setState(() => _acceptedTerms = !_acceptedTerms),
                borderRadius: BorderRadius.circular(8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Checkbox(
                      value: _acceptedTerms,
                      onChanged: (v) =>
                          setState(() => _acceptedTerms = v ?? false),
                      activeColor: AppColors.primaryPurple,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: RichText(
                          text: const TextSpan(
                            style:
                                TextStyle(fontSize: 13, color: Colors.black87),
                            children: [
                              TextSpan(text: "Li e aceito os "),
                              TextSpan(
                                text: "Termos de Uso",
                                style: TextStyle(
                                  color: AppColors.primaryPurple,
                                  fontWeight: FontWeight.bold,
                                  decoration: TextDecoration.underline,
                                ),
                              ),
                              TextSpan(text: " da plataforma"),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              InkWell(
                onTap: () =>
                    setState(() => _acceptedPrivacy = !_acceptedPrivacy),
                borderRadius: BorderRadius.circular(8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Checkbox(
                      value: _acceptedPrivacy,
                      onChanged: (v) =>
                          setState(() => _acceptedPrivacy = v ?? false),
                      activeColor: AppColors.primaryPurple,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: RichText(
                          text: const TextSpan(
                            style:
                                TextStyle(fontSize: 13, color: Colors.black87),
                            children: [
                              TextSpan(text: "Li e aceito a "),
                              TextSpan(
                                text: "Política de Privacidade",
                                style: TextStyle(
                                  color: AppColors.primaryPurple,
                                  fontWeight: FontWeight.bold,
                                  decoration: TextDecoration.underline,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // --- INDICADOR DE PROGRESSO ---
  Widget _buildProgressDots() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(
        4,
        (index) => Container(
          margin: const EdgeInsets.symmetric(horizontal: 6),
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: index <= _currentStep
                ? AppColors.primaryPurple
                : Colors.grey[300],
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// ðŸ§± WIDGETS REUTILIZÃVEIS
// =============================================================================

class _ModernInput extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final IconData icon;
  final bool isPassword;
  final bool obscure;
  final VoidCallback? onObscurePressed;
  final MaskTextInputFormatter? mask;
  final TextInputType? keyboardType;
  final Function(String)? onChanged;
  final bool readOnly;

  const _ModernInput({
    required this.controller,
    required this.label,
    required this.icon,
    this.isPassword = false,
    this.obscure = false,
    this.onObscurePressed,
    this.mask,
    this.keyboardType,
    this.onChanged,
    this.readOnly = false,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      obscureText: obscure,
      keyboardType: keyboardType,
      inputFormatters: mask != null ? [mask!] : [],
      onChanged: onChanged,
      readOnly: readOnly,
      validator: (val) =>
          val == null || val.isEmpty ? 'Campo obrigatório' : null,
      style: TextStyle(color: readOnly ? Colors.grey : Colors.black87),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: Colors.grey[600], fontSize: 14),
        prefixIcon: Icon(icon,
            color: AppColors.primaryPurple.withValues(alpha: 0.7), size: 20),
        suffixIcon: isPassword
            ? IconButton(
                icon: Icon(
                    obscure
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                    color: Colors.grey),
                onPressed: onObscurePressed,
              )
            : null,
        filled: true,
        fillColor: readOnly ? Colors.grey[100] : const Color(0xFFFAFAFA),
        contentPadding:
            const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFEEEEEE))),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide:
                const BorderSide(color: AppColors.primaryPurple, width: 1.5)),
        errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Colors.redAccent)),
      ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  final String text;
  final bool isLoading;
  final VoidCallback onPressed;

  const _PrimaryButton({
    required this.text,
    required this.isLoading,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 50,
      child: ElevatedButton(
        onPressed: isLoading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primaryPurple,
          foregroundColor: Colors.white,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          elevation: 2,
          shadowColor: AppColors.primaryPurple.withValues(alpha: 0.4),
        ),
        child: isLoading
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                    color: Colors.white, strokeWidth: 2))
            : Text(text,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1)),
      ),
    );
  }
}

class _GoogleButton extends StatelessWidget {
  final VoidCallback onPressed;

  const _GoogleButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: const Icon(Icons.g_mobiledata, size: 28, color: Colors.black87),
      label: const Text("Entrar com Google",
          style: TextStyle(color: Colors.black87, fontWeight: FontWeight.w600)),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        side: const BorderSide(color: Color(0xFFEEEEEE), width: 1.5),
      ),
    );
  }
}

class _RoleCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  const _RoleCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primaryPurple.withValues(alpha: 0.05)
              : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color:
                  isSelected ? AppColors.primaryPurple : Colors.grey.shade200,
              width: isSelected ? 2 : 1),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                      color: AppColors.primaryPurple.withValues(alpha: 0.1),
                      blurRadius: 8,
                      offset: const Offset(0, 4))
                ]
              : [],
        ),
        child: Column(
          children: [
            Icon(icon,
                size: 32,
                color: isSelected ? AppColors.primaryPurple : Colors.grey),
            const SizedBox(height: 8),
            Text(title,
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color:
                        isSelected ? AppColors.primaryPurple : Colors.black87)),
            Text(subtitle,
                style: const TextStyle(fontSize: 10, color: Colors.grey)),
          ],
        ),
      ),
    );
  }
}

class _DividerOr extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      children: const [
        Expanded(child: Divider(color: Color(0xFFEEEEEE), thickness: 1.5)),
        Padding(
            padding: EdgeInsets.symmetric(horizontal: 10),
            child: Text("OU",
                style: TextStyle(
                    color: Colors.grey,
                    fontSize: 12,
                    fontWeight: FontWeight.bold))),
        Expanded(child: Divider(color: Color(0xFFEEEEEE), thickness: 1.5)),
      ],
    );
  }
}
