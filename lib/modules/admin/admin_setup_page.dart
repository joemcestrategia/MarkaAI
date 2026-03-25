import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/theme/app_colors.dart';

class AdminSetupPage extends StatefulWidget {
  const AdminSetupPage({super.key});

  @override
  State<AdminSetupPage> createState() => _AdminSetupPageState();
}

class _AdminSetupPageState extends State<AdminSetupPage> {
  bool _loading = true;
  String _message = "Configurando seu acesso administrativo...";
  bool _success = false;

  @override
  void initState() {
    super.initState();
    _claimAdmin();
  }

  Future<void> _claimAdmin() async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) {
        setState(() {
          _message = "Você precisa estar logado para configurar o admin.";
          _loading = false;
        });
        return;
      }

      await Supabase.instance.client
          .from('users')
          .update({
        'role': 'admin',
      }).eq('id', user.id);

      setState(() {
        _message = "Sucesso! Sua conta agora tem permissões de Administrador.";
        _loading = false;
        _success = true;
      });
    } catch (e) {
      setState(() {
        _message = "Erro ao configurar admin: $e";
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(30.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                _success ? Icons.check_circle : Icons.admin_panel_settings,
                size: 80,
                color: _success ? Colors.green : AppColors.primaryPurple,
              ),
              const SizedBox(height: 24),
              Text(
                _message,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 32),
              if (!_loading)
                ElevatedButton(
                  onPressed: () {
                    if (_success) {
                      Navigator.pushReplacementNamed(context, '/admin');
                    } else {
                      Navigator.pushReplacementNamed(context, '/login');
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryPurple,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 15),
                  ),
                  child: Text(_success ? "Ir para o Painel Admin" : "Voltar"),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
