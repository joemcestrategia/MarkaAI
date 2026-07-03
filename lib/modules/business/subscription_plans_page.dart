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
  DateTime? _subscriptionStartedAt;
  DateTime? _currentPeriodEnd;
  bool _cancelAtPeriodEnd = false;
  bool _hasUsedTrial = false;
  bool _isLoadingLive = true;
  LiveSubscriptionStatus? _liveStatus;

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
    if (_shopId == null) return;
    try {
      if (mounted) setState(() => _isLoadingLive = true);
      final live = await SubscriptionService.getLiveSubscriptionStatus(shopId: _shopId!);
      
      if (mounted) {
        setState(() {
          _liveStatus = live;
          _currentPlan = SubscriptionPlan.values.firstWhere(
            (p) => SubscriptionService.getPlanId(p) == live.planId, 
            orElse: () => SubscriptionPlan.free,
          );
          _trialActive = live.status == 'trialing';
          _subscriptionStartedAt = live.subscriptionStartedAt;
          _currentPeriodEnd = live.currentPeriodEnd;
          _cancelAtPeriodEnd = live.cancelAtPeriodEnd;
          _hasUsedTrial = live.hasUsedTrial;
          
          if (_trialActive && _currentPeriodEnd != null) {
            _trialDaysRemaining = _currentPeriodEnd!.difference(DateTime.now()).inDays;
          } else {
            _trialDaysRemaining = 0;
          }
          
          _canUseTrial = !_hasUsedTrial && _currentPlan == SubscriptionPlan.free;
          _isLoadingLive = false;
        });
      }
    } catch (e) {
      debugPrint("Erro ao carregar o plano atual: $e");
      if (mounted) {
        setState(() => _isLoadingLive = false);
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
      body: _shopId == null || _isLoadingLive
          ? const Center(child: CircularProgressIndicator(color: AppColors.primaryPurple))
          : Column(
              children: [
                if (_liveStatus != null && !_liveStatus!.isLive)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                    color: Colors.orange.shade100,
                    child: const Text(
                      "Mostrando último dado conhecido da assinatura.",
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.deepOrange, fontSize: 12),
                    ),
                  ),
                Expanded(
                  child: ListView(
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
                  ),
                ),
              ],
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
                  _buildFeatureItem('1 profissional cadastrado', isCheck: true, accentColor: accentColor),
                  _buildFeatureItem('Pagamentos via PIX online', isCheck: true, accentColor: accentColor),
                  _buildFeatureItem('Sinal obrigatório para reservar horário', isCheck: true, accentColor: accentColor),
                  _buildFeatureItem('Otimização automática de horários', isCheck: true, accentColor: accentColor),
                  _buildFeatureItem('3 fotos por serviço', isCheck: true, accentColor: accentColor),
                  _buildFeatureItem('Desconto automático de aniversário', isCheck: false, accentColor: accentColor),
                  _buildFeatureItem('Escolha de profissional pelo cliente', isCheck: false, accentColor: accentColor),
                  _buildFeatureItem('Aba Financeira e Gestão de Estoque', isCheck: false, accentColor: accentColor),
                ] else if (plan == SubscriptionPlan.plus) ...[
                  _buildFeatureItem('Tudo do plano Start +', isCheck: true, accentColor: accentColor),
                  _buildFeatureItem('Até 2 profissionais cadastrados', isCheck: true, accentColor: accentColor),
                  _buildFeatureItem('Cartão de Crédito e Débito online', isCheck: true, accentColor: accentColor),
                  _buildFeatureItem('Aba Financeira (receitas, despesas e comissões)', isCheck: true, accentColor: accentColor),
                  _buildFeatureItem('Desconto automático de aniversário', isCheck: true, accentColor: accentColor),
                  _buildFeatureItem('Escolha de profissional pelo cliente', isCheck: true, accentColor: accentColor),
                  _buildFeatureItem('Cupons e promoções personalizadas', isCheck: true, accentColor: accentColor),
                  _buildFeatureItem('Clientes VIP, bloqueio e automações', isCheck: true, accentColor: accentColor),
                  _buildFeatureItem('Feriados personalizados por profissional', isCheck: true, accentColor: accentColor),
                  _buildFeatureItem('Gestão de Estoque completa', isCheck: false, accentColor: accentColor),
                  _buildFeatureItem('Visitantes e leads da loja', isCheck: false, accentColor: accentColor),
                  _buildFeatureItem('Emissão de NFS-e', isCheck: false, accentColor: accentColor),
                ] else if (plan == SubscriptionPlan.pro) ...[
                  _buildFeatureItem('Tudo do plano Plus +', isCheck: true, accentColor: accentColor),
                  _buildFeatureItem('Até 3 profissionais cadastrados', isCheck: true, accentColor: accentColor),
                  _buildFeatureItem('Gestão de Estoque completa', isCheck: true, accentColor: accentColor),
                  _buildFeatureItem('Visitantes e leads da loja', isCheck: true, accentColor: accentColor),
                  _buildFeatureItem('Lembrete automático por WhatsApp', isCheck: true, accentColor: accentColor),
                  _buildFeatureItem('Emissão de Nota Fiscal Eletrônica (NFS-e)', isCheck: true, accentColor: accentColor),
                  _buildFeatureItem('Análises financeiras avançadas (DRE/Caixa)', isCheck: true, accentColor: accentColor),
                  _buildFeatureItem('Obrigatoriedade de CPF para agendamentos', isCheck: true, accentColor: accentColor),
                  _buildFeatureItem('Suporte VIP direto via WhatsApp', isCheck: true, accentColor: accentColor),
                ],
                const SizedBox(height: 16),
                // ── Botões de ação ────────────────────────────────
                if (isCurrent && !(_liveStatus?.isManual ?? false)) ...[
                  // Plano ativo oficial
                  if (_subscriptionStartedAt != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        'Assinado em: ${_subscriptionStartedAt!.day.toString().padLeft(2, '0')}/${_subscriptionStartedAt!.month.toString().padLeft(2, '0')}/${_subscriptionStartedAt!.year}',
                        style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey[600],
                            fontWeight: FontWeight.w500),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  if (_cancelAtPeriodEnd && _currentPeriodEnd != null)
                    Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.orange.shade200),
                      ),
                      child: Text(
                        'Cancelamento agendado para ${_currentPeriodEnd!.day.toString().padLeft(2, '0')}/${_currentPeriodEnd!.month.toString().padLeft(2, '0')}/${_currentPeriodEnd!.year}. Seu acesso continuará até esta data.',
                        style: TextStyle(
                          color: Colors.orange.shade800,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
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
                  ),
                  if (!isFree) ...[
                    const SizedBox(height: 12),
                    if (_cancelAtPeriodEnd)
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton(
                          onPressed: () async {
                            final ok = await SubscriptionService.reactivateSubscription(
                              context: context,
                              shopId: _shopId!,
                            );
                            if (ok && mounted) {
                              await _loadCurrentPlan();
                            }
                          },
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.green,
                            side: const BorderSide(color: Colors.green),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                          child: const Text('REATIVAR ASSINATURA',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 14)),
                        ),
                      )
                    else
                      SizedBox(
                        width: double.infinity,
                        child: TextButton(
                          onPressed: () async {
                            final motivo = await _pedirMotivoCancelamento(context);
                            if (motivo != null && mounted) {
                              final ok = await SubscriptionService.cancelSubscription(
                                context: context,
                                shopId: _shopId!,
                                reason: motivo,
                              );
                              if (ok && mounted) {
                                await _loadCurrentPlan();
                              }
                            }
                          },
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.red[400],
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          child: const Text('Cancelar assinatura',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 13)),
                        ),
                      ),
                  ],
                ] else if (isCurrent && (_liveStatus?.isManual ?? false)) ...[
                  // Plano concedido pelo admin / MercadoPago
                  Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.blue.shade200),
                    ),
                    child: Text(
                      'Plano concedido manualmente pelo administrador.',
                      style: TextStyle(
                        color: Colors.blue.shade800,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
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
                      child: const Text('ASSINAR OFICIALMENTE',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 14)),
                    ),
                  ),
                ]
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

  Future<String?> _pedirMotivoCancelamento(BuildContext context) async {
    String? selectedReason;
    final reasons = [
      "Preço",
      "Não uso mais",
      "Faltam funcionalidades",
      "Problema técnico",
      "Encontrei uma alternativa",
      "Outro"
    ];
    
    return await showDialog<String>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              title: const Text('Cancelar Assinatura'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Poderia nos contar o motivo do cancelamento?'),
                  const SizedBox(height: 16),
                  ...reasons.map((reason) {
                    return RadioListTile<String>(
                      title: Text(reason),
                      value: reason,
                      groupValue: selectedReason,
                      onChanged: (val) {
                        setStateDialog(() {
                          selectedReason = val;
                        });
                      },
                      contentPadding: EdgeInsets.zero,
                      visualDensity: const VisualDensity(
                        horizontal: VisualDensity.minimumDensity,
                        vertical: VisualDensity.minimumDensity,
                      ),
                    );
                  }),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, null),
                  child: const Text('Manter Plano'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(ctx, selectedReason ?? 'Não informado'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red[400],
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Confirmar Cancelamento'),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
