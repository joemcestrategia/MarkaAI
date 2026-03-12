import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../onboarding/client_onboarding_page.dart';
import '../login/login_page.dart';

class UserTypePage extends StatelessWidget {
  const UserTypePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.primaryPurple),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Para começar,\nquem é você?",
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: AppColors.primaryPurple,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              "Escolha o perfil que melhor descreve o seu uso do WiSmart.",
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
            const SizedBox(height: 48),

            // BOTÃO CLIENTE
            _buildButton(
              context,
              title: "SOU CLIENTE",
              subtitle: "Quero agendar um serviço agora",
              icon: Icons.person_search,
              color: Colors.blue,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (context) => const ClientOnboardingPage()),
                );
              },
            ),

            const SizedBox(height: 20),

            // BOTÃO PROPRIETÁRIO
            _buildButton(
              context,
              title: "SOU PROPRIETÁRIO",
              subtitle: "Quero gerenciar meu studio e equipe",
              icon: Icons.business_center,
              color: AppColors.primaryPurple,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const LoginPage()),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildButton(BuildContext context,
      {required String title,
      required String subtitle,
      required IconData icon,
      required Color color,
      required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          color: Colors.white,
          border: Border.all(color: color.withValues(alpha: 0.2), width: 2),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            )
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 32),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      // CORREÇÃO AQUI: Trocado .black por .bold ou .w900 para evitar o erro da imagem c9c15d.png
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                          color: color)),
                  const SizedBox(height: 4),
                  Text(subtitle,
                      style:
                          const TextStyle(fontSize: 14, color: Colors.black54)),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios,
                color: color.withValues(alpha: 0.3), size: 16),
          ],
        ),
      ),
    );
  }
}
