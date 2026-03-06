import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import 'subscription_service.dart';

class SubscriptionPlansPage extends StatefulWidget {
  const SubscriptionPlansPage({super.key});

  @override
  State<SubscriptionPlansPage> createState() => _SubscriptionPlansPageState();
}

class _SubscriptionPlansPageState extends State<SubscriptionPlansPage> {
  SubscriptionPlan _currentPlan = SubscriptionPlan.start;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadCurrentPlan();
  }

  Future<void> _loadCurrentPlan() async {
    final plan = await SubscriptionService.getCurrentPlan();
    if (mounted) {
      setState(() {
        _currentPlan = plan;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Planos e Assinaturas',
            style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      backgroundColor: Colors.grey[50], // Fundo levemente cinza
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                _buildHeader(),
                const SizedBox(height: 30),
                _buildPlanCard(SubscriptionPlan.start,
                    isCurrent: _currentPlan == SubscriptionPlan.start),
                _buildPlanCard(SubscriptionPlan.flex,
                    isCurrent: _currentPlan == SubscriptionPlan.flex),
                _buildPlanCard(SubscriptionPlan.plus,
                    isCurrent: _currentPlan == SubscriptionPlan.plus),
                _buildPlanCard(SubscriptionPlan.prime,
                    isCurrent: _currentPlan == SubscriptionPlan.prime),
                const SizedBox(height: 40),
                const Text(
                  "Dúvidas? Entre em contato com o suporte.",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey),
                ),
              ],
            ),
    );
  }

  Widget _buildHeader() {
    return Column(
      children: const [
        Text(
          "Escolha o plano ideal para o seu negócio",
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        ),
        SizedBox(height: 10),
        Text(
          "Upgrade a qualquer momento. Cancele quando quiser.",
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, color: Colors.grey),
        ),
      ],
    );
  }

  Widget _buildPlanCard(SubscriptionPlan plan, {required bool isCurrent}) {
    final details = SubscriptionService.getPlanDetails(plan);
    final bool isFree = details['price'] == 0.00;

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: isCurrent
            ? Border.all(color: AppColors.primaryPurple, width: 2)
            : Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header do Card
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: isCurrent
                  ? AppColors.primaryPurple.withValues(alpha: 0.05)
                  : Colors.transparent,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      details['name'],
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      details['description'],
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                  ],
                ),
                if (isCurrent)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.primaryPurple,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      "ATUAL",
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold),
                    ),
                  ),
              ],
            ),
          ),

          const Divider(height: 1),

          // Preço e Features
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      isFree
                          ? "Grátis"
                          : "R\$ ${details['price'].toStringAsFixed(2).replaceAll('.', ',')}",
                      style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w900,
                          color: Colors.black87),
                    ),
                    if (!isFree)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 6, left: 4),
                        child:
                            Text("/mês", style: TextStyle(color: Colors.grey)),
                      ),
                  ],
                ),
                const SizedBox(height: 20),
                _buildFeatureItem(
                    "Até ${details['employeeLimit']} profissionais"),
                _buildFeatureItem("Link Personalizado",
                    isCheck: details['customLink']),
                _buildFeatureItem("Backup Google Calendar", isCheck: true),

                // Fotos
                _buildFeatureItem(
                    plan == SubscriptionPlan.start
                        ? "1 Foto por Serviço"
                        : "Até 5 Fotos por Serviço",
                    isCheck: true),

                // Ads
                _buildFeatureItem(
                    plan == SubscriptionPlan.start
                        ? "Exibe Publicidade"
                        : "Sem Anúncios",
                    isCheck: plan != SubscriptionPlan.start),

                _buildFeatureItem(
                    details['onlinePayment']
                        ? "Pagamentos Online"
                        : "Sem pagamentos online",
                    isCheck: details['onlinePayment']),

                // Agenda Avançada
                _buildFeatureItem(
                    plan == SubscriptionPlan.start
                        ? "Agenda Simples"
                        : "Agenda Otimizada",
                    isCheck: plan != SubscriptionPlan.start),

                // Features Específicas
                if (plan == SubscriptionPlan.plus ||
                    plan == SubscriptionPlan.prime)
                  _buildFeatureItem("Gestão Financeira & Comissões",
                      isCheck: true),
                if (plan == SubscriptionPlan.prime)
                  _buildFeatureItem("Controle de Estoque", isCheck: true),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: isCurrent
                        ? null
                        : () async {
                            debugPrint(
                                "DEBUG: 'Assinar' button pressed for plan: $plan");
                            final success =
                                await SubscriptionService.startPurchaseFlow(
                                    context, plan);
                            debugPrint(
                                "DEBUG: startPurchaseFlow returned: $success");

                            if (success) {
                              debugPrint(
                                  "DEBUG: Updating UI state to plan: $plan");
                              setState(() {
                                _currentPlan = plan;
                              });
                              await _loadCurrentPlan();
                              debugPrint(
                                  "DEBUG: _loadCurrentPlan finished. Current plan is now: $_currentPlan");
                            }
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryPurple,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                      disabledBackgroundColor: Colors.grey[300],
                      disabledForegroundColor: Colors.grey[500],
                    ),
                    child: Text(
                      isCurrent
                          ? "SEU PLANO ATUAL"
                          : (isFree ? "FAZER DOWNGRADE" : "ASSINAR AGORA"),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeatureItem(String text, {bool isCheck = true}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Icon(
            isCheck ? Icons.check_circle : Icons.cancel,
            color: isCheck ? Colors.green : Colors.grey[400],
            size: 20,
          ),
          const SizedBox(width: 10),
          Text(text, style: const TextStyle(fontSize: 14)),
        ],
      ),
    );
  }
}
