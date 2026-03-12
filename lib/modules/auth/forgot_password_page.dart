import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../core/theme/app_colors.dart';

class ForgotPasswordPage extends StatefulWidget {
  const ForgotPasswordPage({super.key});

  @override
  State<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends State<ForgotPasswordPage> {
  final _emailCtrl = TextEditingController();
  bool _isLoading = false;
  bool _emailSent = false;

  @override
  void dispose() {
    _emailCtrl.dispose();
    super.dispose();
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: Colors.redAccent,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  Future<void> _handleResetPassword() async {
    final email = _emailCtrl.text.trim();
    if (email.isEmpty) {
      _showError("Por favor, insira seu e-mail.");
      return;
    }
    if (!email.contains('@')) {
      _showError("E-mail inválido.");
      return;
    }

    setState(() => _isLoading = true);
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      if (mounted) setState(() => _emailSent = true);
    } on FirebaseAuthException catch (e) {
      if (e.code == 'user-not-found') {
        _showError("E-mail não encontrado no sistema.");
      } else if (e.code == 'invalid-email') {
        _showError("Formato de e-mail inválido.");
      } else if (e.code == 'too-many-requests') {
        _showError("Muitas tentativas. Aguarde e tente novamente.");
      } else {
        _showError("Erro: ${e.message}");
      }
    } catch (_) {
      _showError("Ocorreu um erro inesperado.");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width > 900;

    return Scaffold(
      backgroundColor: Colors.white,
      body: Row(
        children: [
          // ── Painel esquerdo (Desktop apenas) ──────────────────────
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
                        const SizedBox(height: 24),
                        const Text(
                          "Recupere o acesso à sua conta.",
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 28,
                              fontWeight: FontWeight.w700,
                              height: 1.3),
                        ),
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 10),
                          decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.2))),
                          child: const Text(
                              "🔒 Redefinição de senha segura e rápida",
                              style:
                                  TextStyle(color: Colors.white, fontSize: 13)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

          // ── Painel direito (Formulário) ────────────────────────────
          Expanded(
            flex: isDesktop ? 6 : 1,
            child: Container(
              color: Colors.white,
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(30),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 500),
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 350),
                      child:
                          _emailSent ? _buildSuccess() : _buildForm(isDesktop),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildForm(bool isDesktop) {
    return Column(
      key: const ValueKey('form'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Logo (mobile apenas)
        if (!isDesktop) ...[
          Center(
            child: Image.asset('assets/images/logo_purple.png',
                height: 96, fit: BoxFit.contain),
          ),
          const SizedBox(height: 12),
        ],
        const SizedBox(height: 20),

        // Botão voltar
        Row(
          children: [
            InkWell(
              onTap: () => Navigator.pop(context),
              borderRadius: BorderRadius.circular(8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.arrow_back_ios_new,
                      size: 14, color: Colors.grey),
                  const SizedBox(width: 4),
                  Text("Voltar", style: TextStyle(color: Colors.grey.shade600)),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),

        const Text(
          "Esqueceu a senha?",
          style: TextStyle(
              fontSize: 28, fontWeight: FontWeight.bold, color: Colors.black87),
        ),
        const Text(
          "Informe seu e-mail e enviaremos um link para criar uma nova senha.",
          style: TextStyle(color: Colors.grey, height: 1.5),
        ),
        const SizedBox(height: 30),

        // Campo de email — mesmo estilo do _ModernInput do login
        TextFormField(
          controller: _emailCtrl,
          keyboardType: TextInputType.emailAddress,
          onFieldSubmitted: (_) => _handleResetPassword(),
          style: const TextStyle(color: Colors.black87),
          decoration: InputDecoration(
            labelText: "E-mail",
            labelStyle: TextStyle(color: Colors.grey[600], fontSize: 14),
            prefixIcon: Icon(Icons.email_outlined,
                color: AppColors.primaryPurple.withValues(alpha: 0.7),
                size: 20),
            filled: true,
            fillColor: const Color(0xFFFAFAFA),
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
                borderSide: const BorderSide(
                    color: AppColors.primaryPurple, width: 1.5)),
          ),
        ),
        const SizedBox(height: 24),

        // Botão — mesmo estilo do _PrimaryButton do login
        SizedBox(
          height: 50,
          child: ElevatedButton(
            onPressed: _isLoading ? null : _handleResetPassword,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryPurple,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              elevation: 2,
              shadowColor: AppColors.primaryPurple.withValues(alpha: 0.4),
            ),
            child: _isLoading
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2))
                : const Text("ENVIAR LINK DE RECUPERAÇÃO",
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5)),
          ),
        ),
      ],
    );
  }

  Widget _buildSuccess() {
    return Column(
      key: const ValueKey('success'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 40),
        Center(
          child: Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
                shape: BoxShape.circle, color: Colors.green.shade50),
            child: Icon(Icons.mark_email_read_rounded,
                size: 42, color: Colors.green.shade500),
          ),
        ),
        const SizedBox(height: 24),
        const Text(
          "E-mail enviado!",
          textAlign: TextAlign.center,
          style: TextStyle(
              fontSize: 28, fontWeight: FontWeight.bold, color: Colors.black87),
        ),
        const SizedBox(height: 8),
        Text(
          "Enviamos um link para ${_emailCtrl.text.trim()}.\nVerifique também a pasta de spam.",
          textAlign: TextAlign.center,
          style:
              TextStyle(color: Colors.grey.shade600, height: 1.6, fontSize: 14),
        ),
        const SizedBox(height: 30),
        SizedBox(
          height: 50,
          child: ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryPurple,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              elevation: 2,
              shadowColor: AppColors.primaryPurple.withValues(alpha: 0.4),
            ),
            child: const Text("VOLTAR PARA O LOGIN",
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5)),
          ),
        ),
      ],
    );
  }
}
