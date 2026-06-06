import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/theme/app_colors.dart';
import '../schedule/booking_page.dart';
import 'edit_appointment_confirm_page.dart';
import 'owner_calendar_picker.dart';
import '../../core/utils/work_schedule.dart';

/// Tela de seleção de data no modo de edição do dono.
/// Usa [OwnerCalendarPicker] que marca dias completamente ocupados com cinza + risco.
class EditAppointmentDatePage extends StatefulWidget {
  final Map<String, dynamic> appointmentDoc;
  final Map<String, dynamic> shop;
  final Map<String, dynamic> serviceDoc;
  final Map<String, dynamic> professionalDoc;
  final Map<String, dynamic> shopConfig;
  final int intervalMinutes;
  final Map<String, dynamic> pendingUpdates; // Pushed from DetailsPage
  final VoidCallback? onSuccess;

  const EditAppointmentDatePage({
    super.key,
    required this.appointmentDoc,
    required this.shop,
    required this.serviceDoc,
    required this.professionalDoc,
    required this.shopConfig,
    required this.intervalMinutes,
    required this.pendingUpdates,
    this.onSuccess,
  });

  @override
  State<EditAppointmentDatePage> createState() =>
      _EditAppointmentDatePageState();
}

class _EditAppointmentDatePageState extends State<EditAppointmentDatePage> {
  DateTime? _selectedDate;
  int _bookingWindowDays = 365;

  Map<String, dynamic> get _appointmentData => widget.appointmentDoc;
  
  DateTime get _originalDateTime {
    final raw = _appointmentData['scheduled_at'];
    if (raw is DateTime) return raw;
    if (raw is String) return DateTime.tryParse(raw) ?? DateTime.now();
    return DateTime.now();
  }

  String get _originalSlotTime =>
      '${_originalDateTime.hour.toString().padLeft(2, '0')}:'
      '${_originalDateTime.minute.toString().padLeft(2, '0')}';

  @override
  void initState() {
    super.initState();
    // Pré-seleciona a data atual do agendamento
    final orig = _originalDateTime;
    _selectedDate = DateTime(orig.year, orig.month, orig.day);
    _bookingWindowDays = widget.shopConfig['janela_agendamento_dias'] ?? 365;
  }

  @override
  Widget build(BuildContext context) {
    final svcName = widget.serviceDoc['nome'] ?? 'Serviço';
    final profData = widget.professionalDoc;
    final ws = WorkSchedule.fromEmployeeRow(profData);
    final List<int> workDays = ws.workDays.isNotEmpty
        ? ws.workDays
        : ((profData['work_days'] ?? profData['dias_trabalho'] ?? [1, 2, 3, 4, 5, 6])
                as List)
            .map((e) => int.parse(e.toString()))
            .toList();
    final svcData = widget.serviceDoc;
    final int serviceDuration =
        int.tryParse(svcData['tempo_min']?.toString() ?? '') ?? 30;
    final String profStart =
        profData['work_start'] ?? profData['start_time'] ?? '08:00';
    final String profEnd =
        profData['work_end'] ?? profData['end_time'] ?? '18:00';

    final today = DateTime.now();
    final firstDate = DateTime(today.year, today.month, today.day);
    final lastDate = today.add(Duration(days: _bookingWindowDays));

    // Garante que initialDate seja um dia de trabalho válido
    DateTime initialDate = _selectedDate ?? firstDate;
    if (initialDate.isBefore(firstDate)) initialDate = firstDate;
    int safety = 0;
    while (!workDays.contains(initialDate.weekday) && safety < 60) {
      initialDate = initialDate.add(const Duration(days: 1));
      safety++;
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FD),
      appBar: AppBar(
        title: Text('Reagendar — $svcName'),
        backgroundColor: AppColors.primaryPurple,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Indicador do agendamento original
              Container(
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: AppColors.primaryPurple.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: AppColors.primaryPurple.withValues(alpha: 0.2)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.event_repeat,
                        color: AppColors.primaryPurple, size: 18),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Agendamento atual',
                            style: TextStyle(fontSize: 11, color: Colors.grey),
                          ),
                          Text(
                            DateFormat('EEEE, dd/MM/yyyy', 'pt_BR')
                                .format(_originalDateTime),
                            style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: AppColors.primaryPurple),
                          ),
                          Text(
                            '${_appointmentData['client_nome'] ?? _appointmentData['cliente_nome'] ?? 'Cliente'}'
                            ' • $_originalSlotTime',
                            style: const TextStyle(
                                fontSize: 12, color: Colors.black87),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              // Calendário customizado com disponibilidade
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withValues(alpha: 0.04),
                        blurRadius: 8),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Selecione uma nova data',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 16),
                      OwnerCalendarPicker(
                        initialDate: initialDate,
                        firstDate: firstDate,
                        lastDate: lastDate,
                        workDays: workDays,
                        shopId: widget.shop['id'],
                        professionalId: widget.professionalDoc['id'],
                        intervalMinutes: widget.intervalMinutes,
                        serviceDurationMinutes: serviceDuration,
                        profStartTime: profStart,
                        profEndTime: profEnd,
                        professionalDoc: profData,
                        excludeAppointmentId: widget.appointmentDoc['id'],
                        onDateSelected: (d) =>
                            setState(() => _selectedDate = d),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              // Data selecionada
              if (_selectedDate != null)
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.primaryPurple.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.primaryPurple),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.check_circle,
                          color: AppColors.primaryPurple),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          DateFormat('EEEE, dd/MM/yyyy', 'pt_BR')
                              .format(_selectedDate!),
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 20),
              // Botões
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        side: BorderSide(color: Colors.grey.shade400),
                        foregroundColor: Colors.black87,
                      ),
                      onPressed: () => Navigator.pop(context),
                      child: const Text('CANCELAR',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      onPressed: _selectedDate == null
                          ? null
                          : () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => BookingSlotsPage(
                                    shop: widget.shop,
                                    serviceDoc: widget.serviceDoc,
                                    professionalDoc: widget.professionalDoc,
                                    shopConfig: widget.shopConfig,
                                    intervalMinutes: widget.intervalMinutes,
                                    minAdvanceHours: 0,
                                    selectedDate: _selectedDate!,
                                    // Props do modo dono
                                    ownerExcludeAppointmentId:
                                        widget.appointmentDoc['id'],
                                    ownerHighlightedSlotTime: _originalSlotTime,
                                    allowOccupiedSelection: true,
                                    // Substitui checkout/cloud fn pelo fluxo de confirmação do dono
                                    onOwnerSlotConfirmed:
                                        (selectedTime, conflictData) {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) =>
                                              EditAppointmentConfirmPage(
                                            appointmentDoc:
                                                widget.appointmentDoc,
                                            newDate: _selectedDate!,
                                            newTime: selectedTime,
                                            conflictData: conflictData,
                                            pendingUpdates: widget
                                                .pendingUpdates, // Forwarded
                                            onSuccess: widget.onSuccess,
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              );
                            },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primaryPurple,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        elevation: 0,
                      ),
                      child: const Text('VER HORÁRIOS',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 14)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
