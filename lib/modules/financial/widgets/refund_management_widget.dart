import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_colors.dart';

class RefundManagementWidget extends StatefulWidget {
  final String shopId;

  const RefundManagementWidget({super.key, required this.shopId});

  @override
  State<RefundManagementWidget> createState() => _RefundManagementWidgetState();
}

class _RefundManagementWidgetState extends State<RefundManagementWidget> {
  final currencyFormat = NumberFormat.simpleCurrency(locale: 'pt_BR');

  Future<void> _processRefund(DocumentSnapshot doc, bool approve) async {
    final act = approve ? 'Aprovar' : 'Recusar';
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('$act Reembolso'),
        content: Text(
          approve
              ? 'Tem certeza que deseja aprovar este reembolso?\n\nO cliente será notificado e você deve realizar a transferência PIX manualmente para a chave informada.'
              : 'Tem certeza que deseja recusar esta solicitação?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('CANCELAR'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: approve ? AppColors.primaryPurple : Colors.red,
            ),
            child: Text('SIM, ${act.toUpperCase()}'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await FirebaseFirestore.instance
          .collection('refundRequests')
          .doc(doc.id)
          .update({
        'status': approve ? 'aprovado' : 'recusado',
        'data_processamento': FieldValue.serverTimestamp(),
      });

      // Se for aprovado, atualizar o agendamento para refletir que o reembolso foi concluído
      if (approve) {
        final data = doc.data() as Map<String, dynamic>;
        final appId = data['appointmentId'] as String?;
        if (appId != null) {
          await FirebaseFirestore.instance
              .collection('appointments')
              .doc(appId)
              .update({'reembolso_pendente': false, 'reembolso_pago': true});
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Solicitação ${approve ? 'aprovada' : 'recusada'} com sucesso.'),
            backgroundColor: approve ? Colors.green : Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Erro ao processar: $e'),
              backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('refundRequests')
          .where('shopId', isEqualTo: widget.shopId)
          .where('status', isEqualTo: 'pendente')
          .orderBy('data_solicitacao', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const SizedBox.shrink(); // Hide on error
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const SizedBox.shrink(); // Hide if no pending requests
        }

        final docs = snapshot.data!.docs;

        return Container(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.orange.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.orange.shade200),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.warning_amber_rounded, color: Colors.orange),
                  const SizedBox(width: 8),
                  Text(
                    '${docs.length} Solicitaç${docs.length > 1 ? 'ões' : 'ão'} de Reembolso',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: Colors.black87,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ...docs.map((doc) {
                final data = doc.data() as Map<String, dynamic>;
                final valor = (data['valor_pago'] ?? 0).toDouble();
                final date = (data['data_solicitacao'] as Timestamp?)?.toDate();

                return Card(
                  elevation: 0,
                  color: Colors.white,
                  margin: const EdgeInsets.only(bottom: 8),
                  shape: RoundedRectangleBorder(
                    side: BorderSide(color: Colors.orange.shade100),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              data['clientName'] ?? 'Cliente Desconhecido',
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            Text(
                              currencyFormat.format(valor),
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.red),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Chave PIX: ${data['chave_pix'] ?? 'Não informada'}',
                          style: const TextStyle(fontSize: 13),
                        ),
                        if (data['motivo'] != null &&
                            data['motivo'].toString().isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              'Motivo: ${data['motivo']}',
                              style: const TextStyle(
                                  fontSize: 12,
                                  fontStyle: FontStyle.italic,
                                  color: Colors.black54),
                            ),
                          ),
                        if (date != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              'Solicitado em ${DateFormat('dd/MM HH:mm').format(date)}',
                              style: const TextStyle(
                                  fontSize: 11, color: Colors.grey),
                            ),
                          ),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton(
                              onPressed: () => _processRefund(doc, false),
                              style: TextButton.styleFrom(
                                  foregroundColor: Colors.grey.shade700),
                              child: const Text('RECUSAR'),
                            ),
                            const SizedBox(width: 8),
                            ElevatedButton(
                              onPressed: () => _processRefund(doc, true),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.orange,
                                foregroundColor: Colors.white,
                                elevation: 0,
                              ),
                              child: const Text('MARCAR COMO PAGO'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ],
          ),
        );
      },
    );
  }
}
