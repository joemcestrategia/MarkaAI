# -*- coding: utf-8 -*-
"""
Rewrite _buildMainSettingsForm in business_settings_page.dart
with correct AbsorbPointer structure.
"""
import re, sys

PATH = r'c:\src\MarkaAI\lib\modules\business\business_settings_page.dart'

with open(PATH, 'r', encoding='utf-8') as f:
    content = f.read()

# Find start and end of _buildMainSettingsForm method
start_marker = '  Widget _buildMainSettingsForm() {'
end_marker = '\n  Widget _buildPremiumBadge()'

start = content.find(start_marker)
end = content.find(end_marker)

if start == -1 or end == -1:
    print(f"ERROR: Could not find method boundaries. start={start} end={end}")
    sys.exit(1)

print(f"Found method at characters {start}..{end}")

# The new method body
new_method = '''  Widget _buildMainSettingsForm() {
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
                      _buildSectionHeader("Regras de Agendamento", Icons.settings_suggest),
                      _buildSettingCard([
                        // INTERVALO
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text("Intervalo da Agenda",
                                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                                    _subtitled(Icons.schedule, "Espaço entre horários (Ex: 08:00, 09:00)"),
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12),
                                decoration: BoxDecoration(
                                    color: AppColors.primaryPurple.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(8)),
                                child: DropdownButtonHideUnderline(
                                  child: DropdownButton<int>(
                                    value: _appointmentIntervalMinutes,
                                    icon: const Icon(Icons.access_time,
                                        size: 18, color: AppColors.primaryPurple),
                                    style: const TextStyle(
                                        color: AppColors.primaryPurple,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13),
                                    items: const [
                                      DropdownMenuItem(value: 15, child: Text("15 min")),
                                      DropdownMenuItem(value: 30, child: Text("30 min")),
                                      DropdownMenuItem(value: 45, child: Text("45 min")),
                                      DropdownMenuItem(value: 60, child: Text("1 hora")),
                                      DropdownMenuItem(value: 90, child: Text("1h 30min")),
                                      DropdownMenuItem(value: 120, child: Text("2 horas")),
                                    ],
                                    onChanged: (val) {
                                      if (val != null) setState(() => _appointmentIntervalMinutes = val);
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
                                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
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
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text("Liberar Agenda por (Dias)",
                                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
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
                                onChanged: (v) => setState(() => _bookingWindowDays = v),
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
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text("Antecedência Mínima (Horas)",
                                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
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
                                onChanged: (v) => setState(() => _minAdvanceHours = v),
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
                                ? (v) => setState(() => _clientChoosesProfessional = v)
                                : (v) => _showUpgradeDialog(),
                            trailing: !isPremium ? _buildPremiumBadge() : null,
                          ),
                        ),
                      ]),

                      // ═══ POLÍTICA DE CANCELAMENTO ═══
                      const SizedBox(height: 24),
                      _buildSectionHeader("Política de Cancelamento", Icons.timer_off),
                      _buildCancelCard(),

                      // ═══ FINANCEIRO E SINAL ═══
                      const SizedBox(height: 24),
                      _buildSectionHeader("Financeiro e Sinal", Icons.payments_outlined),
                      _buildFinanceCard(),

                      // ═══ PAGAMENTOS ONLINE ═══
                      const SizedBox(height: 12),
                      _buildSectionHeader("Pagamentos Online", Icons.account_balance_wallet),
                      _buildPaymentIntegrationCard(),

                      // ═══ NOTIFICAÇÕES ═══
                      const SizedBox(height: 24),
                      _buildSectionHeader("Notificações", Icons.notifications_active),
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

'''

new_content = content[:start] + new_method + content[end + 1:]

with open(PATH, 'w', encoding='utf-8') as f:
    f.write(new_content)

print("Done! Method rewritten successfully.")
print(f"Old length: {len(content)} chars, new length: {len(new_content)} chars")
