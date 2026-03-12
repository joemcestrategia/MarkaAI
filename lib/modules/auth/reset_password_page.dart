import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../core/theme/app_colors.dart';

class ResetPasswordPage extends StatefulWidget {
  final String oobCode;

  const ResetPasswordPage({super.key, required this.oobCode});

  @override
  State<ResetPasswordPage> createState() => _ResetPasswordPageState();
}

class _ResetPasswordPageState extends State<ResetPasswordPage> {
  final _passCtrl = TextEditingController();
  final _passConfirmCtrl = TextEditingController();

  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscurePasswordConfirm = true;

  @override
  void dispose() {
    _passCtrl.dispose();
    _passConfirmCtrl.dispose();
    super.dispose();
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: Colors.redAccent,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  void _showSuccess(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  Future<void> _handleConfirmReset() async {
    final pass = _passCtrl.text.trim();
    final confirm = _passConfirmCtrl.text.trim();

    if (pass.isEmpty || confirm.isEmpty) {
      _showError("Por favor, preencha ambas as senhas.");
      return;
    }

    if (pass.length < 6) {
      _showError("A nova senha deve ter pelo menos 6 caracteres.");
      return;
    }

    if (pass != confirm) {
      _showError("As senhas não coincidem.");
      return;
    }

    setState(() => _isLoading = true);

    try {
      await FirebaseAuth.instance.confirmPasswordReset(
        code: widget.oobCode,
        newPassword: pass,
      );

      _showSuccess("Senha redefinida com sucesso! Redirecionando...");

      // Espera um pouco e redireciona pro fluxo inicial de login
      if (mounted) {
        await Future.delayed(const Duration(seconds: 2));
        if (mounted) {
          Navigator.of(context)
              .pushNamedAndRemoveUntil('/login', (route) => false);
        }
      }
    } on FirebaseAuthException catch (e) {
      if (e.code == 'expired-action-code' || e.code == 'invalid-action-code') {
        _showError(
            "O link de redefinição expirou ou é inválido. Tente solicitar novamente na tela de login.");
      } else {
        _showError("Erro: ${e.message}");
      }
    } catch (e) {
      _showError("Ocorreu um erro inesperado.");
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isDesktop = size.width > 900;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black87),
          onPressed: () => Navigator.of(context)
              .pushNamedAndRemoveUntil('/login', (route) => false),
        ),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(30),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 500),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!isDesktop)
                  Center(
                    child: Column(
                      children: [
                        Image.asset('assets/images/logo_purple.png',
                            height: 96, fit: BoxFit.contain),
                        const SizedBox(height: 12),
                      ],
                    ),
                  ),
                const SizedBox(height: 20),
                const Text(
                  "Criar Nova Senha",
                  style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87),
                ),
                const SizedBox(height: 10),
                const Text(
                  "Sua nova senha deve ser diferente das anteriores usada recentemente.",
                  style: TextStyle(color: Colors.grey, height: 1.5),
                ),
                const SizedBox(height: 30),

                // Nova Senha
                TextFormField(
                  controller: _passCtrl,
                  obscureText: _obscurePassword,
                  decoration: InputDecoration(
                    labelText: "Nova Senha",
                    prefixIcon:
                        const Icon(Icons.lock_outline, color: Colors.grey),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword
                            ? Icons.visibility_off
                            : Icons.visibility,
                        color: Colors.grey,
                      ),
                      onPressed: () =>
                          setState(() => _obscurePassword = !_obscurePassword),
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(15),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(15),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(15),
                      borderSide: const BorderSide(
                          color: AppColors.primaryPurple, width: 2),
                    ),
                    filled: true,
                    fillColor: Colors.grey.shade50,
                  ),
                ),
                const SizedBox(height: 16),

                // Confirmar Senha
                TextFormField(
                  controller: _passConfirmCtrl,
                  obscureText: _obscurePasswordConfirm,
                  decoration: InputDecoration(
                    labelText: "Confirmar Nova Senha",
                    prefixIcon:
                        const Icon(Icons.lock_outline, color: Colors.grey),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePasswordConfirm
                            ? Icons.visibility_off
                            : Icons.visibility,
                        color: Colors.grey,
                      ),
                      onPressed: () => setState(() =>
                          _obscurePasswordConfirm = !_obscurePasswordConfirm),
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(15),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(15),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(15),
                      borderSide: const BorderSide(
                          color: AppColors.primaryPurple, width: 2),
                    ),
                    filled: true,
                    fillColor: Colors.grey.shade50,
                  ),
                ),
                const SizedBox(height: 30),

                // Botão Primário
                SizedBox(
                  height: 55,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryPurple,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15),
                      ),
                      elevation: 0,
                    ),
                    onPressed: _isLoading ? null : _handleConfirmReset,
                    child: _isLoading
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : const Text(
                            "SALVAR NOVA SENHA",
                            style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
