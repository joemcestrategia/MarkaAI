import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../core/theme/app_colors.dart';
import '../../core/services/session_service.dart';
import 'link_google_business_page.dart';
import '../backup/calendar_backup_page.dart';

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
  
  // 🕒 Intervalo (Slots)
  int _appointmentIntervalMinutes = 60; 
  
  // 🚫 Evitar Buracos
  bool _preventGaps = false; 

  // 📅 Janela de Agendamento (Novo!)
  double _bookingWindowDays = 30.0; // Padrão: 30 dias
  
  // ⏰ Limite Mínimo de Antecedência (Novo!)
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
  
  // Notificações
  bool _notifyClientAppointment = true;
  int _notifyDaysBefore = 1; // Padrão: 1 dia antes

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
          final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
          if (userDoc.exists) sId = userDoc.data()?['shopId'];
        }
      }

      shopId = sId;

      if (shopId != null) {
        final doc = await FirebaseFirestore.instance.collection('shops').doc(shopId).get();
        if (doc.exists && doc.data() != null) {
          final data = doc.data()!;
          if (data.containsKey('config')) {
            final config = data['config'] as Map<String, dynamic>;
            if (mounted) {
              setState(() {
                _allowMultiple = config['permitir_multiplos'] ?? false;
                _allowReschedule = config['permitir_reagendamento'] ?? true;
                _clientChoosesProfessional = config['cliente_escolhe_prof'] ?? true;
                
                _appointmentIntervalMinutes = config['intervalo_agenda_min'] ?? 60;
                _preventGaps = config['evitar_buracos_agenda'] ?? false;
                
                // 📅 Carrega Janela de Dias
                _bookingWindowDays = (config['janela_agendamento_dias'] ?? 30).toDouble();
                
                // ⏰ Carrega Limite Mínimo de Antecedência
                _minAdvanceHours = (config['limite_minimo_agendamento_horas'] ?? 7).toDouble();

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
                
                // Notificações
                _notifyClientAppointment = config['notificar_cliente_agendamento'] ?? true;
                _notifyDaysBefore = config['notificar_dias_antes'] ?? 1;
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
      int finalCancelHours = _cancelUnit == 'hours' ? _cancelValue.round() : (_cancelValue.round() * 24);
      
      // Ensure at least one payment method is enabled (pix, card or cash)
      if (!(_acceptPix || _acceptCard || _acceptCash)) {
        if (mounted) _showSnack("Ao menos uma forma de pagamento deve estar ativa (PIX, Cartão ou Dinheiro).", isError: true);
        setState(() => _isLoading = false);
        return;
      }

      await FirebaseFirestore.instance.collection('shops').doc(shopId).update({
        'config': {
          'permitir_multiplos': _allowMultiple,
          'permitir_reagendamento': _allowReschedule,
          'cliente_escolhe_prof': _clientChoosesProfessional,
          'intervalo_agenda_min': _appointmentIntervalMinutes,
          'evitar_buracos_agenda': _preventGaps,
          'janela_agendamento_dias': _bookingWindowDays.round(), // Salva o novo campo
          'limite_minimo_agendamento_horas': _minAdvanceHours.round(), // ⏰ Salva limite mínimo
          'tempo_cancelamento_horas': finalCancelHours,
          'pagamento_pix': _acceptPix,
          'pagamento_cartao': _acceptCard,
          'pagamento_dinheiro': _acceptCash,
          'exigir_sinal': _requireDeposit,
          'percentual_sinal': _depositPercent.round(),
          'notificar_cliente_agendamento': _notifyClientAppointment,
          'notificar_dias_antes': _notifyDaysBefore,
          'atualizado_em': FieldValue.serverTimestamp(),
        }
      });
      
      if (mounted) _showSnack("Configurações salvas com sucesso!", isError: false);
    
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

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Scaffold(body: Center(child: CircularProgressIndicator(color: AppColors.primaryPurple)));

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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader("Regras de Agendamento", Icons.settings_suggest),
        _buildSettingCard([
          // 🕒 INTERVALO
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("Intervalo da Agenda", style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                      Text("Espaço entre horários (Ex: 08:00, 09:00)", style: TextStyle(fontSize: 12, color: Colors.grey)),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(color: AppColors.primaryPurple.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<int>(
                      value: _appointmentIntervalMinutes,
                      icon: const Icon(Icons.access_time, size: 18, color: AppColors.primaryPurple),
                      style: const TextStyle(color: AppColors.primaryPurple, fontWeight: FontWeight.bold, fontSize: 13),
                      items: const [
                        DropdownMenuItem(value: 15, child: Text("15 min")),
                        DropdownMenuItem(value: 30, child: Text("30 min")),
                        DropdownMenuItem(value: 45, child: Text("45 min")),
                        DropdownMenuItem(value: 60, child: Text("1 hora")),
                        DropdownMenuItem(value: 90, child: Text("1h 30min")),
                        DropdownMenuItem(value: 120, child: Text("2 horas")),
                      ],
                      onChanged: (val) { if (val != null) setState(() => _appointmentIntervalMinutes = val); },
                    ),
                  ),
                )
              ],
            ),
          ),
          const Divider(height: 1),
          
          // 🚫 EVITAR BURACOS
          SwitchListTile(
            value: _preventGaps,
            onChanged: (v) => setState(() => _preventGaps = v),
            activeThumbColor: AppColors.primaryPurple,
            title: const Text("Otimizar Agenda (Evitar Buracos)", style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
            subtitle: const Text("Força agendamentos em sequência, impedindo horários vagos isolados.", style: TextStyle(fontSize: 12)),
          ),
          const Divider(height: 1),

          // 📅 JANELA DE AGENDAMENTO (NOVO)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text("Liberar Agenda por (Dias)", style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                    Text("${_bookingWindowDays.round()} dias", style: const TextStyle(color: AppColors.primaryPurple, fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 4),
                const Text("Define quantos dias à frente o cliente pode ver no calendário.", style: TextStyle(fontSize: 12, color: Colors.grey)),
                Slider(
                  value: _bookingWindowDays,
                  min: 7,
                  max: 90,
                  divisions: 83, // Passo de 1 em 1 dia
                  activeColor: AppColors.primaryPurple,
                  onChanged: (v) => setState(() => _bookingWindowDays = v),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          
          // ⏰ LIMITE MÍNIMO DE ANTECEDÊNCIA (NOVO)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text("Antecedência Mínima (Horas)", style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                    Text("${_minAdvanceHours.round()}h antes", style: const TextStyle(color: AppColors.primaryPurple, fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 4),
                const Text("Tempo mínimo de antecedência para o cliente agendar. Ex: 12h = não pode agendar para hoje à tarde.", style: TextStyle(fontSize: 12, color: Colors.grey)),
                Slider(
                  value: _minAdvanceHours,
                  min: 1,
                  max: 72, // Até 3 dias (72 horas)
                  divisions: 71,
                  activeColor: AppColors.primaryPurple,
                  onChanged: (v) => setState(() => _minAdvanceHours = v),
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          _buildSwitchTile("Múltiplos Agendamentos", "Cliente reserva vários serviços/horários", _allowMultiple, (v) => setState(() => _allowMultiple = v)),
          _buildSwitchTile("Reagendamento Livre", "Permitir troca de horário pelo app", _allowReschedule, (v) => setState(() => _allowReschedule = v)),
          _buildSwitchTile("Escolha de Profissional", "Exibir lista de equipe no agendamento", _clientChoosesProfessional, (v) => setState(() => _clientChoosesProfessional = v)),
        ]),
        
        const SizedBox(height: 24),
        _buildSectionHeader("Política de Cancelamento", Icons.timer_off),
        _buildCancelCard(),
        
        const SizedBox(height: 24),
        _buildSectionHeader("Financeiro e Sinal", Icons.payments_outlined),
        _buildFinanceCard(),
        
        const SizedBox(height: 24),
        _buildSectionHeader("Notificações", Icons.notifications_active),
        _buildNotificationCard(),
        const SizedBox(height: 24),
        
        _buildSectionHeader("Integrações", Icons.link),
        _buildIntegrationsCard(),
      ],
    );
  }

  Widget _buildHelpPanel({bool isDesktop = false}) {
    return Container(
      color: isDesktop ? Colors.white : Colors.transparent,
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Central de Ajuda", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 20),
          _buildHelpTopic("Liberar Agenda", "Se você definir '30 dias', o cliente hoje só consegue ver vagas até daqui a um mês. Isso evita agendamentos muito distantes."),
          _buildHelpTopic("Evitar Buracos", "Essencial para produtividade! Se você abre às 08:00, o sistema sugere 08:00. Se o cliente tentar 09:00 (deixando o horário das 08h vago), o sistema bloqueia."),
          _buildHelpTopic("Sinal", "Cobrar 30% ou 50% antecipado reduz drasticamente as faltas."),
          if (isDesktop) const Spacer(),
          Container(
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(color: AppColors.primaryPurple.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(12)),
            child: const Row(
              children: [
                Icon(Icons.auto_awesome, color: AppColors.primaryPurple, size: 20),
                SizedBox(width: 10),
                Expanded(child: Text("As alterações refletem na hora para seus clientes.", style: TextStyle(fontSize: 12, color: AppColors.primaryPurple))),
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
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), offset: const Offset(0,-2), blurRadius: 10)]
      ),
      child: SizedBox(
        width: double.infinity,
        height: 50,
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.primaryPurple, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
          onPressed: _saveSettings,
          child: const Text("SALVAR ALTERAÇÕES", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
        ),
      ),
    );
  }

  // --- WIDGETS MENORES ---

  Widget _buildSectionHeader(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, left: 4),
      child: Row(children: [Icon(icon, size: 20, color: AppColors.primaryPurple), const SizedBox(width: 8), Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.black87))]),
    );
  }

  Widget _buildSettingCard(List<Widget> children) {
    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 10)]),
      child: Column(children: children),
    );
  }

  Widget _buildSwitchTile(String title, String subtitle, bool value, Function(bool) onChanged) {
    return SwitchListTile(
      value: value, onChanged: onChanged, activeThumbColor: AppColors.primaryPurple,
      title: Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
    );
  }

  Widget _buildCancelCard() {
    return _buildSettingCard([
      Padding(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          Row(children: [
            _unitChip("Horas", 'hours'), const SizedBox(width: 8), _unitChip("Dias", 'days'), const Spacer(),
            Text("${_cancelValue.round()} ${_cancelUnit == 'hours' ? 'Hrs' : 'Dias'}", style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.primaryPurple)),
          ]),
          Slider(value: _cancelValue, min: 1, max: _cancelUnit == 'hours' ? 24 : 7, divisions: _cancelUnit == 'hours' ? 23 : 6, activeColor: AppColors.primaryPurple, onChanged: (v) => setState(() => _cancelValue = v)),
        ]),
      )
    ]);
  }

  Widget _unitChip(String label, String value) {
    bool isS = _cancelUnit == value;
    return ChoiceChip(label: Text(label, style: TextStyle(fontSize: 12, color: isS ? Colors.white : Colors.black)), selected: isS, selectedColor: AppColors.primaryPurple, onSelected: (s) => setState(() { if(s) _cancelUnit = value; _cancelValue = value == 'hours' ? 2.0 : 1.0; }));
  }

  Widget _buildFinanceCard() {
    return _buildSettingCard([
      SwitchListTile(title: const Text("Exigir Sinal (Entrada)", style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)), value: _requireDeposit, activeThumbColor: AppColors.primaryPurple, onChanged: (v) => setState(() => _requireDeposit = v)),
      if (_requireDeposit) Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), child: Row(children: [const Text("Percentual:", style: TextStyle(fontSize: 13)), Expanded(child: Slider(value: _depositPercent, min: 10, max: 100, divisions: 18, activeColor: AppColors.gold, onChanged: (v) => setState(() => _depositPercent = v))), Text("${_depositPercent.round()}%", style: const TextStyle(fontWeight: FontWeight.bold))])),
    ]);
  }

  Widget _buildNotificationCard() {
    return _buildSettingCard([
      SwitchListTile(
        title: const Text("Notificar Cliente sobre Agendamento", style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
        subtitle: const Text("Envia lembretes automáticos antes do agendamento", style: TextStyle(fontSize: 12)),
        value: _notifyClientAppointment,
        activeThumbColor: AppColors.primaryPurple,
        onChanged: (v) => setState(() => _notifyClientAppointment = v),
      ),
      if (_notifyClientAppointment) ...[
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text("Notificar quantos dias antes?", style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                  Text("$_notifyDaysBefore ${_notifyDaysBefore == 1 ? 'dia' : 'dias'}", style: const TextStyle(color: AppColors.primaryPurple, fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 4),
              const Text("O cliente receberá uma notificação push X dias antes do agendamento para confirmar presença.", style: TextStyle(fontSize: 12, color: Colors.grey)),
              Slider(
                value: _notifyDaysBefore.toDouble(),
                min: 1,
                max: 7,
                divisions: 6,
                activeColor: AppColors.primaryPurple,
                onChanged: (v) => setState(() => _notifyDaysBefore = v.round()),
              ),
            ],
          ),
        ),
      ],
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
      
      // 🆕 Google Calendar Backup
      ListTile(
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.green.shade50,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(Icons.cloud_upload, color: Colors.green.shade700, size: 24),
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
    ]);
  }

  Widget _buildHelpTopic(String title, String desc) {
    return Padding(padding: const EdgeInsets.only(bottom: 20), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.primaryPurple)), const SizedBox(height: 4), Text(desc, style: const TextStyle(fontSize: 12, color: Colors.blueGrey, height: 1.4))]));
  }
}