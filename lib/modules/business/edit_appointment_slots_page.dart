import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../../core/theme/app_colors.dart';
import '../schedule/booking_page.dart';
import 'edit_appointment_confirm_page.dart';

/// Tela de seleção de horários no modo de edição do dono.
/// Wrapper em torno de [BookingSlotsPage] com contexto de edição:
/// - Exclui o slot do agendamento em edição do cálculo de ocupação.
/// - Destaca o horário original com badge "atual".
/// - Permite selecionar slots ocupados (privilégio do dono).
class EditAppointmentSlotsPage extends StatefulWidget {
  final DocumentSnapshot appointmentDoc;
  final DocumentSnapshot shop;
  final DocumentSnapshot serviceDoc;
  final DocumentSnapshot professionalDoc;
  final Map<String, dynamic> shopConfig;
  final int intervalMinutes;
  final DateTime selectedDate;
  final String originalSlotTime; // "HH:mm" do agendamento original
  final VoidCallback? onSuccess;

  const EditAppointmentSlotsPage({
    super.key,
    required this.appointmentDoc,
    required this.shop,
    required this.serviceDoc,
    required this.professionalDoc,
    required this.shopConfig,
    required this.intervalMinutes,
    required this.selectedDate,
    required this.originalSlotTime,
    this.onSuccess,
  });

  @override
  State<EditAppointmentSlotsPage> createState() =>
      _EditAppointmentSlotsPageState();
}

class _EditAppointmentSlotsPageState extends State<EditAppointmentSlotsPage> {
  TimeOfDay? _selectedTime;
  Map<String, dynamic>? _conflictData;

  @override
  Widget build(BuildContext context) {
    final svcName =
        (widget.serviceDoc.data() as Map<String, dynamic>)['nome'] ?? 'Serviço';
    final dateStr =
        DateFormat('dd/MM/yyyy', 'pt_BR').format(widget.selectedDate);

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FD),
      appBar: AppBar(
        title: Text('Reagendar — $svcName'),
        backgroundColor: AppColors.primaryPurple,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Column(
        children: [
          // Cabeçalho com a data selecionada
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            color: AppColors.primaryPurple.withValues(alpha: 0.06),
            child: Row(
              children: [
                const Icon(Icons.calendar_today,
                    size: 16, color: AppColors.primaryPurple),
                const SizedBox(width: 8),
                Text(
                  dateStr,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: AppColors.primaryPurple,
                  ),
                ),
              ],
            ),
          ),
          // Grade de horários via BookingSlotsPage com props de modo dono
          Expanded(
            child: BookingSlotsPage(
              shop: widget.shop,
              serviceDoc: widget.serviceDoc,
              professionalDoc: widget.professionalDoc,
              shopConfig: widget.shopConfig,
              intervalMinutes: widget.intervalMinutes,
              minAdvanceHours: 0, // dono não tem restrição de antecedência
              selectedDate: widget.selectedDate,
              // Props do modo dono
              ownerExcludeAppointmentId: widget.appointmentDoc.id,
              ownerHighlightedSlotTime: widget.originalSlotTime,
              allowOccupiedSelection: true,
              onOccupiedSlotSelected: (slot, conflictData) {
                setState(() => _conflictData = conflictData);
              },
            ),
          ),
          // Rodapé com botões de ação
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
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
                      child: const Text('VOLTAR',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      onPressed: _selectedTime == null
                          ? null
                          : () {
                              // Passa o conflictData apenas se houver sobreposição
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => EditAppointmentConfirmPage(
                                    appointmentDoc: widget.appointmentDoc,
                                    newDate: widget.selectedDate,
                                    newTime: _selectedTime!,
                                    conflictData: _conflictData,
                                    onSuccess: widget.onSuccess,
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
                      child: const Text('CONFIRMAR HORÁRIO',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 13)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
