import 'package:supabase_flutter/supabase_flutter.dart' as sb;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/theme/app_colors.dart';
import '../clients/client_details_page.dart';

class BusinessHistoryPage extends StatelessWidget {
  final String shopId;
  const BusinessHistoryPage({super.key, required this.shopId});

  Future<List<Map<String, dynamic>>> _loadEvents() async {
    final List<Map<String, dynamic>> events = [];

    final supabase = sb.Supabase.instance.client;

    // Appointments
    final apptRes = await supabase
        .from('appointments')
        .select()
        .eq('shop_id', shopId)
        .order('scheduled_at', ascending: false)
        .limit(300);

    for (var data in apptRes) {
      final rawDate = data['scheduled_at'];
      final dt = rawDate != null ? DateTime.tryParse(rawDate.toString()) : null;
      events.add({
        'type': 'agendamento',
        'id': data['id'],
        'when': dt,
        'payload': data,
      });
    }

    // Payments (financial_transactions)
    try {
      final transRes = await supabase
          .from('financial_transactions')
          .select()
          .eq('shop_id', shopId)
          .order('data', ascending: false)
          .limit(200);

      for (var data in transRes) {
        final rawDate = data['data'] ?? data['createdAt'];
        final dt = rawDate != null ? DateTime.tryParse(rawDate.toString()) : null;
        events.add({
          'type': 'pagamento',
          'id': data['id'],
          'when': dt,
          'payload': {
            'amount': (data['valor'] as num?)?.toDouble()?.abs() ?? 0.0,
            'description': data['descricao'] ?? data['description'] ?? 'Transação',
            ...data,
          },
        });
      }
    } catch (_) {
      // ignore
    }

    // Sort by date desc
    events.sort((a, b) {
      final da = a['when'] as DateTime?;
      final db = b['when'] as DateTime?;
      if (da == null && db == null) return 0;
      if (da == null) return 1;
      if (db == null) return -1;
      return db.compareTo(da);
    });

    return events;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FD),
      appBar: AppBar(
        title: const Text("Histórico de Atividades",
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        backgroundColor: AppColors.primaryPurple,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _loadEvents(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(
                child:
                    CircularProgressIndicator(color: AppColors.primaryPurple));
          }
          if (!snap.hasData || snap.data!.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.history, size: 64, color: Colors.grey[300]),
                  const SizedBox(height: 16),
                  const Text('Nenhum evento registrado.',
                      style: TextStyle(color: Colors.grey, fontSize: 16)),
                ],
              ),
            );
          }

          final events = snap.data!;

          // Group by day
          final Map<DateTime, List<Map<String, dynamic>>> grouped = {};
          for (var e in events) {
            final when = e['when'] as DateTime?;
            final key = when != null
                ? DateTime(when.year, when.month, when.day)
                : DateTime(1970);
            grouped.putIfAbsent(key, () => []).add(e);
          }

          final keys = grouped.keys.toList();
          keys.sort((a, b) => b.compareTo(a)); // newest first

          return ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
            itemCount: keys.length,
            itemBuilder: (context, idx) {
              final day = keys[idx];
              final items = grouped[day]!;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildDateHeader(day),
                  const SizedBox(height: 10),
                  ...items.map((e) => _buildEventCard(e, context)),
                  const SizedBox(height: 20),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildDateHeader(DateTime date) {
    // Check if today/yesterday
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));

    String label;
    if (date == today) {
      label = "Hoje";
    } else if (date == yesterday) {
      label = "Ontem";
    } else {
      label = DateFormat('EEEE, dd MMM', 'pt_BR').format(date);
      // Capitalize first letter
      label = label[0].toUpperCase() + label.substring(1);
    }

    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 4),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.bold,
          color: Colors.grey[600],
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildEventCard(Map<String, dynamic> event, BuildContext context) {
    if (event['type'] == 'agendamento') {
      return _buildAppointmentCard(event, context);
    } else if (event['type'] == 'pagamento') {
      return _buildPaymentCard(event);
    }
    return const SizedBox.shrink();
  }

  Widget _buildAppointmentCard(
      Map<String, dynamic> event, BuildContext context) {
    final payload = event['payload'] as Map<String, dynamic>;
    final when = event['when'] as DateTime?;
    final time = when != null ? DateFormat('HH:mm').format(when) : '--:--';

    final status = (payload['status'] ?? 'agendado').toString().toLowerCase();
    final rawClientName = (payload['client_name'] ?? payload['client_nome'] ?? payload['cliente_nome'] ?? '').toString().trim();
    final clientName = (rawClientName.toLowerCase() == 'null' || rawClientName.isEmpty) ? 'Cliente' : rawClientName;
    final clientId = payload['clientId'] ?? payload['client_id'];
    final clientPhone = payload['client_phone'] ?? payload['cliente_telefone'];
    final rawServiceName = (payload['service_name'] ?? payload['servico_nome'] ?? '').toString().trim();
    final serviceName = (rawServiceName.toLowerCase() == 'null' || rawServiceName.isEmpty) ? 'Serviço' : rawServiceName;
    final val = double.tryParse(payload['total_value']?.toString() ?? payload['valor_total']?.toString() ?? payload['total_price']?.toString() ?? '0') ?? 0;

    // Classification Logic
    Color accentColor;
    IconData statusIcon;
    String statusLabel;
    bool isManual =
        (payload['clientId'] == null || payload['clientId'].toString().isEmpty);

    if (status == 'concluido' || status == 'finalizado' || status == 'pago') {
      accentColor = Colors.green;
      statusIcon = Icons.check_circle;
      statusLabel = "Concluído";
    } else if (status == 'cancelado') {
      accentColor = Colors.red;
      statusIcon = Icons.cancel;
      statusLabel = "Cancelado";
    } else {
      // Agendado / Efetuado
      if (isManual) {
        accentColor = Colors.orange;
        statusIcon = Icons.edit_note;
        statusLabel = "Manual";
      } else {
        accentColor = Colors.blue;
        statusIcon = Icons.smartphone;
        statusLabel = "App";
      }
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Container(
          decoration: BoxDecoration(
            border: Border(left: BorderSide(color: accentColor, width: 6)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Column(
                  children: [
                    Text(time,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 4),
                    Icon(statusIcon, size: 16, color: accentColor),
                  ],
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      GestureDetector(
                        onTap: clientId != null && clientId.isNotEmpty
                            ? () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => ClientDetailsPage(
                                      clientId: clientId,
                                      clientData: const {},
                                      onClose: () => Navigator.pop(context),
                                    ),
                                  ),
                                );
                              }
                            : null,
                        child: Text(
                          clientName,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            decoration: clientId != null && clientId.isNotEmpty
                                ? TextDecoration.underline
                                : null,
                            color: clientId != null && clientId.isNotEmpty
                                ? AppColors.primaryPurple
                                : Colors.black,
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(serviceName,
                          style:
                              TextStyle(color: Colors.grey[600], fontSize: 13)),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: accentColor.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              statusLabel,
                              style: TextStyle(
                                  color: accentColor,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold),
                            ),
                          ),
                          if (clientPhone != null && clientPhone.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(left: 8.0),
                              child: InkWell(
                                onTap: () async {
                                  final url =
                                      'https://wa.me/${clientPhone.replaceAll(RegExp(r'\D'), '')}';
                                  if (await canLaunchUrl(Uri.parse(url))) {
                                    await launchUrl(Uri.parse(url));
                                  } else {
                                    if (!context.mounted) return;
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                          content: Text(
                                              'Não foi possível abrir o WhatsApp para $clientPhone')),
                                    );
                                  }
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.green.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.chat_rounded,
                                          color: Colors.green, size: 12),
                                      SizedBox(width: 4),
                                      Text(
                                        'WhatsApp',
                                        style: TextStyle(
                                            color: Colors.green,
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$')
                          .format(val),
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: status == 'cancelado'
                            ? Colors.grey
                            : Colors.black87,
                        decoration: status == 'cancelado'
                            ? TextDecoration.lineThrough
                            : null,
                      ),
                    ),
                  ],
                )
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPaymentCard(Map<String, dynamic> event) {
    final payload = event['payload'] as Map<String, dynamic>;
    final when = event['when'] as DateTime?;
    final time = when != null ? DateFormat('HH:mm').format(when) : '--:--';
    final val = double.tryParse(payload['amount']?.toString() ?? '0') ?? 0;
    final desc = payload['description'] ?? 'Pagamento Avulso';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.green.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child:
                const Icon(Icons.attach_money, color: Colors.green, size: 20),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(desc,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 15)),
                Text("Pagamento • $time",
                    style: const TextStyle(color: Colors.grey, fontSize: 12)),
              ],
            ),
          ),
          Text(
            NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$').format(val),
            style: const TextStyle(
                fontWeight: FontWeight.bold, color: Colors.green),
          ),
        ],
      ),
    );
  }
}
