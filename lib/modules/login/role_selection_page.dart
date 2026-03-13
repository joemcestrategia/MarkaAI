import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../clients/client_register_page.dart';
// 🚨 IMPORT CORRIGIDO: Removida a HomePage genérica e adicionada a Home de Negócios
import '../business/business_home_page.dart';

class RoleSelectionPage extends StatelessWidget {
  const RoleSelectionPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.people_alt,
                size: 80, color: AppColors.primaryPurple),
            const SizedBox(height: 24),
            const Text(
              "Como você deseja usar\no MarkaAI?",
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.bold,
                color: AppColors.primaryPurple,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              "Selecione o seu perfil para personalizarmos sua experiência.",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
            const SizedBox(height: 50),

            // OPÇÃO 1: CLIENTE
            _buildRoleCard(
              context,
              title: "Sou Cliente",
              subtitle: "Quero agendar horários e encontrar serviços.",
              icon: Icons.person_outline,
              color: Colors.blue,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (context) => const ClientRegisterPage()),
                );
              },
            ),

            const SizedBox(height: 24),

            // OPÇÃO 2: PROFISSIONAL (DONO)
            _buildRoleCard(
              context,
              title: "Sou Profissional",
              subtitle: "Sou dono de salão ou prestador de serviço.",
              icon: Icons.storefront,
              color: AppColors.primaryPurple,
              onTap: () {
                // 🚨 NAVEGAÇÃO CORRIGIDA: Agora aponta para a Home de Negócios real
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(
                      builder: (context) => const BusinessHomePage()),
                  (route) => false,
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRoleCard(
    BuildContext context, {
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          border: Border.all(color: color.withValues(alpha: 0.3), width: 2),
          borderRadius: BorderRadius.circular(16),
          color: color.withValues(alpha: 0.05),
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
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(fontSize: 14, color: Colors.black54),
                  ),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios,
                size: 16, color: color.withValues(alpha: 0.5)),
          ],
        ),
      ),
    );
  }
}
