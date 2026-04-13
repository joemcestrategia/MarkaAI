import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import 'subscription_service.dart';
import 'trial_service.dart';
import '../../core/services/session_service.dart';
import '../../core/services/plan_features_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SubscriptionPlansPage extends StatefulWidget {
  const SubscriptionPlansPage({super.key});

  @override
  State<SubscriptionPlansPage> createState() => _SubscriptionPlansPageState();
}

class _SubscriptionPlansPageState extends State<SubscriptionPlansPage> {
  SubscriptionPlan _currentPlan = SubscriptionPlan.free;
  bool _isLoading = true;
  bool _canUseTrial = false;
  bool _trialActive = false;
  int _trialDaysRemaining = 0;
  String? _shopId;


  @override
  void initState() {
    super.initState();
    _loadShopId();
  }

  Future<void> _loadShopId() async {
    final id = await SessionService.getShopId();
    if (mounted) {
      setState(() {
        _shopId = id;
      });
      _loadCurrentPlan();
    }
  }

  Future<void> _loadCurrentPlan() async {
    try {
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
    } catch (e) {
      debugPrint("Erro ao carregar o plano atual: $e");
      if (mounted) {
        setState(() => _isLoading = false);
      }
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
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('🎉 Trial ativado! Aproveite 1 mês grátis.'),
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
      body: _shopId == null
          ? const Center(child: CircularProgressIndicator())
          : StreamBuilder<List<Map<String, dynamic>>>(
              stream: Supabase.instance.client
                  .from('shops')
                  .stream(primaryKey: ['id'])
                  .eq('id', _shopId!),
              builder: (context, snapshot) {
                if (!snapshot.hasData || snapshot.data!.isEmpty) {
                  return const Center(child: CircularProgressIndicator());
                }

                final shopData = snapshot.data!.first;
                final detection = PlanFeaturesService.detectPlan(shopData);
                _currentPlan = detection['plan'] as SubscriptionPlan;
                _trialActive = detection['trial'] as bool;
                
                if (_trialActive) {
                  final sub = shopData['subscription'] as Map<String, dynamic>?;
                  if (sub != null) {
                    final endStr = (sub['trial_end_date'] ?? sub['trial_ends_at'])?.toString();
                    if (endStr != null) {
                      final end = DateTime.tryParse(endStr);
                      if (end != null) {
                        _trialDaysRemaining = end.difference(DateTime.now()).inDays;
                      }
                    }
                  }
                }
                
                _canUseTrial = shopData['subscription']?['trial_used'] != true;

                return ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    _buildHeader(),
                    if (_canUseTrial && !_trialActive) _buildTrialBanner(),
                    if (_trialActive) _buildTrialActiveBanner(),
                    const SizedBox(height: 16),
                    _buildPlanCard(SubscriptionPlan.free,
                        isCurrent: _currentPlan == SubscriptionPlan.free),
                    _buildPlanCard(SubscriptionPlan.start,
                        isCurrent: _currentPlan == SubscriptionPlan.start),
                    _buildPlanCard(SubscriptionPlan.plus,
                        isCurrent: _currentPlan == SubscriptionPlan.plus),
                    _buildPlanCard(SubscriptionPlan.pro,
                        isCurrent: _currentPlan == SubscriptionPlan.pro),
                  ],
                );
              },
            ),
    );
  }

  Widget _buildHeader() {
    return Column(
      children: [
        const Icon(Icons.rocket_launch, size: 60, color: AppColors.primaryPurple),
        const SizedBox(height: 16),
        const Text(
          'Eleve o seu negócio',
          style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, letterSpacing: -0.5),
        ),
        const SizedBox(height: 8),
        Text(
          'Escolha o plano ideal para a sua marca.',
          style: TextStyle(fontSize: 16, color: Colors.grey[600]),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildTrialBanner() {
    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.cyan.shade800, Colors.cyan.shade600],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
              color: Colors.cyan.withValues(alpha: 0.3), blurRadius: 10, offset: const Offset(0, 4))
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.card_giftcard, color: Colors.white, size: 28),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Presente da Marka!',
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 18),
                    ),
                    Text(
                      'Ganhe 1 mês de Plus inteiramente grátis.',
                      style: TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTrialActiveBanner() {
    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.green.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.green.shade200),
      ),
      child: Row(
        children: [
          const Icon(Icons.auto_awesome, color: Colors.green, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Período de Teste Ativo!',
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
          color: isCurrent ? accentColor : accentColor.withValues(alpha: 0.25),
          width: isCurrent ? 2.5 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: accentColor.withValues(alpha: isCurrent ? 0.35 : 0.1),
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
                      color: Colors.white.withValues(alpha: 0.22),
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
                                color: Colors.white.withValues(alpha: 0.85)),
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
                                color: Colors.white.withValues(alpha: 0.8),
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
                if (plan == SubscriptionPlan.free) ...[
                  _buildFeatureItem('1 profissional cadastrado', isCheck: true, accentColor: accentColor),
                  _buildFeatureItem('Agendamento online (clientes marcam 24h)', isCheck: true, accentColor: accentColor),
                  _buildFeatureItem('Página pública da sua loja', isCheck: true, accentColor: accentColor),
                  _buildFeatureItem('Backup da agenda no Google Calendar', isCheck: true, accentColor: accentColor),
                  _buildFeatureItem('Pagamentos online (PIX ou Cartão)', isCheck: false, accentColor: accentColor),
                  _buildFeatureItem('Sinal obrigatório para reservar horário', isCheck: false, accentColor: accentColor),
                  _buildFeatureItem('Financeiro, comissões e automações', isCheck: false, accentColor: accentColor),
                ] else if (plan == SubscriptionPlan.start) ...[
                  _buildFeatureItem('Tudo do plano Free +', isCheck: true, accentColor: accentColor),
                  _buildFeatureItem('Até 2 profissionais cadastrados', isCheck: true, accentColor: accentColor),
                  _buildFeatureItem('Pagamentos via PIX online', isCheck: true, accentColor: accentColor),
                  _buildFeatureItem('Sinal obrigatório para reservar horário', isCheck: true, accentColor: accentColor),
                  _buildFeatureItem('Desconto automático de aniversário', isCheck: true, accentColor: accentColor),
                  _buildFeatureItem('Cliente escolhe o profissional', isCheck: true, accentColor: accentColor),
                  _buildFeatureItem('Otimização automática de horários', isCheck: true, accentColor: accentColor),
                  _buildFeatureItem('3 fotos por serviço', isCheck: true, accentColor: accentColor),
                  _buildFeatureItem('Cartão de Crédito/Débito online', isCheck: false, accentColor: accentColor),
                  _buildFeatureItem('Aba Financeira e Gestão de Estoque', isCheck: false, accentColor: accentColor),
                ] else if (plan == SubscriptionPlan.plus) ...[
                  _buildFeatureItem('Tudo do plano Start +', isCheck: true, accentColor: accentColor),
                  _buildFeatureItem('Até 3 profissionais cadastrados', isCheck: true, accentColor: accentColor),
                  _buildFeatureItem('Cartão de Crédito e Débito online', isCheck: true, accentColor: accentColor),
                  _buildFeatureItem('Aba Financeira (receitas, despesas e comissões)', isCheck: true, accentColor: accentColor),
                  _buildFeatureItem('Cupons e promoções personalizadas', isCheck: true, accentColor: accentColor),
                  _buildFeatureItem('Clientes VIP, bloqueio e automações', isCheck: true, accentColor: accentColor),
                  _buildFeatureItem('Gestão de Estoque completa', isCheck: true, accentColor: accentColor),
                  _buildFeatureItem('Feriados personalizados por profissional', isCheck: true, accentColor: accentColor),
                  _buildFeatureItem('Visitantes e leads da loja', isCheck: true, accentColor: accentColor),
                ] else if (plan == SubscriptionPlan.pro) ...[
                  _buildFeatureItem('Tudo do plano Plus +', isCheck: true, accentColor: accentColor),
                  _buildFeatureItem('Até 5 profissionais cadastrados', isCheck: true, accentColor: accentColor),
                  _buildFeatureItem('Análises financeiras avançadas (gráficos e insights)', isCheck: true, accentColor: accentColor),
                  _buildFeatureItem('Eficiência operacional e desempenho da equipe', isCheck: true, accentColor: accentColor),
                  _buildFeatureItem('Comparativo de receita por período e serviço', isCheck: true, accentColor: accentColor),
                  _buildFeatureItem('Emissão de Nota Fiscal Eletrônica (NFS-e)', isCheck: true, accentColor: accentColor),
                  _buildFeatureItem('Obrigatoriedade de CPF para agendamentos', isCheck: true, accentColor: accentColor),
                  _buildFeatureItem('Suporte VIP direto via WhatsApp', isCheck: true, accentColor: accentColor),
                ],
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
                                context, plan,
                            );
                        if (success && mounted) {
                          setState(() => _currentPlan = plan);
                          await _loadCurrentPlan();
                        }
                      },
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: accentColor.withValues(alpha: 0.5)),
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
                else if (_canUseTrial && plan == SubscriptionPlan.plus) ...[
                  // ── Trial disponível apenas para o Plus ──
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.card_giftcard, size: 18),
                      label: const Text('TESTAR 1 MÊS GRÁTIS',
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
                                context, plan,
                            );
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
                  // ── Trial já usado ou plano não elegível: só compra ────────────────────
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () async {
                        final success =
                            await SubscriptionService.startPurchaseFlow(
                                context, plan,
                            );
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

  Widget _buildFeatureItem(String text, {required bool isCheck, required Color accentColor}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(
            isCheck ? Icons.check_circle : Icons.cancel,
            size: 18,
            color: isCheck ? accentColor : Colors.grey[300],
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
