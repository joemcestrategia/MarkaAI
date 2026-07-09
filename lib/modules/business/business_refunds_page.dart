import 'package:supabase_flutter/supabase_flutter.dart' as sb;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/theme/app_colors.dart';
import 'appointment_details_page.dart';

class BusinessRefundsPage extends StatefulWidget {
  final String shopId;
  const BusinessRefundsPage({super.key, required this.shopId});

  @override
  State<BusinessRefundsPage> createState() => _BusinessRefundsPageState();
}

class _BusinessRefundsPageState extends State<BusinessRefundsPage> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _pendentes = [];
  List<Map<String, dynamic>> _resolvidos = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadRefunds();
  }

  Future<void> _loadRefunds() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final client = sb.Supabase.instance.client;
      // Busca todos os cancelados. O filtro de paid_amount faremos em memória 
      // para capturar tanto paid_amount quanto possivelmente valor_pago.
      final res = await client
          .from('appointments')
          .select('id, shop_id, client_name, client_photo, scheduled_at, status, total_price, total_payable, paid_amount, payment_id, refund_status, refund_amount, refunded_at, refunded_by, service_name, duration_min')
          .eq('shop_id', widget.shopId)
          .inFilter('status', ['cancelado', 'reembolsado'])
          .order('scheduled_at', ascending: false);

      final mpRes = await client
          .from('mp_processed_payments')
          .select('payment_id, shop_id, amount, processed_at, reconciliation_status, status, orphan_reason')
          .eq('shop_id', widget.shopId)
          .isFilter('appointment_id', null)
          .eq('status', 'approved');

      final List<Map<String, dynamic>> todosCancelados = List<Map<String, dynamic>>.from(res);
      final List<Map<String, dynamic>> orfaos = List<Map<String, dynamic>>.from(mpRes);
      
      final pendentesTemp = <Map<String, dynamic>>[];
      final resolvidosTemp = <Map<String, dynamic>>[];

      for (var appt in todosCancelados) {
        final paidAmount = double.tryParse(appt['paid_amount']?.toString() ?? '0') ?? 0;
        final refundStatus = appt['refund_status']?.toString();

        // Só nos interessam agendamentos cancelados que tiveram pagamento
        if (paidAmount > 0) {
          if (refundStatus == 'estornado' || refundStatus == 'retido') {
            resolvidosTemp.add(appt);
          } else {
            // Se for pendente, processando, null, ou nao_aplicavel (antigos)
            pendentesTemp.add(appt);
          }
        }
      }

      for (var orphan in orfaos) {
        final amount = double.tryParse(orphan['amount']?.toString() ?? '0') ?? 0;
        final reconStatus = orphan['reconciliation_status']?.toString();
        
        final mappedOrphan = {
          'id': orphan['payment_id'],
          'payment_id': orphan['payment_id'],
          'shop_id': orphan['shop_id'],
          'client_name': 'Cliente não identificado',
          'service_name': 'Pagamento sem agendamento (Falha sistêmica)',
          'scheduled_at': orphan['processed_at'],
          'status': 'cancelado',
          'total_price': amount,
          'total_payable': amount,
          'paid_amount': amount,
          'refund_status': (reconStatus == 'refunded_manually' || reconStatus == 'resolved') ? 'estornado' : 'pendente',
          'refund_amount': (reconStatus == 'refunded_manually' || reconStatus == 'resolved') ? amount : null,
          'is_orphan': true,
          'reconciliation_status': reconStatus,
        };
        
        if (mappedOrphan['refund_status'] == 'estornado') {
          resolvidosTemp.add(mappedOrphan);
        } else {
          pendentesTemp.add(mappedOrphan);
        }
      }

      // Ordenar por data
      pendentesTemp.sort((a, b) => (b['scheduled_at'] ?? '').toString().compareTo((a['scheduled_at'] ?? '').toString()));
      resolvidosTemp.sort((a, b) => (b['scheduled_at'] ?? '').toString().compareTo((a['scheduled_at'] ?? '').toString()));

      setState(() {
        _pendentes = pendentesTemp;
        _resolvidos = resolvidosTemp;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Widget _buildStatusBadge(String refundStatus, double? refundAmount, String? refundedAt) {
    Color bgColor;
    Color textColor;
    IconData icon;
    String label;

    switch (refundStatus) {
      case 'pendente':
        bgColor = Colors.amber.withValues(alpha: 0.15);
        textColor = Colors.amber[800]!;
        icon = Icons.hourglass_empty;
        label = 'Estorno Pendente';
        break;
      case 'processando':
        bgColor = Colors.blue.withValues(alpha: 0.15);
        textColor = Colors.blue[800]!;
        icon = Icons.sync;
        label = 'Processando...';
        break;
      case 'estornado':
        bgColor = Colors.green.withValues(alpha: 0.15);
        textColor = Colors.green[800]!;
        icon = Icons.check_circle_outline;
        label = 'Estornado';
        if (refundAmount != null && refundAmount > 0) {
          label += ' (R\$ ${refundAmount.toStringAsFixed(2)})';
        }
        break;
      case 'retido':
        bgColor = Colors.red.withValues(alpha: 0.15);
        textColor = Colors.red[800]!;
        icon = Icons.block;
        label = 'Resolvido (Retido)';
        break;
      default:
        // Para testes antigos que não tinham status, mostramos como pendente
        bgColor = Colors.amber.withValues(alpha: 0.15);
        textColor = Colors.amber[800]!;
        icon = Icons.warning_amber_rounded;
        label = 'Ação Necessária';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: textColor),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: textColor)),
        ],
      ),
    );
  }

  void _openAppointmentDetails(Map<String, dynamic> appointment) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AppointmentDetailsPage(
          appointmentDoc: appointment,
        ),
      ),
    );
    // Reload if returned something (might have processed refund)
    if (result != null) {
      _loadRefunds();
    }
  }

  void _showOrphanDetails(Map<String, dynamic> orphan) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Pagamento Órfão (Sem Agendamento)'),
          content: const Text(
            'Este pagamento foi aprovado pelo Mercado Pago, mas o agendamento não foi concluído devido a uma falha.\n\n'
            'Como não existe agendamento vinculado, o estorno deve ser feito MANUALMENTE no painel do Mercado Pago (ou app do banco, se foi Pix direto).',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Fechar'),
            ),
            if (orphan['refund_status'] == 'pendente')
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.primaryPurple),
                onPressed: () async {
                  Navigator.pop(context);
                  await _markOrphanAsResolved(orphan['payment_id']);
                },
                child: const Text('Marcar como Resolvido', style: TextStyle(color: Colors.white)),
              ),
          ],
        );
      }
    );
  }

  Future<void> _markOrphanAsResolved(String paymentId) async {
    setState(() => _isLoading = true);
    try {
      await sb.Supabase.instance.client
          .from('mp_processed_payments')
          .update({'reconciliation_status': 'resolved'})
          .eq('payment_id', paymentId);
      _loadRefunds();
    } catch (e) {
      setState(() {
        _isLoading = false;
        _error = e.toString();
      });
    }
  }

  Widget _buildList(List<Map<String, dynamic>> list, String emptyMessage) {
    if (list.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle_outline, size: 64, color: Colors.green.withValues(alpha: 0.5)),
            const SizedBox(height: 16),
            Text(
              emptyMessage,
              style: const TextStyle(fontSize: 16, color: Colors.black54),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadRefunds,
      color: AppColors.primaryPurple,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: list.length,
        itemBuilder: (context, index) {
          final item = list[index];
          final clientName = item['client_name']?.toString() ?? 'Cliente não informado';
          final serviceName = item['service_name']?.toString() ?? 'Serviço';
          final rawDate = item['scheduled_at'];
          DateTime? scheduledAt;
          if (rawDate != null) {
            scheduledAt = DateTime.tryParse(rawDate.toString());
          }
          
          final refundStatus = item['refund_status']?.toString() ?? 'nao_aplicavel';
          final refundAmount = double.tryParse(item['refund_amount']?.toString() ?? '0');
          final refundedAt = item['refunded_at']?.toString();
          final paidAmount = double.tryParse(item['paid_amount']?.toString() ?? '0') ?? 0;

          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: Colors.grey.shade200),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () {
                if (item['is_orphan'] == true) {
                  _showOrphanDetails(item);
                } else {
                  _openAppointmentDetails(item);
                }
              },
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CircleAvatar(
                          backgroundColor: AppColors.primaryPurple.withValues(alpha: 0.1),
                          foregroundColor: AppColors.primaryPurple,
                          radius: 20,
                          child: Text(clientName.isNotEmpty ? clientName[0].toUpperCase() : '?'),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                clientName,
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                serviceName,
                                style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              'R\$ ${paidAmount.toStringAsFixed(2)}',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'Pago',
                              style: TextStyle(color: Colors.grey, fontSize: 11),
                            ),
                          ],
                        ),
                      ],
                    ),
                    if (item['is_orphan'] == true) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.red.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.warning_amber_rounded, size: 14, color: Colors.red),
                            SizedBox(width: 4),
                            Text('Pagamento sem agendamento', style: TextStyle(fontSize: 12, color: Colors.red, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                    ] else ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.blue.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.info_outline, size: 14, color: Colors.blue),
                            SizedBox(width: 4),
                            Text('Cancelamento com cobrança', style: TextStyle(fontSize: 12, color: Colors.blue, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    const Divider(height: 1),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.calendar_today_outlined, size: 14, color: Colors.grey.shade600),
                            const SizedBox(width: 6),
                            Text(
                              scheduledAt != null ? DateFormat('dd/MM/yyyy HH:mm').format(scheduledAt) : 'Sem data',
                              style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
                            ),
                          ],
                        ),
                        _buildStatusBadge(refundStatus, refundAmount, refundedAt),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Color(0xFFF2F4F8),
        body: Center(child: CircularProgressIndicator(color: AppColors.primaryPurple)),
      );
    }

    if (_error != null) {
      return Scaffold(
        backgroundColor: const Color(0xFFF2F4F8),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 16),
              Text('Erro ao carregar estornos:\n$_error', textAlign: TextAlign.center),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _loadRefunds,
                child: const Text('Tentar novamente'),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF2F4F8),
      body: DefaultTabController(
        length: 2,
        child: Column(
          children: [
            Container(
              color: Colors.white,
              child: const TabBar(
                labelColor: AppColors.primaryPurple,
                unselectedLabelColor: Colors.grey,
                indicatorColor: AppColors.primaryPurple,
                indicatorWeight: 3,
                tabs: [
                  Tab(text: 'Pendentes'),
                  Tab(text: 'Resolvidos'),
                ],
              ),
            ),
            Expanded(
              child: TabBarView(
                children: [
                  _buildList(_pendentes, 'Nenhuma pendência financeira.'),
                  _buildList(_resolvidos, 'Nenhum estorno resolvido.'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
