import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../core/theme/app_colors.dart';

/// Página para cliente confirmar ou cancelar presença em agendamento (aberta via deep link de notificação).
class AppointmentConfirmationPage extends StatefulWidget {
  final String appointmentId;

  const AppointmentConfirmationPage({super.key, required this.appointmentId});

  @override
  State<AppointmentConfirmationPage> createState() => _AppointmentConfirmationPageState();
}

class _AppointmentConfirmationPageState extends State<AppointmentConfirmationPage> {
  bool _isLoading = false;
  Map<String, dynamic>? _appointmentData;

  @override
  void initState() {
    super.initState();
    _loadAppointment();
  }

  Future<void> _loadAppointment() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('appointments')
          .doc(widget.appointmentId)
          .get();
      if (doc.exists && mounted) {
        setState(() => _appointmentData = doc.data());
      }
    } catch (_) {}
  }

  Future<void> _confirmPresence(bool confirmed) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || _appointmentData == null) return;
    
    if (_appointmentData!['clientId'] != user.uid) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Este agendamento não pertence a você.'), backgroundColor: Colors.red),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      await FirebaseFirestore.instance
          .collection('appointments')
          .doc(widget.appointmentId)
          .update({
        'client_confirmed': confirmed,
        'client_confirmed_at': FieldValue.serverTimestamp(),
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(confirmed ? 'Presença confirmada!' : 'Agendamento cancelado.'),
            backgroundColor: confirmed ? Colors.green : Colors.orange,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_appointmentData == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Confirmar Agendamento'), backgroundColor: AppColors.primaryPurple),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final data = _appointmentData!;
    final date = (data['data_agendamento'] as Timestamp?)?.toDate() ?? DateTime.now();
    final servico = data['servico_nome'] ?? 'Serviço';
    final horario = data['horario'] ?? '';
    final valor = data['valor_total'] ?? 0.0;
    final metodoPagamento = data['metodo_pagamento'] ?? '';
    final precisaPagar = (metodoPagamento.toLowerCase().contains('pessoalmente') || 
                          metodoPagamento.toLowerCase().contains('local')) && 
                          (data['valor_pago'] ?? 0.0) == 0.0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Confirmar Agendamento'),
        backgroundColor: AppColors.primaryPurple,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Detalhes do Agendamento', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 16),
                    _buildInfoRow(Icons.cut, 'Serviço', servico),
                    _buildInfoRow(Icons.calendar_today, 'Data', '${date.day}/${date.month}/${date.year}'),
                    _buildInfoRow(Icons.access_time, 'Horário', horario),
                    _buildInfoRow(Icons.attach_money, 'Valor', 'R\$ ${valor.toStringAsFixed(2)}'),
                    if (precisaPagar) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.orange[50],
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.orange[200]!),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.info, color: Colors.orange[700], size: 20),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Pagamento será realizado no local.',
                                style: TextStyle(color: Colors.orange[900], fontSize: 13),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              height: 50,
              child: ElevatedButton(
                onPressed: _isLoading ? null : () => _confirmPresence(true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: _isLoading
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Text('CONFIRMAR PRESENÇA', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 50,
              child: OutlinedButton(
                onPressed: _isLoading ? null : () => _confirmPresence(false),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.orange),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('CANCELAR AGENDAMENTO', style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Colors.grey[700]),
          const SizedBox(width: 12),
          Text('$label: ', style: const TextStyle(fontSize: 14, color: Colors.grey)),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600))),
        ],
      ),
    );
  }
}
