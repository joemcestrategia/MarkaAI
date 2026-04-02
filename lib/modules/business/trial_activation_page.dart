import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import 'subscription_service.dart';
import 'trial_service.dart';

class TrialActivationPage extends StatefulWidget {
  const TrialActivationPage({super.key});

  @override
  State<TrialActivationPage> createState() => _TrialActivationPageState();
}

class _TrialActivationPageState extends State<TrialActivationPage> {
  final SubscriptionPlan _selectedPlan = SubscriptionPlan.plus;
  bool _isLoading = false;

  Future<void> _activateTrial() async {
    final planDetails = SubscriptionService.getPlanDetails(_selectedPlan);

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text("Testar ${planDetails['name']}"),
        content: Text(
            "Você tem certeza que deseja testar o plano ${planDetails['name']} grátis por 1 mês?\n\n"
            "Após esse período, você poderá escolher se deseja assinar ou voltar para o plano gratuito."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Cancelar", style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryPurple,
              foregroundColor: Colors.white,
            ),
            child: const Text("Sim, ativar teste!"),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isLoading = true);

    bool activated = await TrialService.activateTrial();

    if (mounted) {
      if (activated) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                "🎉 Parabéns! Trial ativado com sucesso. Aproveite seu 1 mês de Plus!"),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(
            context, true); // Retorna true para atualizar status na home
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                "Ocorreu um erro ao ativar o trial. Você já utilizou o benefício?"),
            backgroundColor: Colors.red,
          ),
        );
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final details = SubscriptionService.getPlanDetails(_selectedPlan);

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FD),
      appBar: AppBar(
        title: const Text("Teste Grátis por 1 Mês",
            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        centerTitle: true,
        backgroundColor: AppColors.primaryPurple,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primaryPurple))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(Icons.stars, size: 80, color: AppColors.primaryPurple),
                  const SizedBox(height: 24),
                  const Text(
                    "Experimente o Plano Plus",
                    style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primaryPurple),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    "Libere todos os recursos do plano Plus gratuitamente por 1 mês. Sem compromisso e sem cartão de crédito.",
                    style: TextStyle(fontSize: 16, color: Colors.black87),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppColors.primaryPurple.withValues(alpha: 0.2)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          blurRadius: 15,
                          offset: const Offset(0, 5),
                        )
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              details['name'],
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: AppColors.primaryPurple,
                              ),
                            ),
                            const Icon(Icons.check_circle, color: Colors.green),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          details['description'],
                          style: const TextStyle(fontSize: 15, color: Colors.black54),
                        ),
                        const Divider(height: 32),
                        const Text(
                          "Recursos inclusos no teste:",
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                        const SizedBox(height: 12),
                        ...((details['features'] as List? ?? []).take(5)).map((f) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            children: [
                              const Icon(Icons.done, size: 16, color: Colors.green),
                              const SizedBox(width: 8),
                              Expanded(child: Text(f.toString(), style: const TextStyle(fontSize: 13))),
                            ],
                          ),
                        )),
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),
                  ElevatedButton(
                    onPressed: _activateTrial,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryPurple,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                      elevation: 4,
                    ),
                    child: const Text(
                      "Começar Meu Mês Grátis",
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    "Ao final do teste, sua conta voltará automaticamente para o plano Free, a menos que você escolha assinar.",
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
    );
  }
}
