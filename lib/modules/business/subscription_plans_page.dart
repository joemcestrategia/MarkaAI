import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import 'subscription_service.dart';
import 'trial_service.dart';

class SubscriptionPlansPage extends StatefulWidget {
  const SubscriptionPlansPage({super.key});

  @override
  State<SubscriptionPlansPage> createState() => _SubscriptionPlansPageState();
}

class _SubscriptionPlansPageState extends State<SubscriptionPlansPage> {
  SubscriptionPlan _currentPlan = SubscriptionPlan.free;
  bool _isLoading = true;
  // Estado do trial
  bool _canUseTrial = false;
  bool _trialActive = false;
  int _trialDaysRemaining = 0;

  @override
  void initState() {
    super.initState();
    _loadCurrentPlan();
  }

  Future<void> _loadCurrentPlan() async {
    final plan = await SubscriptionService.getCurrentPlan();
    final trialStatus = await TrialService.getTrialStatus();
    if (mounted) {
      setState(() {
        _currentPlan = plan;
        _canUseTrial = trialStatus['canUseTrial'] as bool;
        _trialActive = trialStatus['trialActive'] as bool;
        _trialDaysRemaining = trialStatus['daysRemaining'] as int;
        _isLoading = false;
      });
    }
  }

  /// Ativa o trial de 3 meses para o plano escolhido
  Future<void> _ativarTrial(String planId) async {
    // Mostra loading
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
          child: CircularProgressIndicator(color: Color(0xFF0891B2))),
    );
    final ok = await TrialService.activateTrial(planId);
    if (mounted) Navigator.of(context, rootNavigator: true).pop();
    if (!mounted) return;

    if (ok) {
      await _loadCurrentPlan();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('🎉 Trial ativado! Aproveite 3 meses grátis.'),
          backgroundColor: Color(0xFF0891B2),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Trial indisponível — você já utilizou seu período de teste.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Planos e Assinaturas',
            style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: AppColors.primaryPurple,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      backgroundColor: const Color(0xFFF4F4F8),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                _buildHeader(),
                // Banner de trial disponível
                if (_canUseTrial && !_trialActive) _buildTrialBanner(),
                // Banner de trial ativo
                if (_trialActive) _buildTrialActiveBanner(),
                const SizedBox(height: 8),
                _buildPlanCard(SubscriptionPlan.free,
                    isCurrent: _currentPlan == SubscriptionPlan.free),
                _buildPlanCard(SubscriptionPlan.start,
                    isCurrent: _currentPlan == SubscriptionPlan.start),
                _buildPlanCard(SubscriptionPlan.plus,
                    isCurrent: _currentPlan == SubscriptionPlan.plus),
                _buildPlanCard(SubscriptionPlan.pro,
                    isCurrent: _currentPlan == SubscriptionPlan.pro),
                const SizedBox(height: 20),
                const Center(
                  child: Text(
                    "Dúvidas? Entre em contato com o suporte.",
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
                const SizedBox(height: 40),
              ],
            ),
    );
  }

  Widget _buildHeader() {
    final planName =
        SubscriptionService.getPlanDetails(_currentPlan)['name'] as String;
    String statusLabel = 'Você está no plano $planName';
    if (_trialActive) {
      statusLabel =
          'Testando o plano $planName · $_trialDaysRemaining dias restantes';
    }
    return Column(
      children: [
        const Text(
          "Escolha o plano ideal para o seu negócio",
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        const Text(
          "Upgrade a qualquer momento. Cancele quando quiser.",
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, color: Colors.grey),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: _trialActive
                  ? [const Color(0xFF0891B2), const Color(0xFF06B6D4)]
                  : [const Color(0xFF6B21A8), const Color(0xFF9333EA)],
            ),
            borderRadius: BorderRadius.circular(30),
            boxShadow: [
              BoxShadow(
                color: (_trialActive
                        ? const Color(0xFF0891B2)
                        : const Color(0xFF6B21A8))
                    .withOpacity(0.3),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _trialActive ? Icons.timer : Icons.workspace_premium,
                color: Colors.white,
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                statusLabel,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTrialBanner() {
    return Container(
      margin: const EdgeInsets.only(top: 16, bottom: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0891B2), Color(0xFF06B6D4)],
        ),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0891B2).withOpacity(0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: const Row(
        children: [
          Icon(Icons.star_rounded, color: Colors.white, size: 28),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '🎁 3 meses grátis disponíveis!',
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 15),
                ),
                SizedBox(height: 2),
                Text(
                  'Escolha um plano pago abaixo e clique em "Testar Grátis". Apenas 1 trial por conta.',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTrialActiveBanner() {
    return Container(
      margin: const EdgeInsets.only(top: 16, bottom: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.green.shade50,
        border: Border.all(color: Colors.green.shade300),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(Icons.check_circle, color: Colors.green.shade600, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Período de teste ativo!',
                  style: TextStyle(
                      color: Colors.green.shade800,
                      fontWeight: FontWeight.bold,
                      fontSize: 15),
                ),
                Text(
                  '$_trialDaysRemaining dias restantes · Para continuar após o trial, assine o plano.',
                  style: TextStyle(color: Colors.green.shade700, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Cores do gradiente por plano
  List<Color> _planGradientColors(SubscriptionPlan plan) {
    switch (plan) {
      case SubscriptionPlan.start:
        return [const Color(0xFF059669), const Color(0xFF10B981)];
      case SubscriptionPlan.plus:
        return [const Color(0xFF6B21A8), const Color(0xFF9333EA)];
      case SubscriptionPlan.pro:
        return [const Color(0xFFB45309), const Color(0xFFF59E0B)];
      default: // free
        return [const Color(0xFF374151), const Color(0xFF6B7280)];
    }
  }

  Widget _buildPlanCard(SubscriptionPlan plan, {required bool isCurrent}) {
    final details = SubscriptionService.getPlanDetails(plan);
    final bool isFree = (details['price'] as double) == 0.0;
    final List<Color> gradient = _planGradientColors(plan);
    final Color accentColor = gradient[0];

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isCurrent ? accentColor : accentColor.withOpacity(0.25),
          width: isCurrent ? 2.5 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: accentColor.withOpacity(isCurrent ? 0.35 : 0.1),
            blurRadius: isCurrent ? 22 : 8,
            spreadRadius: isCurrent ? 1 : 0,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Header colorido por plano ──────────────────────────────
          Container(
            padding: EdgeInsets.fromLTRB(20, isCurrent ? 12 : 18, 20, 18),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: gradient,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Badge "SEU PLANO ATUAL"
                if (isCurrent)
                  Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.22),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white60),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.verified, color: Colors.white, size: 14),
                        SizedBox(width: 5),
                        Text(
                          'SEU PLANO ATUAL',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ],
                    ),
                  ),
                // Nome + Preço lado a lado
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            details['name'] as String,
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          Text(
                            details['description'] as String,
                            style: TextStyle(
                                fontSize: 12,
                                color: Colors.white.withOpacity(0.85)),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          isFree
                              ? 'Grátis'
                              : 'R\$ ${(details['price'] as double).toStringAsFixed(2).replaceAll('.', ',')}',
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                          ),
                        ),
                        if (!isFree)
                          Text(
                            '/mês',
                            style: TextStyle(
                                color: Colors.white.withOpacity(0.8),
                                fontSize: 12),
                          ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),

          // ── Features ──────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildFeatureItem(
                    'Até ${details['employeeLimit']} profissionais',
                    isCheck: true,
                    accentColor: accentColor),
                _buildFeatureItem('Link Personalizado',
                    isCheck: details['customLink'] as bool,
                    accentColor: accentColor),
                _buildFeatureItem('Backup Google Calendar',
                    isCheck: true, accentColor: accentColor),
                _buildFeatureItem(
                    (plan == SubscriptionPlan.free ||
                            plan == SubscriptionPlan.start)
                        ? '1 Foto por Serviço'
                        : 'Até 5 Fotos por Serviço',
                    isCheck: true,
                    accentColor: accentColor),
                _buildFeatureItem(
                    plan == SubscriptionPlan.free
                        ? 'Exibe Publicidade'
                        : 'Sem Anúncios',
                    isCheck: plan != SubscriptionPlan.free,
                    accentColor: accentColor),
                _buildFeatureItem(
                    (details['onlinePayment'] as bool)
                        ? 'Pagamentos Online (PIX & Cartão)'
                        : 'Sem pagamentos online',
                    isCheck: details['onlinePayment'] as bool,
                    accentColor: accentColor),
                _buildFeatureItem(
                    (plan == SubscriptionPlan.free ||
                            plan == SubscriptionPlan.start)
                        ? 'Agenda Simples'
                        : 'Agenda Otimizada com Bloqueio',
                    isCheck: plan == SubscriptionPlan.plus ||
                        plan == SubscriptionPlan.pro,
                    accentColor: accentColor),
                if (plan == SubscriptionPlan.plus ||
                    plan == SubscriptionPlan.pro)
                  _buildFeatureItem('Gestão Financeira & Comissões',
                      isCheck: true, accentColor: accentColor),
                if (plan == SubscriptionPlan.pro)
                  _buildFeatureItem('Controle de Estoque Completo',
                      isCheck: true, accentColor: accentColor),
                const SizedBox(height: 16),
                // ── Botões de ação ────────────────────────────────
                if (isCurrent)
                  // Plano ativo
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: null,
                      style: ElevatedButton.styleFrom(
                        disabledBackgroundColor: Colors.grey[100],
                        disabledForegroundColor: Colors.grey[500],
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        elevation: 0,
                      ),
                      child: const Text('✓ Plano Ativo',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 14)),
                    ),
                  )
                else if (isFree)
                  // Plano gratuito — downgrade direto
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: () async {
                        final success =
                            await SubscriptionService.startPurchaseFlow(
                                context, plan);
                        if (success && mounted) {
                          setState(() => _currentPlan = plan);
                          await _loadCurrentPlan();
                        }
                      },
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: accentColor.withOpacity(0.5)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      child: Text('USAR PLANO FREE',
                          style: TextStyle(
                              color: accentColor,
                              fontWeight: FontWeight.bold,
                              fontSize: 14)),
                    ),
                  )
                else if (_canUseTrial) ...[
                  // ── Trial disponível: trial é a opção principal ──
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.card_giftcard, size: 18),
                      label: const Text('TESTAR 3 MESES GRÁTIS',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 14)),
                      onPressed: () async {
                        await _ativarTrial(SubscriptionService.getPlanId(plan));
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0891B2),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        elevation: 0,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  // ── Compra como opção secundária (link) ──────────
                  Center(
                    child: TextButton(
                      onPressed: () async {
                        final success =
                            await SubscriptionService.startPurchaseFlow(
                                context, plan);
                        if (success && mounted) {
                          setState(() => _currentPlan = plan);
                          await _loadCurrentPlan();
                        }
                      },
                      child: Text(
                        'Já quero assinar agora →',
                        style: TextStyle(
                          color: accentColor,
                          fontSize: 13,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                  ),
                ] else ...[
                  // ── Trial já usado: só compra ────────────────────
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () async {
                        final success =
                            await SubscriptionService.startPurchaseFlow(
                                context, plan);
                        if (success && mounted) {
                          setState(() => _currentPlan = plan);
                          await _loadCurrentPlan();
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: accentColor,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        elevation: 0,
                      ),
                      child: const Text('ASSINAR AGORA',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 14)),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeatureItem(
    String text, {
    required bool isCheck,
    required Color accentColor,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Icon(
            isCheck ? Icons.check_circle : Icons.cancel,
            color: isCheck ? accentColor : Colors.grey[400],
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 14,
                color: isCheck ? Colors.black87 : Colors.grey[500],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
