import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:google_sign_in/google_sign_in.dart';
import '../../core/theme/app_colors.dart';
import '../../core/services/session_service.dart';
import '../../core/services/notification_service.dart';
import 'link_google_business_page.dart';
import '../backup/calendar_backup_page.dart';
import 'payment_settings_page.dart';
import 'subscription_service.dart';
import 'subscription_plans_page.dart';
import '../../core/widgets/plan_gate_widget.dart';

class BusinessSettingsPage extends StatefulWidget {
  const BusinessSettingsPage({super.key});

  @override
  State<BusinessSettingsPage> createState() => _BusinessSettingsPageState();
}

class _BusinessSettingsPageState extends State<BusinessSettingsPage> {
  bool _isLoading = true;
  String? shopId;

  // --- ESTADOS DAS CONFIGURAÇÕES ---
  bool _allowMultiple = false;
  bool _allowReschedule = true;
  bool _clientChoosesProfessional = true;
  bool _onlineBookingActive = true;

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
  bool _acceptPix = true;
  bool _acceptCard = true;
  bool _acceptCash = true;
  bool _requireDeposit = false;
  double _depositPercent = 30.0;
  // Pagamento com cartão - única taxa configurável pelo lojista (aplicada no crédito)
  double _creditTaxPercent = 0.0; // 0..20%

  // Notificações
  bool _notifyClientAppointment = true;
  int _notifyDaysBefore = 1; // Padrão: 1 dia antes

  // FASE 4 — Parcelamento no cartão de crédito
  bool _acceptInstallments = true; // Aceitar parcelamento
  int _maxInstallments = 6; // Máximo de parcelas (2-12)

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    try {
      String? sId = await SessionService.getShopId();

      if (sId == null || sId.isEmpty) {
        final user = FirebaseAuth.instance.currentUser;
        if (user != null) {
          final userDoc = await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .get();
          if (userDoc.exists) sId = userDoc.data()?['shopId'];
        }
      }

      shopId = sId;

      if (shopId != null) {
        final doc = await FirebaseFirestore.instance
            .collection('shops')
            .doc(shopId)
            .get();
        if (doc.exists && doc.data() != null) {
          final data = doc.data()!;
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

                _acceptPix = config['pagamento_pix'] ?? true;
                _acceptCard = config['pagamento_cartao'] ?? true;
                _acceptCash = config['pagamento_dinheiro'] ?? true;
                _requireDeposit = config['exigir_sinal'] ?? false;
                _depositPercent = (config['percentual_sinal'] ?? 30).toDouble();
                // cartão: ler única taxa de crédito (0..20%)
                _creditTaxPercent = (config['tax_percent'] ??
                        config['porcentagem_a_vista'] ??
                        0)
                    .toDouble();
                if (_creditTaxPercent < 0) _creditTaxPercent = 0;
                if (_creditTaxPercent > 20) _creditTaxPercent = 20;

                // Notificações
                _notifyClientAppointment =
                    config['notificar_cliente_agendamento'] ?? true;
                _notifyDaysBefore = config['notificar_dias_antes'] ?? 1;

                // FASE 4 — Parcelamento
                _acceptInstallments = config['aceitar_parcelas'] ?? true;
                _maxInstallments = (config['max_parcelas'] ?? 6).clamp(2, 12);
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
      final canUseOnline = await SubscriptionService.canUseOnlinePayment();

      if (!canUseOnline) {
        // Free plan: force cash only
        _acceptPix = false;
        _acceptCard = false;
        _requireDeposit = false;
        _acceptCash = true;
        _creditTaxPercent = 0.0; // ← [FIX] não salvar taxa para plano free
        _acceptInstallments =
            false; // ← [FIX] não salvar parcelamento para plano free
      } else {
        // Paid Plan Validation: Ensure at least one payment method is enabled (pix, card or cash)
        if (!(_acceptPix || _acceptCard || _acceptCash)) {
          if (mounted) {
            _showSnack(
                "Ao menos uma forma de pagamento deve estar ativa (PIX, Cartão ou Dinheiro).",
                isError: true);
          }
          setState(() => _isLoading = false);
          return;
        }
      }

      await FirebaseFirestore.instance.collection('shops').doc(shopId).update({
        'config': {
          'permitir_multiplos': _allowMultiple,
          'permitir_reagendamento': _allowReschedule,
          'cliente_escolhe_prof': _clientChoosesProfessional,
          'agendamento_online_ativo': _onlineBookingActive,
          'intervalo_agenda_min': _appointmentIntervalMinutes,
          'evitar_buracos_agenda': _preventGaps,
          'janela_agendamento_dias':
              _bookingWindowDays.round(), // Salva o novo campo
          'limite_minimo_agendamento_horas':
              _minAdvanceHours.round(), // â° Salva limite mínimo
          'tempo_cancelamento_horas': finalCancelHours,
          'pagamento_pix': _acceptPix,
          'pagamento_cartao': _acceptCard,
          'pagamento_dinheiro': _acceptCash,
          'exigir_sinal': _requireDeposit,
          'percentual_sinal': _depositPercent.round(),
          // única taxa aplicada ao crédito (aplicada quando cliente escolher cartão)
          'tax_percent': _creditTaxPercent,
          'notificar_cliente_agendamento': _notifyClientAppointment,
          'notificar_dias_antes': _notifyDaysBefore,
          // FASE 4 — Parcelamento
          'aceitar_parcelas': _acceptInstallments,
          'max_parcelas': _acceptInstallments ? _maxInstallments : 1,
          'atualizado_em': FieldValue.serverTimestamp(),
        }
      });

      if (mounted) {
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
  }

  // --- COMPONENTES DA UI ---

  Widget _buildMainSettingsForm() {
    return FutureBuilder<bool>(
        future: SubscriptionService.canUseAdvancedScheduling(),
        builder: (context, snapshot) {
          final isPremium = snapshot.data ?? false;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ─────────── Toggle principal — SEMPRE ativo ───────────
              _buildSettingCard([
                _buildSwitchTile(
                    "Agendamento Online Ativo",
                    "Se desativado, os clientes não poderão agendar sozinhos e serão instruídos a te chamar no WhatsApp.",
                    _onlineBookingActive,
                    (v) => _setOnlineBooking(v)),
              ]),

              const SizedBox(height: 24),

              // ─── Tudo abaixo fica desabilitado quando booking for inativo ───
              AbsorbPointer(
                absorbing: !_onlineBookingActive,
                child: AnimatedOpacity(
                  opacity: _onlineBookingActive ? 1.0 : 0.3,
                  duration: const Duration(milliseconds: 300),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ═══ REGRAS DE AGENDAMENTO ═══
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

                        // EVITAR BURACOS (PREMIUM)
                        Opacity(
                          opacity: isPremium ? 1.0 : 0.6,
                          child: SwitchListTile(
                            value: isPremium ? _preventGaps : false,
                            onChanged: isPremium
                                ? (v) => setState(() => _preventGaps = v)
                                : (v) => _showUpgradeDialog(),
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
                                if (!isPremium) _buildPremiumBadge(),
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

                        // MÚLTIPLOS AGENDAMENTOS (PREMIUM)
                        Opacity(
                          opacity: isPremium ? 1.0 : 0.6,
                          child: _buildSwitchTile(
                            "Múltiplos Agendamentos",
                            "Cliente reserva vários serviços/horários",
                            isPremium ? _allowMultiple : false,
                            isPremium
                                ? (v) => setState(() => _allowMultiple = v)
                                : (v) => _showUpgradeDialog(),
                            trailing: !isPremium ? _buildPremiumBadge() : null,
                          ),
                        ),
                        _buildSwitchTile(
                            "Reagendamento Livre",
                            "Permitir troca de horário pelo app",
                            _allowReschedule,
                            (v) => setState(() => _allowReschedule = v)),

                        // ESCOLHA DE PROFISSIONAL (PREMIUM)
                        Opacity(
                          opacity: isPremium ? 1.0 : 0.6,
                          child: _buildSwitchTile(
                            "Escolha de Profissional",
                            "Exibir lista de equipe no agendamento",
                            isPremium ? _clientChoosesProfessional : true,
                            isPremium
                                ? (v) => setState(
                                    () => _clientChoosesProfessional = v)
                                : (v) => _showUpgradeDialog(),
                            trailing: !isPremium ? _buildPremiumBadge() : null,
                          ),
                        ),
                      ]),

                      // ═══ POLÍTICA DE CANCELAMENTO ═══
                      const SizedBox(height: 24),
                      _buildSectionHeader(
                          "Política de Cancelamento", Icons.timer_off),
                      _buildCancelCard(),

                      // ═══ FINANCEIRO E SINAL ═══
                      const SizedBox(height: 24),
                      _buildSectionHeader(
                          "Financeiro e Sinal", Icons.payments_outlined),
                      _buildFinanceCard(),

                      // ═══ PAGAMENTOS ONLINE ═══
                      const SizedBox(height: 12),
                      _buildSectionHeader(
                          "Pagamentos Online", Icons.account_balance_wallet),
                      _buildPaymentIntegrationCard(),

                      // ═══ NOTIFICAÇÕES ═══
                      const SizedBox(height: 24),
                      _buildSectionHeader(
                          "Notificações", Icons.notifications_active),
                      _buildNotificationCard(),

                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),

              // ═══ INTEGRAÇÕES — sempre ativa ═══
              _buildSectionHeader("Integrações", Icons.link),
              _buildIntegrationsCard(),
            ],
          );
        });
  }

  Widget _buildPremiumBadge() {
    return Container(
      margin: const EdgeInsets.only(left: 8),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.grey[200],
        borderRadius: BorderRadius.circular(4),
      ),
      child: const Text("Premium",
          style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: Colors.black54)),
    );
  }

  void _showUpgradeDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Recurso Premium ⭐"),
        content: const Text(
            "Configurações avançadas de agenda são exclusivas de planos pagos.\n\nAssine para liberar!"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Depois"),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await Navigator.pushNamed(context, '/subscription_plans');
              if (mounted) setState(() {});
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryPurple,
                foregroundColor: Colors.white),
            child: const Text("Ver Planos"),
          ),
        ],
      ),
    );
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
          Text(title,
              style:
                  const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
          if (trailing != null) trailing,
        ],
      ),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
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
    return FutureBuilder<bool>(
      future: SubscriptionService.canUseOnlinePayment(),
      builder: (context, snapshot) {
        final isPremium = snapshot.data ?? false;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Banner de upgrade para usuários free
            if (snapshot.hasData && !isPremium)
              PlanUpgradeBanner(
                currentPlanName: 'Free',
                featureDescription: 'pagamentos online (PIX e Cartão)',
                onUpgradeTap: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const SubscriptionPlansPage()),
                  );
                  if (mounted) setState(() {});
                },
              ),
            _buildSettingCard([
              // SINAL / ENTRADA
              SwitchListTile(
                title: const Text("Exigir Sinal (Entrada)",
                    style:
                        TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                value: _requireDeposit,
                activeThumbColor: AppColors.primaryPurple,
                onChanged: isPremium
                    ? (v) => setState(() => _requireDeposit = v)
                    : (v) => _showUpgradeDialog(),
                subtitle: !isPremium
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

                      // PIX
                      Opacity(
                        opacity: isPremium ? 1.0 : 0.6,
                        child: _buildSwitchTile(
                          "PIX",
                          "Pagamento instantâneo via QR",
                          isPremium ? _acceptPix : false,
                          isPremium
                              ? (v) => setState(() => _acceptPix = v)
                              : (v) => _showUpgradeDialog(),
                          trailing: !isPremium ? _buildPremiumBadge() : null,
                        ),
                      ),

                      // Cartão
                      Opacity(
                        opacity: isPremium ? 1.0 : 0.6,
                        child: _buildSwitchTile(
                          "Cartão",
                          "Pagamento com cartão via gateway",
                          isPremium ? _acceptCard : false,
                          isPremium
                              ? (v) => setState(() => _acceptCard = v)
                              : (v) => _showUpgradeDialog(),
                          trailing: !isPremium ? _buildPremiumBadge() : null,
                        ),
                      ),

                      // Dinheiro (sempre)
                      _buildSwitchTile(
                        "Presencial",
                        "Pagamento no local (dinheiro/cartão)",
                        !isPremium ? true : _acceptCash,
                        !isPremium
                            ? (v) {}
                            : (v) => setState(() => _acceptCash = v),
                      ),
                    ]),
              ),

              const Divider(height: 1),
              // CONFIGURAÇÕES DE CARTÃO — bloqueado para plano free
              PlanGateWidget(
                requiredPlan: SubscriptionPlan.starter,
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
                        const Divider(height: 1),
                        const SizedBox(height: 8),
                        const Text("Parcelamento",
                            style: TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 4),
                        _subtitled(Icons.credit_card,
                            "Defina se seus clientes podem parcelar e o máximo de parcelas permitidas."),
                        SwitchListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: const Text("Aceitar Parcelamento",
                              style: TextStyle(fontSize: 13)),
                          value: _acceptInstallments,
                          activeThumbColor: AppColors.primaryPurple,
                          onChanged: (v) =>
                              setState(() => _acceptInstallments = v),
                        ),
                        if (_acceptInstallments) ...[
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text("Máx. de Parcelas",
                                  style: TextStyle(fontSize: 13)),
                              Text("${_maxInstallments}x",
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.primaryPurple)),
                            ],
                          ),
                          Slider(
                            value: _maxInstallments.toDouble(),
                            min: 2,
                            max: 12,
                            divisions: 10,
                            label: "${_maxInstallments}x",
                            activeColor: AppColors.primaryPurple,
                            onChanged: (v) =>
                                setState(() => _maxInstallments = v.round()),
                          ),
                        ],
                      ]),
                ),
              ),
            ]),
          ],
        );
      },
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
                // Map existing _notifyDaysBefore (days) → hours
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
          onPressed: () {
            if (shopId != null) {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => LinkGoogleBusinessPage(shopId: shopId!),
                ),
              );
            }
          },
          icon: const Icon(Icons.link, size: 18),
          label: const Text("CONECTAR"),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primaryPurple,
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

      // --- OPÇÕES AVANÇADAS (final das configurações) ---
      ListTile(
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.red.shade50,
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Icons.delete_forever, color: Colors.red, size: 24),
        ),
        title: const Text(
          "Excluir Conta (Irreversível)",
          style: TextStyle(
              fontSize: 14, fontWeight: FontWeight.bold, color: Colors.red),
        ),
        subtitle: const Text(
          "Remove usuário e marca perfil como excluído. Esta ação NÃO pode ser desfeita.",
          style: TextStyle(fontSize: 12),
        ),
        onTap: () async {
          final confirmed = await _confirmAndDeleteAccount();
          if (confirmed == true) {
            // nothing further here; the delete flow manages navigation
          }
        },
      ),
    ]);
  }

  Widget _buildPaymentIntegrationCard() {
    return FutureBuilder<bool>(
      future: SubscriptionService.canUseOnlinePayment(),
      builder: (context, canPaySnapshot) {
        final canPay = canPaySnapshot.data ?? false;
        return _buildSettingCard([
          PlanGateWidget(
            requiredPlan: SubscriptionPlan.starter,
            featureLabel: 'Conexão com Mercado Pago',
            onUpgradeTap: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const SubscriptionPlansPage()),
              );
              if (mounted) setState(() {});
            },
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("Configurações de Pagamento",
                      style:
                          TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  const Text(
                      "Centralize aqui Mercado Pago, métodos aceitos e regras de parcelamento.",
                      style: TextStyle(fontSize: 12, color: Colors.grey)),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.account_balance_wallet),
                      label: const Text("Conectar / Configurar Mercado Pago"),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primaryPurple,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      onPressed: canPay
                          ? () {
                              if (!mounted) return;
                              Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                      builder: (_) => PaymentSettingsPage(
                                          onClose: () =>
                                              Navigator.pop(context))));
                            }
                          : null,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ]);
      },
    );
  }

  Future<bool?> _confirmAndDeleteAccount() async {
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) {
          bool checked = false;
          return StatefulBuilder(builder: (ctx2, setS) {
            return AlertDialog(
              title: const Text('Excluir Conta - Irreversível'),
              content: Column(mainAxisSize: MainAxisSize.min, children: [
                const Text(
                    'Esta ação excluirá o usuário do Firebase Auth e marcará o perfil como excluído no Firestore. Ã‰ IRRECUPERÃVEL.'),
                const SizedBox(height: 12),
                Row(children: [
                  Checkbox(
                      value: checked,
                      onChanged: (v) => setS(() => checked = v ?? false)),
                  const Expanded(
                      child: Text(
                          'Estou ciente e desejo excluir permanentemente esta conta')),
                ]),
              ]),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx2, false),
                    child: const Text('Cancelar')),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                  onPressed: checked ? () => Navigator.pop(ctx2, true) : null,
                  child: const Text('Excluir'),
                ),
              ],
            );
          });
        });

    if (confirmed == true) {
      if (!mounted) return confirmed;
      // perform deletion
      showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => const Center(child: CircularProgressIndicator()));
      try {
        final user = FirebaseAuth.instance.currentUser;
        if (user == null) throw 'Usuário não autenticado';
        final idToken = await user.getIdToken(true);
        final url = Uri.parse(
            'https://us-central1-wismart-118c3.cloudfunctions.net/deleteUserAccount');
        final resp = await http.post(url,
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $idToken'
            },
            body: jsonEncode({'confirm': true}));
        if (mounted) Navigator.pop(context); // remove progress
        if (resp.statusCode == 200) {
          try {
            await GoogleSignIn().signOut();
            await GoogleSignIn().disconnect();
          } catch (_) {}
          try {
            await NotificationService.removeToken();
          } catch (_) {}
          await SessionService.logout();
          await FirebaseAuth.instance.signOut();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text(
                    'Conta excluída com sucesso. Limpe o cache do app/telefone para evitar reentrar.')));
            Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (_) => const SizedBox()),
                (r) => false);
          }
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text(
                    'Falha ao excluir conta: ${resp.statusCode} ${resp.body}')));
          }
        }
      } catch (e) {
        if (mounted) Navigator.pop(context);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Erro ao excluir conta: $e')));
        }
      }
    }
    return confirmed;
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
