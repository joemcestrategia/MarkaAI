import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class CancellationHelper {
  /// Retorna os campos que devem ser mesclados no update (ex: refund_status, cancellation_reason)
  /// Retorna null se a ação foi cancelada pelo usuário (deve abortar o update).
  static Future<Map<String, dynamic>?> getCancellationPayload(BuildContext context, String appointmentId) async {
    // 1. Fetch fresh data to check paid_amount
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    Map<String, dynamic>? freshApt;
    try {
      freshApt = await Supabase.instance.client
          .from('appointments')
          .select('paid_amount')
          .eq('id', appointmentId)
          .single();
    } catch (e) {
      if (context.mounted) Navigator.pop(context); // fecha loading
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao carregar dados: $e'), backgroundColor: Colors.red),
        );
      }
      return null;
    }

    if (context.mounted) Navigator.pop(context); // fecha loading

    final double paidAmount = double.tryParse(freshApt['paid_amount']?.toString() ?? '0') ?? 0;
    final bool hasPaid = paidAmount > 0;

    String? reason;
    String? note;

    if (hasPaid && context.mounted) {
      final result = await showDialog<Map<String, String>>(
        context: context,
        builder: (ctx) {
          String selectedReason = 'cliente_desistiu';
          final noteController = TextEditingController();
          
          return StatefulBuilder(
            builder: (context, setStateSB) {
              return AlertDialog(
                title: const Text('Cancelar Agendamento Pago'),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Este agendamento possui valor pago. O estorno ficará pendente. Selecione o motivo do cancelamento:'),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      value: selectedReason,
                      decoration: const InputDecoration(labelText: 'Motivo', border: OutlineInputBorder()),
                      items: const [
                        DropdownMenuItem(value: 'cliente_desistiu', child: Text('Cliente desistiu')),
                        DropdownMenuItem(value: 'no_show', child: Text('Cliente não compareceu')),
                        DropdownMenuItem(value: 'salao_cancelou', child: Text('Estabelecimento cancelou')),
                        DropdownMenuItem(value: 'outro', child: Text('Outro')),
                      ],
                      onChanged: (val) {
                        if (val != null) setStateSB(() => selectedReason = val);
                      },
                    ),
                    if (selectedReason == 'outro') ...[
                      const SizedBox(height: 16),
                      TextField(
                        controller: noteController,
                        decoration: const InputDecoration(
                          labelText: 'Detalhes adicionais (opcional)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ]
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, null),
                    child: const Text('VOLTAR', style: TextStyle(color: Colors.grey)),
                  ),
                  ElevatedButton(
                    onPressed: () {
                      Navigator.pop(ctx, {
                        'reason': selectedReason,
                        'note': noteController.text.trim(),
                      });
                    },
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
                    child: const Text('CANCELAR AGENDAMENTO'),
                  ),
                ],
              );
            }
          );
        }
      );

      if (result == null) return null;
      reason = result['reason'];
      note = result['note'];
    } else if (context.mounted) {
      // Confirmação simples para agendamentos não pagos
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Cancelar Agendamento'),
          content: const Text('Tem certeza que deseja cancelar este agendamento? Esta ação não pode ser desfeita.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('VOLTAR', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
              child: const Text('CANCELAR'),
            ),
          ],
        ),
      );
      if (confirm != true) return null;
    }

    // Se chegou até aqui, retorna o payload que deve ser mesclado no update
    final Map<String, dynamic> payload = {'status': 'cancelado'};
    if (hasPaid) {
      payload['refund_status'] = 'pendente';
      if (reason != null && reason.isNotEmpty) payload['cancellation_reason'] = reason;
      if (note != null && note.isNotEmpty) payload['cancellation_note'] = note;
    }
    return payload;
  }
}
