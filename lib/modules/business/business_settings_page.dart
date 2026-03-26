import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;
import '../../core/services/auth_service.dart';

import '../../core/theme/app_colors.dart';
import '../../core/services/session_service.dart';
import '../../core/services/shop_data_cache_service.dart';
import '../../core/services/plan_features_service.dart';
import '../../core/constants/plan_features.dart';
import '../../widgets/upgrade_modal.dart';
import 'link_google_business_page.dart';
import '../backup/calendar_backup_page.dart';
import 'payment_settings_page.dart';
import 'subscription_plans_page.dart';
import 'subscription_service.dart';
import '../../core/widgets/plan_gate_widget.dart';

class BusinessSettingsPage extends StatefulWidget {
  const BusinessSettingsPage({super.key});

  @override
  State<BusinessSettingsPage> createState() => _BusinessSettingsPageState();
}

class _BusinessSettingsPageState extends State<BusinessSettingsPage> {
  bool _isLoading = true;
  String? shopId;
  PlanFeatures _currentFeatures = planFeaturesConfig[PlanKey.free]!;
  Stream<PlanFeatures>? _featuresStream;

  // --- ESTADOS DAS CONFIGURAÇÕES ---
  bool _allowMultiple = false;
  bool _allowReschedule = true;
  bool _clientChoosesProfessional = true;
  bool _onlineBookingActive = true;
  bool _autoBlockHolidays = false;

  // ðŸ•’ Intervalo (Slots)
  int _appointmentIntervalMinutes = 60;

  // ðŸš« Evitar Buracos
  bool _preventGaps = false;

  // ðŸ“… Janela de Agendamento (Novo!)
  double _bookingWindowDays = 30.0; // Padrão: 30 dias

  // â° Limite Mínimo de Antecedência (Novo!)
  double _minAdvanceHours = 7.0; // Padrão: 7 horas de antecedência mínima

  // Cancelamento
  String _cancelUnit = 'hours';
  double _cancelValue = 2.0;

  // Financeiro
  bool _cartaoOnline = false;
  bool _debitoPresencial = false;
  bool _pagarPessoalmente = true;
  bool _requireDeposit = false;
  double _depositPercent = 30.0;
  // Pagamento com cartão - única taxa configurável pelo lojista (aplicada no crédito)
  double _creditTaxPercent = 0.0; // 0..20%

  // Notificações
  bool _notifyClientAppointment = true;
  int _notifyDaysBefore = 1; // Padrão: 1 dia antes

  // Novos Recursos: Proteção e Descontos
  bool _trustedOnlyPayInPerson = false;
  bool _birthdayPixDiscountEnabled = false;
  double _birthdayPixDiscountPercent = 10.0;
  double _vipExtraDays = 0.0; // Padrão: 0 dias extras
  bool _restrictProblematicClients = false;

  // Configurações de Automação de Tags (VIP/Sumido)
  double _vipMinVisits = 15.0; // Padrão: 15 visitas
  double _vipAvgInterval = 30.0; // Padrão: 30 dias de intervalo médio
  double _sumidoMaxDays = 45.0; // Padrão: 45 dias sem agendar

  // Google Business
  Map<String, dynamic>? _googleBusiness;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    try {
      String? sId = await SessionService.getShopId();

      if (sId == null || sId.isEmpty) {
        final user = AuthService().currentUser;
        if (user != null) {
          final userDoc = await sb.Supabase.instance.client
              .from('users')
              .select('shop_id')
              .eq('id', user.id)
              .maybeSingle();
          if (userDoc != null) sId = userDoc['shop_id'];
        }
      }

      shopId = sId;

      if (shopId != null) {
        _featuresStream = PlanFeaturesService.streamFeaturesByShopId(shopId!);
        _currentFeatures =
            await PlanFeaturesService.loadFeaturesByShopId(shopId!);

        final doc = await sb.Supabase.instance.client
            .from('shops')
            .select('config, google_business')
            .eq('id', shopId!)
            .maybeSingle();
        if (doc != null) {
          final data = doc;
          _googleBusiness = data['google_business'] as Map<String, dynamic>?;
          if (data.containsKey('config')) {
            final config = data['config'] as Map<String, dynamic>;
            if (mounted) {
              setState(() {
                _allowMultiple = config['permitir_multiplos'] ?? false;
                _allowReschedule = config['permitir_reagendamento'] ?? true;
                _clientChoosesProfessional =
                    config['cliente_escolhe_prof'] ?? true;
                _onlineBookingActive =
                    config['agendamento_online_ativo'] ?? true;
                _autoBlockHolidays = config['auto_block_holidays'] ?? false;

                _appointmentIntervalMinutes =
                    config['intervalo_agenda_min'] ?? 60;
                _preventGaps = config['evitar_buracos_agenda'] ?? false;

                // ðŸ“… Carrega Janela de Dias
                _bookingWindowDays =
                    (config['janela_agendamento_dias'] ?? 30).toDouble();

                // â° Carrega Limite Mínimo de Antecedência
                _minAdvanceHours =
                    (config['limite_minimo_agendamento_horas'] ?? 7).toDouble();

                int dbHours = config['tempo_cancelamento_horas'] ?? 2;
                if (dbHours >= 24 && dbHours % 24 == 0) {
                  _cancelUnit = 'days';
                  _cancelValue = (dbHours / 24).toDouble().clamp(1, 7);
                } else {
                  _cancelUnit = 'hours';
                  _cancelValue = dbHours.toDouble().clamp(1, 24);
                }

                _cartaoOnline = config['cartao_online'] ??
                    config['pagamento_cartao'] ??
                    false;
                _debitoPresencial = config['pagamento_pix'] ??
                    config['debito_presencial'] ??
                    false;
                _pagarPessoalmente = config['pagar_pessoalmente'] ??
                    config['pagamento_dinheiro'] ??
                    true;
                _requireDeposit = config['exigir_sinal'] ?? false;
                _depositPercent = (config['percentual_sinal'] ?? 30).toDouble();
                // cartão: ler única taxa de crédito (0..20%)
                _creditTaxPercent = (config['tax_percent'] ??
                        config['porcentagem_a_vista'] ??
                        0)
                    .toDouble();
                if (_creditTaxPercent < 0) _creditTaxPercent = 0;
                if (_creditTaxPercent > 20) _creditTaxPercent = 20;

                _notifyDaysBefore = config['notificar_dias_antes'] ?? 1;

                _trustedOnlyPayInPerson =
                    config['trusted_only_pay_in_person'] ?? false;
                _birthdayPixDiscountEnabled =
                    config['birthday_pix_discount_enabled'] ?? false;
                _birthdayPixDiscountPercent =
                    (config['birthday_pix_discount_percent'] ?? 10.0)
                        .toDouble();
                _vipExtraDays =
                    (config['vip_extra_booking_days'] ?? 0).toDouble();
                _restrictProblematicClients =
                    config['restrict_problematic_clients'] ?? false;

                // Automação de Tags
                _vipMinVisits = (config['vip_min_visits'] ?? 15).toDouble();
                _vipAvgInterval = (config['vip_avg_interval'] ?? 30).toDouble();
                _sumidoMaxDays = (config['sumido_max_days'] ?? 45).toDouble();
              });
            }
          }
        }
      }
    } catch (e) {
      debugPrint("Erro ao carregar: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _saveSettings() async {
    if (shopId == null) {
      _showSnack("Erro: ID da loja não encontrado.", isError: true);
      return;
    }

    setState(() => _isLoading = true);

    try {
      int finalCancelHours = _cancelUnit == 'hours'
          ? _cancelValue.round()
          : (_cancelValue.round() * 24);

      // Payment validation for Free Plan
      final canUseOnline = _currentFeatures.mercadoPagoIntegration;

      if (!canUseOnline) {
        // Free plan: force cash only
        _cartaoOnline = false;
        _debitoPresencial = false;
        _requireDeposit = false;
        _pagarPessoalmente = true;
        _creditTaxPercent = 0.0; // ? [FIX] não salvar taxa para plano free
      } else {
        // Paid Plan Validation: Ensure at least one payment method is enabled
        if (!(_cartaoOnline || _debitoPresencial || _pagarPessoalmente)) {
          if (mounted) {
            _showSnack(
                "É necessário ter pelo menos um método de pagamento ativo para que seus clientes possam finalizar agendamentos.",
                isError: true);
          }
          setState(() => _isLoading = false);
          return;
        }
      }

      await sb.Supabase.instance.client.from('shops').update({
        'config': {
          'permitir_multiplos': _allowMultiple,
          'permitir_reagendamento': _allowReschedule,
          'cliente_escolhe_prof': _clientChoosesProfessional,
          'agendamento_online_ativo': _onlineBookingActive,
          'auto_block_holidays': _autoBlockHolidays,
          'intervalo_agenda_min': _appointmentIntervalMinutes,
          'evitar_buracos_agenda': _preventGaps,
          'janela_agendamento_dias':
              _bookingWindowDays.round(), // Salva o novo campo
          'limite_minimo_agendamento_horas':
              _minAdvanceHours.round(), // â ° Salva limite mínimo
          'tempo_cancelamento_horas': finalCancelHours,
          'cartao_online': _cartaoOnline,
          'debito_presencial': _debitoPresencial,
          'pagar_pessoalmente': _pagarPessoalmente,
          // Legacy fallbacks for older app versions
          'pagamento_cartao': _cartaoOnline,
          'pagamento_dinheiro': _pagarPessoalmente,
          'pagamento_pix': _debitoPresencial,
          'exigir_sinal': _requireDeposit,
          'percentual_sinal': _depositPercent.round(),
          // única taxa aplicada ao crédito (aplicada quando cliente escolher cartão)
          'tax_percent': _creditTaxPercent,
          'notificar_cliente_agendamento': _notifyClientAppointment,
          'notificar_dias_antes': _notifyDaysBefore,
          'trusted_only_pay_in_person': _trustedOnlyPayInPerson,
          'birthday_pix_discount_enabled': _birthdayPixDiscountEnabled,
          'birthday_pix_discount_percent': _birthdayPixDiscountPercent,
          'vip_extra_booking_days': _vipExtraDays.round(),
          'restrict_problematic_clients': _restrictProblematicClients,
          'vip_min_visits': _vipMinVisits.round(),
          'vip_avg_interval': _vipAvgInterval.round(),
          'sumido_max_days': _sumidoMaxDays.round(),
          'atualizado_em': DateTime.now().toIso8601String(),
        },
        'notification_settings': {
          'send_reminders': _notifyClientAppointment,
          'default_reminder_days': _notifyDaysBefore,
          'email_template': 'default',
        }
      }).eq('id', shopId!);

      if (mounted) {
        // Invalida o cache de configuração da loja
        ShopDataCacheService().invalidate(shopId!, 'config');
        
        _showSnack("Configurações salvas com sucesso!", isError: false);
      }
    } catch (e) {
      if (mounted) _showSnack("Erro ao salvar: $e", isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showSnack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? Colors.red : Colors.green,
      behavior: SnackBarBehavior.floating,
    ));
  }

  /// Ativado/desativado o agendamento online.
  /// Quando desativado, todas as configurações de agendamento são zeradas
  /// automaticamente e salvas no Firestore imediatamente.
  void _setOnlineBooking(bool value) {
    setState(() {
      _onlineBookingActive = value;
      if (!value) {
        // Desativar todas as configurações de agendamento
        _allowMultiple = false;
        _allowReschedule = false;
        _clientChoosesProfessional = false;
        _preventGaps = false;
        _bookingWindowDays = 30.0;
        _minAdvanceHours = 7.0;
      }
    });

    if (!value) {
      _showSnack(
        'Agendamento online desativado. Todas as configurações de agenda foram desligadas.',
        isError: false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
          body: Center(
              child:
                  CircularProgressIndicator(color: AppColors.primaryPurple)));
    }

    return StreamBuilder<PlanFeatures>(
      stream: _featuresStream!,
      builder: (context, snapshot) {
        if (snapshot.hasData) {
          _currentFeatures = snapshot.data!;
        }

        return Scaffold(
          backgroundColor: const Color(0xFFF2F4F8),
          body: LayoutBuilder(
            builder: (context, constraints) {
              bool isMobile = constraints.maxWidth < 900;

              if (isMobile) {
                return Column(
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            _buildMainSettingsForm(),
                            const SizedBox(height: 20),
                            _buildHelpPanel(),
                          ],
                        ),
                      ),
                    ),
                    _buildSaveArea(),
                  ],
                );
              } else {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 3,
                      child: Column(
                        children: [
                          Expanded(
                            child: SingleChildScrollView(
                              padding: const EdgeInsets.all(30),
                              child: _buildMainSettingsForm(),
                            ),
                          ),
                          _buildSaveArea(),
                        ],
                      ),
                    ),
                    VerticalDivider(width: 1, color: Colors.grey[300]),
                    Expanded(
                      flex: 2,
                      child: _buildHelpPanel(isDesktop: true),
                    ),
                  ],
                );
              }
            },
          ),
        );
      },
    );
  }

  // --- COMPONENTES DA UI ---

  Widget _buildMainSettingsForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ----------- Toggle principal — SEMPRE ativo -----------
              _buildSettingCard([
                _buildSwitchTile(
                    "Agendamento Online Ativo",
                    "Se desativado, os clientes não poderão agendar sozinhos e serão instruídos a te chamar no WhatsApp.",
                    _onlineBookingActive,
                    (v) => _setOnlineBooking(v)),
                const Divider(height: 1),
                _buildSwitchTile(
                    "Bloquear Feriados Automaticamente",
                    "Feriados nacionais serão bloqueados sem precisar aprovar um por um.",
                    _autoBlockHolidays,
                    (v) => setState(() => _autoBlockHolidays = v)),
              ]),

              const SizedBox(height: 24),

              // --- Tudo abaixo fica desabilitado quando booking for inativo ---
              AbsorbPointer(
                absorbing: !_onlineBookingActive,
                child: AnimatedOpacity(
                  opacity: _onlineBookingActive ? 1.0 : 0.3,
                  duration: const Duration(milliseconds: 300),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // --- REGRAS DE AGENDAMENTO ---
                      _buildSectionHeader(
                          "Regras de Agendamento", Icons.settings_suggest),
                      _buildSettingCard([
                        // INTERVALO
                        Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text("Intervalo da Agenda",
                                        style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.bold)),
                                    _subtitled(Icons.schedule,
                                        "Espaço entre horários (Ex: 08:00, 09:00)"),
                                  ],
                                ),
                              ),
                              Container(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 12),
                                decoration: BoxDecoration(
                                    color: AppColors.primaryPurple
                                        .withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(8)),
                                child: DropdownButtonHideUnderline(
                                  child: DropdownButton<int>(
                                    value: _appointmentIntervalMinutes,
                                    icon: const Icon(Icons.access_time,
                                        size: 18,
                                        color: AppColors.primaryPurple),
                                    style: const TextStyle(
                                        color: AppColors.primaryPurple,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13),
                                    items: const [
                                      DropdownMenuItem(
                                          value: 15, child: Text("15 min")),
                                      DropdownMenuItem(
                                          value: 30, child: Text("30 min")),
                                      DropdownMenuItem(
                                          value: 45, child: Text("45 min")),
                                      DropdownMenuItem(
                                          value: 60, child: Text("1 hora")),
                                      DropdownMenuItem(
                                          value: 90, child: Text("1h 30min")),
                                      DropdownMenuItem(
                                          value: 120, child: Text("2 horas")),
                                    ],
                                    onChanged: (val) {
                                      if (val != null) {
                                        setState(() =>
                                            _appointmentIntervalMinutes = val);
                                      }
                                    },
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Divider(height: 1),

                        // EVITAR BURACOS
                        Opacity(
                          opacity: _currentFeatures.agendaOptimization ? 1.0 : 0.6,
                          child: SwitchListTile(
                            value: _currentFeatures.agendaOptimization ? _preventGaps : false,
                            onChanged: _currentFeatures.agendaOptimization
                                ? (v) => setState(() => _preventGaps = v)
                                : (v) => _showUpgradeDialog('Otimização de Agenda', PlanKey.starter),
                            activeThumbColor: AppColors.primaryPurple,
                            title: Row(
                              children: [
                                const Flexible(
                                  child: Text("Otimizar Agenda",
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.bold)),
                                ),
                                if (!_currentFeatures.agendaOptimization) _buildPremiumBadge(),
                              ],
                            ),
                            subtitle: const Text(
                                "Força agendamentos em sequência, impedindo horários vagos isolados.",
                                style: TextStyle(fontSize: 12)),
                          ),
                        ),
                        const Divider(height: 1),

                        // JANELA DE AGENDAMENTO
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text("Liberar Agenda por (Dias)",
                                      style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.bold)),
                                  Text("${_bookingWindowDays.round()} dias",
                                      style: const TextStyle(
                                          color: AppColors.primaryPurple,
                                          fontWeight: FontWeight.bold)),
                                ],
                              ),
                              const SizedBox(height: 4),
                              _subtitled(Icons.calendar_view_month,
                                  "Define quantos dias à frente o cliente pode ver no calendário."),
                              Slider(
                                value: _bookingWindowDays,
                                min: 7,
                                max: 90,
                                divisions: 83,
                                activeColor: AppColors.primaryPurple,
                                onChanged: (v) =>
                                    setState(() => _bookingWindowDays = v),
                              ),
                            ],
                          ),
                        ),
                        const Divider(height: 1),

                        // ANTECEDÊNCIA MÍNIMA
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text("Antecedência Mínima (Horas)",
                                      style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.bold)),
                                  Text("${_minAdvanceHours.round()}h antes",
                                      style: const TextStyle(
                                          color: AppColors.primaryPurple,
                                          fontWeight: FontWeight.bold)),
                                ],
                              ),
                              const SizedBox(height: 4),
                              _subtitled(Icons.access_time,
                                  "Tempo mínimo de antecedência para o cliente agendar. Ex: 12h = não pode agendar para hoje à tarde."),
                              Slider(
                                value: _minAdvanceHours,
                                min: 1,
                                max: 72,
                                divisions: 71,
                                activeColor: AppColors.primaryPurple,
                                onChanged: (v) =>
                                    setState(() => _minAdvanceHours = v),
                              ),
                            ],
                          ),
                        ),
                        const Divider(height: 1),

                        // MÚLTIPLOS AGENDAMENTOS (Sempre disponivel)
                        _buildSwitchTile(
                          "Múltiplos Agendamentos",
                          "Cliente reserva vários serviços/horários",
                          _allowMultiple,
                          (v) => setState(() => _allowMultiple = v),
                        ),
                        _buildSwitchTile(
                            "Reagendamento Livre",
                            "Permitir troca de horário pelo app",
                            _allowReschedule,
                            (v) => setState(() => _allowReschedule = v)),

                        // ESCOLHA DE PROFISSIONAL
                        Opacity(
                          opacity: _currentFeatures.clientChoosesProfessional ? 1.0 : 0.6,
                          child: _buildSwitchTile(
                            "Escolha de Profissional",
                            "Exibir lista de equipe no agendamento",
                            _currentFeatures.clientChoosesProfessional ? _clientChoosesProfessional : false, // Fixed logical bug from old code (true -> false to enforce off)
                            _currentFeatures.clientChoosesProfessional
                                ? (v) => setState(
                                    () => _clientChoosesProfessional = v)
                                : (v) => _showUpgradeDialog('Escolha de Profissional', PlanKey.starter),
                            trailing: !_currentFeatures.clientChoosesProfessional ? _buildPremiumBadge() : null,
                          ),
                        ),
                      ]),

                      // --- POLÍTICA DE CANCELAMENTO ---
                      const SizedBox(height: 24),
                      _buildSectionHeader(
                          "Política de Cancelamento", Icons.timer_off),
                      _buildCancelCard(),

                      // --- FINANCEIRO E SINAL ---
                      const SizedBox(height: 24),
                      _buildSectionHeader(
                          "Financeiro e Sinal", Icons.payments_outlined),
                      _buildFinanceCard(),

                      // --- PAGAMENTOS ONLINE ---
                      const SizedBox(height: 12),
                      _buildSectionHeader(
                          "Pagamentos Online", Icons.account_balance_wallet),
                      _buildPaymentIntegrationCard(),


                      // --- CONFIGURAÇÕES VIP E CONFIANÇA ---
                      const SizedBox(height: 24),
                      _buildSectionHeader(
                          "Clientes VIP e de Confiança", Icons.stars_outlined),
                      _buildVIPSettingsCard(),

                      // --- NOTIFICAÇÕES ---
                      const SizedBox(height: 24),
                      _buildSectionHeader(
                          "Notificações", Icons.notifications_active),
                      _buildNotificationCard(),

                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),

              // --- INTEGRAÇÕES — sempre ativa ---
              _buildSectionHeader("Integrações", Icons.link),
              _buildIntegrationsCard(),

              const SizedBox(height: 24),
            ],
          );
  }

  Widget _buildVIPSettingsCard() {
    final isPremium = _currentFeatures.clientClassification;
    return _buildSettingCard([
      Opacity(
        opacity: isPremium ? 1.0 : 0.6,
        child: Column(
          children: [
                // Proteção de Pagamento Pessoalmente
                _buildSwitchTile(
                  "Restringir Pagamento Pessoalmente",
                  "Somente VIPs podem escolher pagar na loja",
                  isPremium ? _trustedOnlyPayInPerson : false,
                  isPremium
                      ? (v) => setState(() {
                            _trustedOnlyPayInPerson = v;
                            if (v) {
                              // Caso a loja ative a opção de pagar pessoalmente somente para vips, 
                              // entao a opção de pagar pessoalmente (geral) deve ser desativada
                              _pagarPessoalmente = false;
                            }
                          })
                      : (v) => _showUpgradeDialog('Restringir Pagamentos a VIPs', PlanKey.plus),
                  trailing: !isPremium ? _buildPremiumBadge() : null,
                ),
                const Divider(height: 1),

                // Janela de Agendamento Extra para VIP
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              const Text("Dias Extras para VIPs",
                                  style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold)),
                              if (!isPremium) _buildPremiumBadge(),
                            ],
                          ),
                          Text("+${_vipExtraDays.round()} dias",
                              style: const TextStyle(
                                  color: AppColors.primaryPurple,
                                  fontWeight: FontWeight.bold)),
                        ],
                      ),
                      const SizedBox(height: 4),
                      _subtitled(Icons.star_outline,
                          "Permite que clientes VIP vejam a agenda com X dias de antecedência extra."),
                      Slider(
                        value: isPremium ? _vipExtraDays : 0.0,
                        min: 0,
                        max: 60,
                        divisions: 60,
                        activeColor: AppColors.primaryPurple,
                        onChanged: isPremium
                            ? (v) => setState(() => _vipExtraDays = v)
                            : (v) => _showUpgradeDialog('Dias Extras para VIP', PlanKey.plus),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),

                // Restrição de Clientes Problemáticos
                _buildSwitchTile(
                    "Restringir Clientes Problemáticos",
                    "Impede que clientes marcados como 'problemáticos' agendem online",
                    isPremium ? _restrictProblematicClients : false,
                    isPremium 
                      ? (v) => setState(() => _restrictProblematicClients = v)
                      : (v) => _showUpgradeDialog('Bloqueio de Clientes Problemáticos', PlanKey.plus),
                    trailing: !isPremium ? _buildPremiumBadge() : null,
                ),

                const Divider(height: 1),

                // Configurações de Automação VIP
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildAutomationHeader(
                          "Automação VIP", Icons.auto_awesome),
                      const SizedBox(height: 16),
                      _buildSliderSetting(
                        label: "Mínimo de Visitas",
                        value: _vipMinVisits,
                        min: 3,
                        max: 50,
                        suffix: "visitas",
                        onChanged: (v) => setState(() => _vipMinVisits = v),
                      ),
                      const SizedBox(height: 12),
                      _buildSliderSetting(
                        label: "Intervalo Médio Máximo",
                        value: _vipAvgInterval,
                        min: 7,
                        max: 90,
                        suffix: "dias",
                        onChanged: (v) => setState(() => _vipAvgInterval = v),
                        subtitle: "Média de dias entre um agendamento e outro",
                      ),
                    ],
                  ),
                ),

                const Divider(height: 1),

                // Configurações de Automação Sumido
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildAutomationHeader(
                          "Automação Sumido", Icons.timer_outlined),
                      const SizedBox(height: 16),
                      _buildSliderSetting(
                        label: "Inatividade Máxima",
                        value: _sumidoMaxDays,
                        min: 15,
                        max: 180,
                        suffix: "dias",
                        onChanged: (v) => setState(() => _sumidoMaxDays = v),
                        subtitle:
                            "Dias sem agendar para ser considerado sumido",
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ]);
  }

  Widget _buildAutomationHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppColors.primaryPurple),
        const SizedBox(width: 8),
        Text(title,
            style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: AppColors.primaryPurple)),
      ],
    );
  }

  Widget _buildSliderSetting({
    required String label,
    required double value,
    required double min,
    required double max,
    required String suffix,
    required ValueChanged<double> onChanged,
    String? subtitle,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label,
                style:
                    const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            Text("${value.round()} $suffix",
                style: const TextStyle(
                    color: AppColors.primaryPurple,
                    fontWeight: FontWeight.bold)),
          ],
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 4),
          Text(subtitle,
              style: const TextStyle(fontSize: 12, color: Colors.grey)),
        ],
        Slider(
          value: value,
          min: min,
          max: max,
          divisions: (max - min).toInt(),
          activeColor: AppColors.primaryPurple,
          onChanged: onChanged,
        ),
      ],
    );
  }

  Widget _buildPremiumBadge() {
    return Container(
      margin: const EdgeInsets.only(left: 8),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.grey[200],
        borderRadius: BorderRadius.circular(4),
      ),
      child: const Text("Upgrade",
          style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: Colors.black54)),
    );
  }

  void _showUpgradeDialog(String featureName, PlanKey requiredPlan) {
    UpgradeModal.show(context, featureName: featureName, requiredPlan: requiredPlan.name.toUpperCase());
  }

  Widget _buildHelpPanel({bool isDesktop = false}) {
    return Container(
      color: isDesktop ? Colors.white : Colors.transparent,
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Central de Ajuda",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 20),
          _buildHelpTopic("Liberar Agenda",
              "Se você definir '30 dias', o cliente hoje só consegue ver vagas até daqui a um mês. Isso evita agendamentos muito distantes."),
          _buildHelpTopic("Otimizar Agenda",
              "Essencial para produtividade! Se você abre às 08:00, o sistema sugere 08:00. Se o cliente tentar 09:00 (deixando o horário das 08h vago), o sistema bloqueia."),
          _buildHelpTopic("Sinal",
              "Cobrar 30% ou 50% antecipado reduz drasticamente as faltas."),
          if (isDesktop) const Spacer(),
          Container(
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
                color: AppColors.primaryPurple.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(12)),
            child: const Row(
              children: [
                Icon(Icons.auto_awesome,
                    color: AppColors.primaryPurple, size: 20),
                SizedBox(width: 10),
                Expanded(
                    child: Text(
                        "As alterações refletem na hora para seus clientes.",
                        style: TextStyle(
                            fontSize: 12, color: AppColors.primaryPurple))),
              ],
            ),
          )
        ],
      ),
    );
  }

  // --- WIDGETS MENORES ---

  Widget _buildSectionHeader(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, left: 4),
      child: Row(children: [
        Icon(icon, size: 20, color: AppColors.primaryPurple),
        const SizedBox(width: 8),
        Text(title,
            style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: Colors.black87))
      ]),
    );
  }

  // Pequeno helper para subtítulos com ícone ilustrativo
  Widget _subtitled(IconData icon, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: Colors.grey[600]),
        const SizedBox(width: 8),
        Expanded(
            child: Text(text,
                style: const TextStyle(fontSize: 12, color: Colors.grey),
                softWrap: true)),
      ],
    );
  }

  Widget _buildSettingCard(List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.03), blurRadius: 10)
          ]),
      child: Column(children: children),
    );
  }

  Widget _buildSwitchTile(
      String title, String subtitle, bool value, Function(bool) onChanged,
      {Widget? trailing}) {
    return SwitchListTile(
      value: value,
      onChanged: onChanged,
      activeThumbColor: AppColors.primaryPurple,
      title: Row(
        children: [
          Flexible(
            child: Text(title,
                style:
                    const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
          ),
          if (trailing != null) trailing,
        ],
      ),
      subtitle: Text(subtitle,
          style: const TextStyle(fontSize: 12), overflow: TextOverflow.visible),
    );
  }

  Widget _buildCancelCard() {
    return _buildSettingCard([
      Padding(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          Row(children: [
            _unitChip("Horas", 'hours'),
            const SizedBox(width: 8),
            _unitChip("Dias", 'days'),
            const Spacer(),
            Text(
                "${_cancelValue.round()} ${_cancelUnit == 'hours' ? 'Hrs' : 'Dias'}",
                style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppColors.primaryPurple)),
          ]),
          Slider(
              value: _cancelValue,
              min: 1,
              max: _cancelUnit == 'hours' ? 24 : 7,
              divisions: _cancelUnit == 'hours' ? 23 : 6,
              activeColor: AppColors.primaryPurple,
              onChanged: (v) => setState(() => _cancelValue = v)),
        ]),
      )
    ]);
  }

  Widget _unitChip(String label, String value) {
    bool isS = _cancelUnit == value;
    return ChoiceChip(
        label: Text(label,
            style: TextStyle(
                fontSize: 12, color: isS ? Colors.white : Colors.black)),
        selected: isS,
        selectedColor: AppColors.primaryPurple,
        onSelected: (s) => setState(() {
              if (s) _cancelUnit = value;
              _cancelValue = value == 'hours' ? 2.0 : 1.0;
            }));
  }

  Widget _buildFinanceCard() {
    final allowPayments = _currentFeatures.mercadoPagoIntegration;
    final allowDeposit = _currentFeatures.requireDeposit;
    final allowCreditCard = _currentFeatures.payments.contains('credit_card');
    final allowPix = _currentFeatures.payments.contains('pix');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
            _buildSettingCard([
              // SINAL / ENTRADA
              SwitchListTile(
                title: const Text("Exigir Sinal (Entrada)",
                    style:
                        TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                value: allowDeposit ? _requireDeposit : false,
                activeThumbColor: AppColors.primaryPurple,
                onChanged: allowDeposit
                    ? (v) => setState(() => _requireDeposit = v)
                    : (v) => _showUpgradeDialog('Exigir Sinal', PlanKey.starter),
                subtitle: !allowDeposit
                    ? Row(
                        children: [
                          _buildPremiumBadge(),
                        ],
                      )
                    : null,
              ),
              if (_requireDeposit)
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(children: [
                    const Text("Percentual:", style: TextStyle(fontSize: 13)),
                    Expanded(
                      child: Slider(
                        value: _depositPercent,
                        min: 10,
                        max: 100,
                        divisions: 18,
                        activeColor: AppColors.primaryPurple,
                        onChanged: (v) => setState(() => _depositPercent = v),
                      ),
                    ),
                    Text("${_depositPercent.round()}%",
                        style: const TextStyle(fontWeight: FontWeight.bold))
                  ]),
                ),

              const Divider(height: 1),
              // MÉTODOS ACEITOS
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text("Métodos de Pagamento Aceitos",
                          style: TextStyle(
                              fontSize: 14, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),

                      // Cartão Online
                      Opacity(
                        opacity: allowCreditCard ? 1.0 : 0.6,
                        child: _buildSwitchTile(
                          "Cartão de Crédito/Débito (Online)",
                          "Necessário plugar Mercado Pago na aba Integrações",
                          allowCreditCard ? _cartaoOnline : false,
                          allowCreditCard
                              ? (v) {
                                  int active = (v ? 1 : 0) +
                                      (_debitoPresencial ? 1 : 0) +
                                      (_pagarPessoalmente ? 1 : 0);
                                  if (!v && active == 0) {
                                    _showSnack(
                                        "Você precisa ter ao menos um método de pagamento ativo.",
                                        isError: true);
                                    return;
                                  }
                                  setState(() => _cartaoOnline = v);
                                }
                              : (v) => _showUpgradeDialog('Pagamento Via Cartão de Crédito', PlanKey.plus),
                          trailing: !allowCreditCard ? _buildPremiumBadge() : null,
                        ),
                      ),

                      // Pix Online
                      Opacity(
                        opacity: allowPix ? 1.0 : 0.6,
                        child: _buildSwitchTile(
                          "Pix",
                          "Pagamento instantâneo via QR Code (requer Mercado Pago)",
                          allowPix ? _debitoPresencial : false,
                          allowPix
                              ? (v) {
                                  int active = (_cartaoOnline ? 1 : 0) +
                                      (v ? 1 : 0) +
                                      (_pagarPessoalmente ? 1 : 0);
                                  if (!v && active == 0) {
                                    _showSnack(
                                        "Você precisa ter ao menos um método de pagamento ativo.",
                                        isError: true);
                                    return;
                                  }
                                  setState(() => _debitoPresencial = v);
                                }
                              : (v) => _showUpgradeDialog('Pagamento Via Pix Automático', PlanKey.starter),
                          trailing: !allowPix ? _buildPremiumBadge() : null,
                        ),
                      ),

                      // Pagar Pessoalmente (Espécie / Pix Loja)
                      Opacity(
                        opacity: _trustedOnlyPayInPerson ? 0.5 : 1.0,
                        child: AbsorbPointer(
                          absorbing: _trustedOnlyPayInPerson,
                          child: _buildSwitchTile(
                            "Pagar Pessoalmente",
                            _trustedOnlyPayInPerson 
                              ? "Opção desativada pois a restrição para VIPs está ligada abaixo." 
                              : "Dinheiro ou PIX direto na loja",
                            !allowPayments ? true : _pagarPessoalmente,
                            !allowPayments
                                ? (v) {
                                    if (!v) {
                                      _showSnack(
                                          "Plano Gratuito permite apenas pagamento presencial.",
                                          isError: true);
                                    }
                                  }
                                : (v) {
                                    int active = (_cartaoOnline ? 1 : 0) +
                                        (_debitoPresencial ? 1 : 0) +
                                        (v ? 1 : 0);
                                    if (!v && active == 0) {
                                      _showSnack(
                                          "Você precisa ter ao menos um método de pagamento ativo.",
                                          isError: true);
                                      return;
                                    }
                                    setState(() {
                                      _pagarPessoalmente = v;
                                      // Se desativar o pagamento pessoalmente, removemos a restrição VIP (pois não há mais o que restringir)
                                      if (!v) {
                                        _trustedOnlyPayInPerson = false;
                                      }
                                    });
                                  },
                          ),
                        ),
                      ),

                      const Divider(height: 1),
                      const SizedBox(height: 12),

                      // Desconto de Aniversário (PIX)
                      Opacity(
                        opacity: _currentFeatures.birthdayDiscount ? 1.0 : 0.6,
                        child: Column(
                          children: [
                            _buildSwitchTile(
                              "Desconto de Aniversário (PIX)",
                              "Oferecer automático no mês do aniversário",
                              _currentFeatures.birthdayDiscount ? _birthdayPixDiscountEnabled : false,
                              _currentFeatures.birthdayDiscount
                                  ? (v) => setState(
                                      () => _birthdayPixDiscountEnabled = v)
                                  : (v) => _showUpgradeDialog('Desconto de Aniversário', PlanKey.starter),
                              trailing:
                                  !_currentFeatures.birthdayDiscount ? _buildPremiumBadge() : null,
                            ),
                            if (_birthdayPixDiscountEnabled && _currentFeatures.birthdayDiscount)
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 8),
                                child: Row(children: [
                                  const Text("Desconto:",
                                      style: TextStyle(fontSize: 13)),
                                  Expanded(
                                    child: Slider(
                                      value: _birthdayPixDiscountPercent,
                                      min: 1,
                                      max: 50,
                                      divisions: 49,
                                      activeColor: AppColors.primaryPurple,
                                      onChanged: (v) => setState(() =>
                                          _birthdayPixDiscountPercent = v),
                                    ),
                                  ),
                                  Text(
                                      "${_birthdayPixDiscountPercent.round()}%",
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold))
                                ]),
                              ),
                          ],
                        ),
                      ),
                    ]),
              ),

              const Divider(height: 1),
              // CONFIGURAÇÕES DE CARTÃO — bloqueado para plano free
              PlanGateWidget(
                requiredPlan: SubscriptionPlan.start,
                featureLabel: 'Taxa de Cartão e Parcelamento',
                onUpgradeTap: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const SubscriptionPlansPage()),
                  );
                  if (mounted) setState(() {});
                },
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text("Configurações - Cartão de Crédito",
                            style: TextStyle(
                                fontSize: 14, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        _subtitled(Icons.info_outline,
                            "Defina se a taxa será repassada e o percentual único a aplicar sobre o valor."),
                        const SizedBox(height: 12),
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      const Text("Taxa aplicada ao crédito (%)",
                                          style: TextStyle(fontSize: 13)),
                                      Text(
                                          "${_creditTaxPercent.toStringAsFixed(1)}%",
                                          style: const TextStyle(
                                              fontWeight: FontWeight.bold)),
                                    ]),
                                Slider(
                                  value: _creditTaxPercent,
                                  min: 0,
                                  max: 20,
                                  divisions: 200,
                                  label:
                                      "${_creditTaxPercent.toStringAsFixed(1)}%",
                                  onChanged: (v) =>
                                      setState(() => _creditTaxPercent = v),
                                  activeColor: AppColors.primaryPurple,
                                ),
                              ]),
                        ),
                      ]),
                ),
              ),
            ]),
          ],
        );
  }

  Widget _buildNotificationCard() {
    return _buildSettingCard([
      // Notificação para a LOJA: novo agendamento
      _buildSwitchTile(
        'Avisar-me sobre novos agendamentos',
        'Receba uma notificação push quando um cliente agendar',
        _notifyClientAppointment,
        (v) => setState(() => _notifyClientAppointment = v),
      ),
      const Divider(height: 1),

      // Notificação para o CLIENTE: lembrete
      Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Lembrete automático para clientes',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            const Text(
              'Quantas horas antes do agendamento o cliente recebe o lembrete?',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [1, 2, 6, 12, 24, 48].map((h) {
                // Map existing _notifyDaysBefore (days) ? hours
                final currentH = _notifyDaysBefore * 24;
                final isSelected = currentH == h;
                return ChoiceChip(
                  label: Text(
                    h < 24 ? '${h}h' : '${h ~/ 24}d',
                    style: TextStyle(
                      fontSize: 12,
                      color: isSelected ? Colors.white : Colors.black87,
                    ),
                  ),
                  selected: isSelected,
                  selectedColor: AppColors.primaryPurple,
                  onSelected: (s) {
                    if (s) {
                      setState(() {
                        _notifyDaysBefore = h ~/ 24 == 0 ? 1 : h ~/ 24;
                      });
                    }
                  },
                );
              }).toList(),
            ),
          ],
        ),
      ),
    ]);
  }

  Widget _buildIntegrationsCard() {
    return _buildSettingCard([
      // Google Meu Negócio
      ListTile(
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.blue.shade50,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(Icons.star, color: Colors.orange.shade700, size: 24),
        ),
        title: const Text(
          "Google Meu Negócio",
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
        ),
        subtitle: const Text(
          "Exiba suas avaliações do Google na página da sua loja",
          style: TextStyle(fontSize: 12),
        ),
        trailing: ElevatedButton.icon(
          onPressed: () async {
            if (shopId != null) {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => LinkGoogleBusinessPage(shopId: shopId!),
                ),
              );
              // Recarrega configurações ao voltar para atualizar o status do botão
              _loadSettings();
            }
          },
          icon: Icon(_googleBusiness != null ? Icons.link_off : Icons.link,
              size: 18),
          label: Text(_googleBusiness != null ? "DESCONECTAR" : "CONECTAR"),
          style: ElevatedButton.styleFrom(
            backgroundColor: _googleBusiness != null
                ? Colors.red[600]
                : AppColors.primaryPurple,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          ),
        ),
      ),

      const Divider(height: 1),

      // ðŸ†• Google Calendar Backup
      ListTile(
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.green.shade50,
            borderRadius: BorderRadius.circular(10),
          ),
          child:
              Icon(Icons.cloud_upload, color: Colors.green.shade700, size: 24),
        ),
        title: const Text(
          "Backup Google Calendar",
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
        ),
        subtitle: const Text(
          "Salve automaticamente todos os agendamentos no seu Google Calendar",
          style: TextStyle(fontSize: 12),
        ),
        trailing: ElevatedButton.icon(
          onPressed: () {
            if (shopId != null) {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => CalendarBackupPage(
                    isOwner: true,
                    shopId: shopId,
                  ),
                ),
              );
            }
          },
          icon: const Icon(Icons.sync, size: 18),
          label: const Text("CONFIGURAR"),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.green,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          ),
        ),
      ),

      const Divider(height: 1),

    ]);
  }

  Widget _buildPaymentIntegrationCard() {
    final canConnect = _currentFeatures.mercadoPagoIntegration;
    return _buildSettingCard([
      PlanGateWidget(
        requiredPlan: SubscriptionPlan.start,
        featureLabel: 'Conexão com Mercado Pago',
        onUpgradeTap: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const SubscriptionPlansPage()),
          );
          if (mounted) setState(() {});
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text("Configurações de Pagamento",
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              const Text(
                  "Centralize aqui seu Mercado Pago e métodos aceitos.",
                  style: TextStyle(fontSize: 12, color: Colors.grey)),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.account_balance_wallet, size: 20),
                  label: const Text("CONECTAR MERCADO PAGO",
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryPurple,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: canConnect
                      ? () {
                          if (!mounted) return;
                          Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => PaymentSettingsPage(
                                      onClose: () => Navigator.pop(context))));
                        }
                      : null,
                ),
              ),
            ],
          ),
        ),
      ),
    ]);
  }


  Widget _buildSaveArea() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Colors.grey[200]!)),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                offset: const Offset(0, -2),
                blurRadius: 10)
          ]),
      child: SafeArea(
        top: false,
        child: SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryPurple,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12))),
            onPressed: _saveSettings,
            child: const Text("SALVAR ALTERAÇÕES",
                style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16)),
          ),
        ),
      ),
    );
  }

  Widget _buildHelpTopic(String title, String desc) {
    return Padding(
        padding: const EdgeInsets.only(bottom: 20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title,
              style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: AppColors.primaryPurple)),
          const SizedBox(height: 4),
          Text(desc,
              style: const TextStyle(
                  fontSize: 12, color: Colors.blueGrey, height: 1.4))
        ]));
  }
}
