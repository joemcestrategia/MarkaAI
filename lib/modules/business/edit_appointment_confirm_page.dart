import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import '../../core/theme/app_colors.dart';

/// Tela de confirmação da edição de agendamento (exclusiva do fluxo do dono).
/// Exibe o resumo da alteração e, se houver sobreposição, alerta com detalhes
/// do agendamento conflitante.
class EditAppointmentConfirmPage extends StatefulWidget {
  final Map<String, dynamic> appointmentDoc;
  final DateTime newDate;
  final TimeOfDay newTime;

  /// Dados do agendamento conflitante, se houver sobreposição.
  final Map<String, dynamic>? conflictData;
  final Map<String, dynamic>? pendingUpdates; // Recebe updates pendentes
  final VoidCallback? onSuccess;

  const EditAppointmentConfirmPage({
    super.key,
    required this.appointmentDoc,
    required this.newDate,
    required this.newTime,
    this.conflictData,
    this.pendingUpdates,
    this.onSuccess,
  });

  @override
  State<EditAppointmentConfirmPage> createState() =>
      _EditAppointmentConfirmPageState();
}

class _EditAppointmentConfirmPageState
    extends State<EditAppointmentConfirmPage> {
  bool _isSaving = false;
  bool _isLoadingAlternatives = false;

  // Lista de Profissionais livres para assumir o NOVO agendamento (Ação 1 - Reatribuir)
  List<Map<String, dynamic>> _reassignOptions = [];
  String? _selectedReassignId;

  // Lista de Profissionais livres para assumir o ANTIGO agendamento (Ação 2 - Permutar / Swap)
  List<Map<String, dynamic>> _swapOptions = [];
  String? _selectedSwapId;

  // Qual ação extra o usuário escolheu?
  // 0 = Nenhuma (mantém alerta), 1 = Reatribuir Novo, 2 = Permutar Antigo
  int _selectedAction = 0;

  DateTime get _newDateTime => DateTime(
        widget.newDate.year,
        widget.newDate.month,
        widget.newDate.day,
        widget.newTime.hour,
        widget.newTime.minute,
      );

  bool get _hasConflict =>
      widget.conflictData != null && widget.conflictData!.isNotEmpty;

  @override
  void initState() {
    super.initState();
    if (_hasConflict) {
      _fetchAlternatives();
    }
  }

  /// Busca de Profissionais para Swap e Reatribuição
  Future<void> _fetchAlternatives() async {
    setState(() => _isLoadingAlternatives = true);
    try {
      final currentApp = widget.appointmentDoc;
      final shopId = (currentApp['shop_id'] ?? currentApp['shopId']) as String;

      // Usa pendingUpdates se existir, fallback pro original
      final pending = widget.pendingUpdates ?? {};
      final currentProfId = (pending['professional_id'] ??
              currentApp['professional_id'] ??
              currentApp['profissional_id'] ??
              currentApp['profissionalId'])
          .toString();
      final newServiceId =
          pending['service_id'] as String? ?? currentApp['service_id'] as String;
      final int newServiceDuration = pending['duracao_min'] ??
          int.tryParse(currentApp['duracao_min']?.toString() ?? '30') ??
          30;

      // Dados do agendamento Conflitante (O antigo que já ocupava a vaga)
      final conflictApp = widget.conflictData!;
      final oldServiceId = conflictApp['service_id'] as String?;
      final oldServiceDuration =
          int.tryParse(conflictApp['duracao_min']?.toString() ?? '30') ?? 30;
      
      final oldAppStart = conflictApp['scheduled_at'] is String 
          ? DateTime.parse(conflictApp['scheduled_at'])
          : conflictApp['scheduled_at'] as DateTime;

      // Buscar todos os funcionários da loja (exceto o profissional atual)
      final otherEmployees = await Supabase.instance.client
          .from('employees')
          .select()
          .eq('shop_id', shopId)
          .neq('id', currentProfId);

      List<Map<String, dynamic>> reassignMatches = [];
      List<Map<String, dynamic>> swapMatches = [];

      for (var empData in otherEmployees) {
        final skills =
            (empData['servicos_habilidade'] as List?)?.cast<String>() ?? [];

        // 1. O Funcionario sabe fazer o Serviço Novo? (Ação 1: Reatribuir)
        bool canDoNewService = skills.isEmpty || skills.contains(newServiceId);
        if (canDoNewService) {
          bool isFree = await _checkEmployeeAvailability(
              empData['id'].toString(), _newDateTime, newServiceDuration);
          if (isFree) {
            reassignMatches.add({'id': empData['id'].toString(), 'nome': empData['nome']});
          }
        }

        // 2. O Funcionario sabe fazer o Serviço Antigo? (Ação 2: Swap)
        if (oldServiceId != null) {
          bool canDoOldService =
              skills.isEmpty || skills.contains(oldServiceId);
          if (canDoOldService) {
            bool isFree = await _checkEmployeeAvailability(
                empData['id'].toString(), oldAppStart, oldServiceDuration);
            if (isFree) {
              swapMatches.add({'id': empData['id'].toString(), 'nome': empData['nome']});
            }
          }
        }
      }

      if (mounted) {
        setState(() {
          _reassignOptions = reassignMatches;
          _swapOptions = swapMatches;

          if (_reassignOptions.isNotEmpty) {
            _selectedReassignId = _reassignOptions.first['id'];
          }
          if (_swapOptions.isNotEmpty) {
            _selectedSwapId = _swapOptions.first['id'];
          }
        });
      }
    } catch (e) {
      debugPrint("Erro buscando alternativas: \$e");
    } finally {
      if (mounted) setState(() => _isLoadingAlternatives = false);
    }
  }

  Future<bool> _checkEmployeeAvailability(
      String empId, DateTime targetStart, int duration) async {
    final dayStart =
        DateTime(targetStart.year, targetStart.month, targetStart.day);
    final dayEnd = dayStart.add(const Duration(days: 1));

    final snap = await Supabase.instance.client
        .from('appointments')
        .select()
        .eq('professional_id', empId)
        .gte('scheduled_at', dayStart.toIso8601String())
        .lt('scheduled_at', dayEnd.toIso8601String());

    final targetStartMin = targetStart.hour * 60 + targetStart.minute;
    final targetEndMin = targetStartMin + duration;

    for (var d in snap) {
      final status = (d['status'] ?? '').toString().toLowerCase();
      if (status == 'cancelado' || status == 'rejeitado' || status == 'recusado' || status == 'excluido') {
        continue;
      }

      final appStart = DateTime.parse(d['scheduled_at'].toString());
      final appDur = int.tryParse(d['duration_min']?.toString() ?? '30') ?? 30;
      final startMin = appStart.hour * 60 + appStart.minute;
      final endMin = startMin + appDur;

      if (targetStartMin < endMin && startMin < targetEndMin) {
        return false; // Colisão
      }
    }
    return true; // Livre
  }

  Future<void> _processSwapOrReassignment() async {
    setState(() => _isSaving = true);
    try {
      final Map<String, dynamic> updatesToSave = {
        ...?widget.pendingUpdates,
        'scheduled_at': _newDateTime.toIso8601String(),
        // Operação administrativa (readequação): dono autorizado a sobrepor
        'bypass_overlap_check': true,
      };

      if (_selectedAction == 1 && _selectedReassignId != null) {
        // Ação 1: REATRIBUIR
        updatesToSave['professional_id'] = _selectedReassignId;
        await Supabase.instance.client
          .from('appointments')
          .update(updatesToSave)
          .eq('id', widget.appointmentDoc['id']);
      } else if (_selectedAction == 2 && _selectedSwapId != null) {
        // Ação 2: PERMUTA/SWAP
        final conflictId = widget.conflictData!['id'];

        await Supabase.instance.client
          .from('appointments')
          .update({
            'professional_id': _selectedSwapId,
            'bypass_overlap_check': true,
          })
          .eq('id', conflictId);

        await Supabase.instance.client
          .from('appointments')
          .update(updatesToSave)
          .eq('id', widget.appointmentDoc['id']);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Readequação de agenda concluída com sucesso! ✅'),
            backgroundColor: AppColors.successGreen,
          ),
        );
        int count = 0;
        Navigator.of(context).popUntil((_) => count++ >= 3);
        widget.onSuccess?.call();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao salvar realocação: \$e'),
            backgroundColor: AppColors.errorRed,
          ),
        );
      }
    }
  }

  Future<void> _confirm() async {
    if (_hasConflict && _selectedAction > 0) {
      await _processSwapOrReassignment();
      return;
    }
    setState(() => _isSaving = true);
    try {
      final data = widget.appointmentDoc;
      final pending = widget.pendingUpdates ?? {};

      // --- RE-VALIDAÇÃO BACKEND (PRE-UPDATE) ---
      final dayStart =
          DateTime(_newDateTime.year, _newDateTime.month, _newDateTime.day);
      final dayEnd = DateTime(
          _newDateTime.year, _newDateTime.month, _newDateTime.day, 23, 59);

      final serviceDur = pending['duracao_min'] ??
          int.tryParse(data['duracao_min']?.toString() ?? '') ??
          30;
      final newStartMin = _newDateTime.hour * 60 + _newDateTime.minute;
      final newEndMin = newStartMin + serviceDur;

      final profId = (pending['professional_id'] ??
              data['professional_id'] ??
              data['profissional_id'] ??
              data['profissionalId'])
          ?.toString();
      final clientId =
          pending['client_id'] as String? ?? data['client_id'] as String?;

      if (profId != null) {
        final snapProf = await Supabase.instance.client
            .from('appointments')
            .select()
            .eq('professional_id', profId)
            .gte('scheduled_at', dayStart.toIso8601String())
            .lte('scheduled_at', dayEnd.toIso8601String());

        for (final d in snapProf) {
          if (d['id'] == widget.appointmentDoc['id']) continue;
          final status = (d['status'] ?? '').toString().toLowerCase();
          if (status == 'cancelado' ||
              status == 'rejeitado' ||
              status == 'recusado' ||
              status == 'excluido') {
            continue;
          }

          final dt = DateTime.parse(d['scheduled_at'].toString());
          final dur = int.tryParse(d['duration_min']?.toString() ?? '') ?? 30;
          final startMin = dt.hour * 60 + dt.minute;
          final endMin = startMin + dur;

          if (newStartMin < endMin && startMin < newEndMin) {
            throw Exception(
                "O profissional já possui um agendamento conflitante neste horário.");
          }
        }
      }

      if (clientId != null && clientId.isNotEmpty) {
        final snapClient = await Supabase.instance.client
            .from('appointments')
            .select()
            .eq('client_id', clientId)
            .gte('scheduled_at', dayStart.toIso8601String())
            .lte('scheduled_at', dayEnd.toIso8601String());

        for (final d in snapClient) {
          if (d['id'] == widget.appointmentDoc['id']) continue;
          final status = (d['status'] ?? '').toString().toLowerCase();
          if (status == 'cancelado' ||
              status == 'rejeitado' ||
              status == 'recusado' ||
              status == 'excluido') {
            continue;
          }

          final dt = DateTime.parse(d['scheduled_at'].toString());
          final dur = int.tryParse(d['duration_min']?.toString() ?? '') ?? 30;
          final startMin = dt.hour * 60 + dt.minute;
          final endMin = startMin + dur;

          if (newStartMin < endMin && startMin < newEndMin) {
            throw Exception(
                "O cliente já possui outro serviço agendado neste mesmo horário.");
          }
        }
      }
      // --- FIM RE-VALIDAÇÃO ---

      await Supabase.instance.client
          .from('appointments')
          .update({
            ...?widget.pendingUpdates,
            'scheduled_at': _newDateTime.toIso8601String(),
          })
          .eq('id', widget.appointmentDoc['id']);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Agendamento atualizado com sucesso! ✅'),
            backgroundColor: AppColors.successGreen,
          ),
        );
        // Fecha todas as telas do fluxo de edição (Confirm + Slots + Date)
        int count = 0;
        Navigator.of(context).popUntil((_) => count++ >= 3);
        widget.onSuccess?.call();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao salvar: $e'),
            backgroundColor: AppColors.errorRed,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.appointmentDoc;
    final pending = widget.pendingUpdates ?? {};

    final originalDt = data['scheduled_at'] is String
        ? DateTime.parse(data['scheduled_at'])
        : (data['scheduled_at'] as DateTime);
    final dateFormat = DateFormat('dd/MM/yyyy', 'pt_BR');
    final timeFormat = DateFormat('HH:mm', 'pt_BR');

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FD),
      appBar: AppBar(
        title: const Text('Confirmar Reagendamento'),
        backgroundColor: AppColors.primaryPurple,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Resumo da alteração ────────────────────────────────────────
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.grey.shade200),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.03),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'RESUMO DA ALTERAÇÃO',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey,
                      letterSpacing: 1.0,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Serviço
                  _buildChangeRow(
                    icon: Icons.content_cut,
                    title: 'Serviço',
                    oldValue: data['servico_nome'] ?? 'Serviço',
                    newValue: pending['servico_nome'] ??
                        data['servico_nome'] ??
                        'Serviço',
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Divider(height: 1, color: Color(0xFFEEEEEE)),
                  ),

                  // Profissional
                  _buildChangeRow(
                    icon: Icons.badge_outlined,
                    title: 'Profissional',
                    oldValue: data['profissional_nome'] ?? 'Profissional',
                    newValue: pending['profissional_nome'] ??
                        data['profissional_nome'] ??
                        'Profissional',
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Divider(height: 1, color: Color(0xFFEEEEEE)),
                  ),

                  // Data / Hora
                  _buildChangeRow(
                    icon: Icons.schedule_outlined,
                    title: 'Data / Horário',
                    oldValue:
                        '${dateFormat.format(originalDt)}, às ${timeFormat.format(originalDt)}',
                    newValue:
                        '${dateFormat.format(widget.newDate)}, às ${widget.newTime.format(context)}',
                    isHighlight: true,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // ── Alerta de sobreposição (se houver) ─────────────────────────
            if (_hasConflict) ...[
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.orange, width: 1.5),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.warning_amber_rounded,
                            color: Colors.orange, size: 20),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            'ATENÇÃO: sobreposição de agendamentos',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: Colors.deepOrange,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'O horário selecionado já possui um agendamento:',
                      style: TextStyle(fontSize: 13, color: Colors.grey[700]),
                    ),
                    const SizedBox(height: 8),
                    _buildConflictDetail(),
                    const SizedBox(height: 8),
                    Text(
                      'Selecione outro horário para continuar.',
                      style: TextStyle(
                          fontSize: 12,
                          color: Colors.red[700],
                          fontStyle: FontStyle.italic,
                          fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // ── Sugestões Inteligentes de Swap / Reatribuição ──────────────
              if (_isLoadingAlternatives)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(20.0),
                    child: CircularProgressIndicator(
                        color: AppColors.primaryPurple),
                  ),
                )
              else if (_reassignOptions.isNotEmpty ||
                  _swapOptions.isNotEmpty) ...[
                const Text(
                  '💡 Sugestões de Resolução',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primaryPurple),
                ),
                const SizedBox(height: 10),

                // Sugestão 1: Reatribuir o Novo Agendamento
                if (_reassignOptions.isNotEmpty)
                  _buildSuggestionCard(
                    title: 'Reatribuir Serviço Novo',
                    description:
                        'Outro profissional está livre para fazer o serviço que você está tentando editar neste horário.',
                    actionValue: 1,
                    options: _reassignOptions,
                    selectedId: _selectedReassignId,
                    onChangedOption: (val) =>
                        setState(() => _selectedReassignId = val),
                  ),
                if (_reassignOptions.isNotEmpty) const SizedBox(height: 12),

                // Sugestão 2: Permutar o Agendamento Antigo
                if (_swapOptions.isNotEmpty)
                  _buildSuggestionCard(
                    title: 'Transferir Serviço Conflitante',
                    description:
                        'Transfira o agendamento antigo (que está ocupando a vaga) para um colega que está livre, liberando espaço para o seu novo serviço.',
                    actionValue: 2,
                    options: _swapOptions,
                    selectedId: _selectedSwapId,
                    onChangedOption: (val) =>
                        setState(() => _selectedSwapId = val),
                  ),
                const SizedBox(height: 20),
              ],
            ],

            // ── Informação sobre o agendamento sendo editado ───────────────
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.primaryPurple.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Icon(Icons.person_outline,
                      color: AppColors.primaryPurple, size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          data['client_nome'] ??
                              data['cliente_nome'] ??
                              'Cliente',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                        Text(
                          data['servico_nome'] ?? 'Serviço',
                          style:
                              const TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 32),

            // ── Botões ─────────────────────────────────────────────────────
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _isSaving ? null : () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      side: BorderSide(color: Colors.grey.shade400),
                      foregroundColor: Colors.black87,
                    ),
                    child: const Text('CANCELAR',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    onPressed: _isSaving || _hasConflict ? null : _confirm,
                    style: ElevatedButton.styleFrom(
                      backgroundColor:
                          _hasConflict ? Colors.grey : AppColors.primaryPurple,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                    ),
                    child: _isSaving
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : Text(
                            (_hasConflict && _selectedAction > 0)
                                ? 'APLICAR SOLUÇÃO'
                                : _hasConflict
                                    ? 'HORÁRIO INDISPONÍVEL'
                                    : 'CONFIRMAR',
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSuggestionCard({
    required String title,
    required String description,
    required int actionValue,
    required List<Map<String, dynamic>> options,
    required String? selectedId,
    required ValueChanged<String?> onChangedOption,
  }) {
    final bool isSelected = _selectedAction == actionValue;

    return GestureDetector(
      onTap: () => setState(() => _selectedAction = actionValue),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primaryPurple.withValues(alpha: 0.05)
              : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? AppColors.primaryPurple : Colors.grey.shade300,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Radio<int>(
                  value: actionValue,
                  groupValue: _selectedAction,
                  onChanged: (val) {
                    if (val != null) {
                      setState(() => _selectedAction = val);
                    }
                  },
                  activeColor: AppColors.primaryPurple,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color:
                          isSelected ? AppColors.primaryPurple : Colors.black87,
                    ),
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(left: 48.0, right: 8.0),
              child: Text(
                description,
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ),
            if (options.length > 1) ...[
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.only(left: 48.0),
                child: DropdownButtonFormField<String>(
                  value: selectedId,
                  isExpanded: true,
                  decoration: InputDecoration(
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                  ),
                  items: options.map((opt) {
                    return DropdownMenuItem<String>(
                      value: opt['id'],
                      child: Text(opt['nome'],
                          style: const TextStyle(fontSize: 13)),
                    );
                  }).toList(),
                  onChanged: isSelected ? onChangedOption : null,
                ),
              ),
            ] else if (options.isNotEmpty) ...[
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.only(left: 48.0),
                child: Text(
                  'Substituto disponível: ${options.first['nome']}',
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildChangeRow({
    required IconData icon,
    required String title,
    required String oldValue,
    required String newValue,
    bool isHighlight = false,
  }) {
    final hasChanged = oldValue != newValue;
    final color = isHighlight ? AppColors.primaryPurple : Colors.black87;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: AppColors.primaryPurple.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 16, color: AppColors.primaryPurple),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: const TextStyle(fontSize: 11, color: Colors.grey)),
              if (hasChanged) ...[
                Text(
                  oldValue,
                  style: const TextStyle(
                      fontSize: 13,
                      color: Colors.grey,
                      decoration: TextDecoration.lineThrough),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    const Icon(Icons.subdirectory_arrow_right,
                        size: 14, color: AppColors.primaryPurple),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        newValue,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: color,
                        ),
                      ),
                    ),
                  ],
                ),
              ] else ...[
                Text(
                  newValue,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: isHighlight ? FontWeight.bold : FontWeight.w500,
                    color: color,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildConflictDetail() {
    final d = widget.conflictData!;
    final conflictName = d['client_nome'] ?? d['cliente_nome'] ?? 'Cliente';
    final conflictService = d['servico_nome'] ?? 'Serviço';
    final ts = d['scheduled_at'];
    String conflictTime = '';
    if (ts != null) {
      final dt = ts is String ? DateTime.parse(ts) : (ts as DateTime);
      conflictTime =
          '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    }

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.orange.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.person, size: 14, color: Colors.deepOrange),
              const SizedBox(width: 6),
              Text(conflictName,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 13)),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              const Icon(Icons.content_cut, size: 14, color: Colors.grey),
              const SizedBox(width: 6),
              Text(conflictService,
                  style: const TextStyle(fontSize: 12, color: Colors.black87)),
            ],
          ),
          if (conflictTime.isNotEmpty) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(Icons.schedule, size: 14, color: Colors.grey),
                const SizedBox(width: 6),
                Text(conflictTime,
                    style:
                        const TextStyle(fontSize: 12, color: Colors.black87)),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
