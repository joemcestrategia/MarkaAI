import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../../modules/business/trial_service.dart';
import '../../modules/business/trial_activation_page.dart';
import '../../modules/business/subscription_plans_page.dart';

class PaywallModalWidget {
  /// Mostra um modal de Paywall sempre que o usuário tentar acessar um recurso bloqueado.
  static Future<void> show({
    required BuildContext context,
    required String featureName,
  }) async {
    final status = await TrialService.getTrialStatus();
    final canUseTrial = status['canUseTrial'] == true;

    if (!context.mounted) return;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.primaryPurple.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.lock_outline,
                  color: AppColors.primaryPurple),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text("Recurso Exclusivo",
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              "Para acessar $featureName, você precisa de um plano pago.",
              style: const TextStyle(fontSize: 15, color: Colors.black87),
            ),
            const SizedBox(height: 24),
            if (canUseTrial) ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [AppColors.primaryPurple, Color(0xFF4A1F8A)],
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    const Text(
                      "🎁 Experimente de Graça",
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      "Ative seu trial de 90 dias agora e desbloqueie tudo sem cartão de crédito.",
                      style: TextStyle(color: Colors.white70, fontSize: 13),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: AppColors.primaryPurple,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: () {
                        Navigator.pop(ctx);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const TrialActivationPage()),
                        );
                      },
                      child: const Text("Ativar 90 Dias Grátis"),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const SubscriptionPlansPage()),
                  );
                },
                child: const Text("Explorar Planos Pagos",
                    style: TextStyle(color: Colors.grey)),
              ),
            ] else ...[
              // Se já usou o Trial antes, exibe apenas os planos normais
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryPurple,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () {
                  Navigator.pop(ctx);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const SubscriptionPlansPage()),
                  );
                },
                child: const Text("Ver Planos Disponíveis",
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child:
                    const Text("Voltar", style: TextStyle(color: Colors.grey)),
              ),
            ]
          ],
        ),
      ),
    );
  }
}
