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
  SubscriptionPlan? _selectedPlan;
  bool _isLoading = false;

  final List<SubscriptionPlan> _availablePlans = [
    SubscriptionPlan.start,
    SubscriptionPlan.plus,
    SubscriptionPlan.pro
  ];

  Future<void> _activateTrial() async {
    if (_selectedPlan == null) return;

    final planDetails = SubscriptionService.getPlanDetails(_selectedPlan!);
    final planIdString = _selectedPlan.toString().split('.').last;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text("Testar ${planDetails['name']}"),
        content: Text(
            "Você tem certeza que deseja testar o plano ${planDetails['name']} grátis por 90 dias?\n\n"
            "Esta escolha é única e não poderá ser alterada durante o teste."),
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

    bool activated = await TrialService.activateTrial(planIdString);

    if (mounted) {
      if (activated) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                "🎉 Parabéns! Trial ativado com sucesso. Aproveite seus 90 dias!"),
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
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FD),
      appBar: AppBar(
        title: const Text("Teste Grátis por 90 Dias",
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
                  const Text(
                    "Qual plano você deseja testar?",
                    style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primaryPurple),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    "Escolha abaixo qual plano pago você gostaria de experimentar de graça durante 90 dias. Sem cartão de crédito.",
                    style: TextStyle(fontSize: 16, color: Colors.black87),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),
                  ..._availablePlans.map((plan) {
                    final details = SubscriptionService.getPlanDetails(plan);
                    final isSelected = _selectedPlan == plan;

                    return GestureDetector(
                      onTap: () {
                        setState(() => _selectedPlan = plan);
                      },
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 16),
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? AppColors.primaryPurple.withValues(alpha: 0.08)
                              : Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: isSelected
                                ? AppColors.primaryPurple
                                : Colors.grey.shade300,
                            width: 2,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.05),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            )
                          ],
                        ),
                        child: Row(
                          children: [
                            Radio<SubscriptionPlan>(
                              value: plan,
                              groupValue: _selectedPlan,
                              activeColor: AppColors.primaryPurple,
                              onChanged: (SubscriptionPlan? val) {
                                if (val != null) {
                                  setState(() => _selectedPlan = val);
                                }
                              },
                            ),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        details['name'],
                                        style: TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                          color: isSelected
                                              ? AppColors.primaryPurple
                                              : Colors.black87,
                                        ),
                                      ),
                                      Text(
                                        "R\$ ${details['price'].toStringAsFixed(2).replaceAll('.', ',')}/mês",
                                        style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.grey,
                                          decoration:
                                              TextDecoration.lineThrough,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    details['description'],
                                    style: const TextStyle(
                                        fontSize: 14, color: Colors.black54),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: _selectedPlan == null ? null : _activateTrial,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryPurple,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: Colors.grey.shade300,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text(
                      "Começar Teste Gratuitamente",
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
