import 'package:supabase_flutter/supabase_flutter.dart' as sb;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/theme/app_colors.dart';
import 'appointment_details_page.dart';

class BusinessHistoryPage extends StatefulWidget {
  final String shopId;
  final void Function(DateTime scheduledAt, String appointmentId)? onNavigateToSchedule;
  const BusinessHistoryPage({super.key, required this.shopId, this.onNavigateToSchedule});

  @override
  State<BusinessHistoryPage> createState() => _BusinessHistoryPageState();
}

class _BusinessHistoryPageState extends State<BusinessHistoryPage> {
  static List<Map<String, dynamic>>? _cachedEvents;
  static DateTime? _lastFetchTime;
  late Future<List<Map<String, dynamic>>> _eventsFuture;

  @override
  void initState() {
    super.initState();
    _eventsFuture = _loadEvents();
  }

  Future<void> _onRefresh() async {
    setState(() {
      _eventsFuture = _loadEvents(forceRefresh: true);
    });
    await _eventsFuture;
  }

  Future<List<Map<String, dynamic>>> _loadEvents({bool forceRefresh = false}) async {
    if (!forceRefresh && _cachedEvents != null && _lastFetchTime != null) {
      if (DateTime.now().difference(_lastFetchTime!).inMinutes < 5) {
        return _cachedEvents!;
      }
    }

    final List<Map<String, dynamic>> events = [];
    final supabase = sb.Supabase.instance.client;

    final limitDate = DateTime.now().subtract(const Duration(days: 30));

    // Appointments (com a mesma query do Schedule, para garantir dados completos)
    final apptRes = await supabase
        .from('appointments')
        .select('*, shop_id, professional_id, client_id, scheduled_at, duration_min, status, total_value, total_price, labor_value, valor_com_desconto, total_payable, discount_amount, paid_amount, remaining_amount, payment_method, payment_status, coupon_applied, coupon_code, coupon_discount_percent, birthday_discount_applied, birthday_discount_percent, metadata, service_id, client_name, client_phone, client_email, client_photo, service_name, professional_name')
        .eq('shop_id', widget.shopId)
        .neq('status', 'pre_reserva')
        .gte('created_at', limitDate.toUtc().toIso8601String())
        .order('created_at', ascending: false)
        .limit(300);

    // Enriquecimento: busca nome real de clientes onde client_name é um email
    final toFix = apptRes.where((a) {
      final n = (a['client_name'] ?? '').toString();
      return n.contains('@') && !n.contains(' ') && a['client_id'] != null;
    }).toList();
    if (toFix.isNotEmpty) {
      final ids = toFix.map((a) => a['client_id'].toString()).toSet().toList();
      try {
        final userRows = await supabase.from('users').select('id, name').inFilter('id', ids);
        final nameMap = <String, String>{};
        for (final r in userRows) {
          final n = (r['name'] ?? '').toString().trim();
          if (n.isNotEmpty && !n.contains('@')) nameMap[r['id'].toString()] = n;
        }
        for (final appt in toFix) {
          final rn = nameMap[appt['client_id'].toString()];
          if (rn != null) appt['client_name'] = rn;
        }
      } catch (_) {}
    }

    for (var data in apptRes) {
      final rawDate = data['created_at'];
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
          .eq('shop_id', widget.shopId)
          .gte('created_at', limitDate.toUtc().toIso8601String())
          .order('created_at', ascending: false)
          .limit(200);

      for (var data in transRes) {
        final rawDate = data['created_at'] ?? data['createdAt'] ?? data['data'];
        final dt = rawDate != null ? DateTime.tryParse(rawDate.toString()) : null;
        events.add({
          'type': 'pagamento',
          'id': data['id'],
          'when': dt,
          'payload': {
            'amount': (data['valor'] as num?)?.toDouble().abs() ?? 0.0,
            'description': data['descricao'] ?? data['description'] ?? 'Transação',
            ...data,
          },
        });
      }
    } catch (_) {
      // ignore
    }

    // Activity log (reagendamentos, pagamentos confirmados, cancelamentos)
    try {
      final actRes = await supabase
          .from('shop_activity_log')
          .select()
          .eq('shop_id', widget.shopId)
          .gte('created_at', limitDate.toUtc().toIso8601String())
          .order('created_at', ascending: false)
          .limit(300);

      for (final data in actRes) {
        final rawDate = data['created_at'];
        final dt = rawDate != null ? DateTime.tryParse(rawDate.toString()) : null;
        events.add({
          'type': 'atividade',
          'id': data['id'],
          'when': dt,
          'payload': Map<String, dynamic>.from(data as Map),
        });
      }
    } catch (_) {
      // ignore — tabela pode não existir ainda
    }

    // Sort by date desc (mais recentes no topo)
    events.sort((a, b) {
      final da = a['when'] as DateTime?;
      final db = b['when'] as DateTime?;
      if (da == null && db == null) return 0;
      if (da == null) return 1;
      if (db == null) return -1;
      return db.compareTo(da);
    });

    _cachedEvents = events;
    _lastFetchTime = DateTime.now();

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
        future: _eventsFuture,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(
                child:
                    CircularProgressIndicator(color: AppColors.primaryPurple));
          }
          if (!snap.hasData || snap.data!.isEmpty) {
            return RefreshIndicator(
              onRefresh: _onRefresh,
              child: Stack(
                children: [
                  ListView(), // Necessário para acionar o RefreshIndicator
                  Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.history, size: 64, color: Colors.grey[300]),
                        const SizedBox(height: 16),
                        const Text('Nenhum evento registrado.',
                            style: TextStyle(color: Colors.grey, fontSize: 16)),
                      ],
                    ),
                  ),
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
          keys.sort((a, b) => b.compareTo(a)); // desc

          return RefreshIndicator(
            onRefresh: _onRefresh,
            child: ListView.builder(
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
            ),
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
    } else if (event['type'] == 'atividade') {
      return _buildAtividadeCard(event);
    }
    return const SizedBox.shrink();
  }

  Widget _buildAtividadeCard(Map<String, dynamic> event) {
    final payload = event['payload'] as Map<String, dynamic>;
    final when = event['when'] as DateTime?;
    final time = when != null ? DateFormat('HH:mm').format(when) : '--:--';
    final eventType = (payload['event_type'] as String? ?? '').toLowerCase();
    final description = payload['description'] as String? ?? '';
    final actorName = payload['actor_name'] as String? ?? '';

    final bool isReschedule = eventType == 'reagendamento';
    final bool isPayment = eventType == 'pagamento_confirmado';
    final bool isCancel = eventType == 'agendamento_cancelado';

    final Color accentColor = isPayment
        ? Colors.green
        : isCancel
            ? Colors.red
            : isReschedule
                ? AppColors.primaryPurple
                : Colors.orange;

    final IconData icon = isPayment
        ? Icons.credit_card_rounded
        : isCancel
            ? Icons.cancel_outlined
            : isReschedule
                ? Icons.swap_horiz_rounded
                : Icons.info_outline;

    final String badge = isPayment
        ? 'PAGAMENTO'
        : isCancel
            ? 'CANCELAMENTO'
            : isReschedule
                ? 'REAGENDAMENTO'
                : 'ATUALIZAÇÃO';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accentColor.withValues(alpha: 0.25), width: 1.5),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 6, offset: const Offset(0, 2)),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 18, color: accentColor),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: accentColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(badge,
                          style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: accentColor)),
                    ),
                    const SizedBox(width: 8),
                    Text(time, style: const TextStyle(fontSize: 11, color: Colors.grey)),
                  ],
                ),
                const SizedBox(height: 4),
                Text(description,
                    style: const TextStyle(fontSize: 12, color: Colors.black87),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis),
                if (actorName.isNotEmpty)
                  Text(actorName,
                      style: const TextStyle(fontSize: 10, color: Colors.grey)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAppointmentCard(
      Map<String, dynamic> event, BuildContext context) {
    final payload = event['payload'] as Map<String, dynamic>;
    final when = event['when'] as DateTime?;
    final time = when != null ? DateFormat('HH:mm').format(when) : '--:--';

    final status = (payload['status'] ?? 'agendado').toString().toLowerCase();
    final rawClientName = (payload['client_name'] ?? payload['client_nome'] ?? payload['cliente_nome'] ?? '').toString().trim();
    final rawClientNameSanitized = (rawClientName.toLowerCase() == 'null' || rawClientName.isEmpty) ? '' : rawClientName;
    final clientName = (rawClientNameSanitized.contains('@') && !rawClientNameSanitized.contains(' '))
        ? 'Cliente' // enriquecimento falhou (rede?) — fallback neutro
        : (rawClientNameSanitized.isNotEmpty ? rawClientNameSanitized : 'Cliente');
    final clientPhone = payload['client_phone'] ?? payload['cliente_telefone'];
    final rawServiceName = (payload['service_name'] ?? payload['servico_nome'] ?? '').toString().trim();
    final serviceName = (rawServiceName.toLowerCase() == 'null' || rawServiceName.isEmpty) ? 'Serviço' : rawServiceName;
    final rawProfName = (payload['professional_name'] ?? payload['profissional_nome'] ?? payload['professionalName'] ?? '').toString().trim();
    final professionalDisplay = (rawProfName.toLowerCase() == 'null' || rawProfName.isEmpty) ? '' : rawProfName;
    final paymentMethod = (payload['payment_method'] ?? '').toString().trim();
    final double pagoHist = double.tryParse(payload['paid_amount']?.toString() ?? payload['valor_pago']?.toString() ?? '0') ?? 0;

    // HELPERS DE DESCONTO
    bool temDesconto(Map<String, dynamic> data) {
      bool hasBirthday = data['birthday_discount_applied'] == true;
      bool hasCoupon = data['coupon_applied'] == true;
      double discountAmt = double.tryParse(data['discount_amount']?.toString() ?? '0') ?? 0;
      return hasBirthday || hasCoupon || discountAmt > 0.01;
    }

    double valorFinal(Map<String, dynamic> data) {
      final double totalPrice = double.tryParse(data['total_price']?.toString() ?? '0') ?? 0;
      final double totalPayable = double.tryParse(data['total_payable']?.toString() ?? '0') ?? 0;
      final double valorCDesc = double.tryParse(data['valor_com_desconto']?.toString() ?? '0') ?? 0;
      final double discountAmt = double.tryParse(data['discount_amount']?.toString() ?? '0') ?? 0;
      final bool hasBirthday = data['birthday_discount_applied'] == true;
      final bool hasCoupon = data['coupon_applied'] == true;

      if (totalPayable > 0 && totalPrice > 0 && totalPayable < totalPrice - 0.01) return totalPayable;
      if (valorCDesc > 0 && totalPrice > 0 && valorCDesc < totalPrice - 0.01) return valorCDesc;
      if (discountAmt > 0.01 && totalPrice > 0) return totalPrice - discountAmt;
      if (hasBirthday && totalPrice > 0) {
        final pct = double.tryParse(data['birthday_discount_percent']?.toString() ?? '0') ?? 0;
        if (pct > 0) return totalPrice * (1 - pct / 100);
      }
      if (hasCoupon && totalPrice > 0) {
        final pct = double.tryParse(data['coupon_discount_percent']?.toString() ?? '0') ?? 0;
        if (pct > 0) return totalPrice * (1 - pct / 100);
      }
      if (totalPayable > 0) return totalPayable;
      if (valorCDesc > 0) return valorCDesc;
      if (totalPrice > 0) return totalPrice;
      return double.tryParse(data['total_value']?.toString() ?? data['valor_total']?.toString() ?? '0') ?? 0;
    }

    List<Map<String, dynamic>> labelDesconto(Map<String, dynamic> data) {
      List<Map<String, dynamic>> tags = [];
      if (data['birthday_discount_applied'] == true) {
        tags.add({"text": "🎂 ANIVERSÁRIO", "color": Colors.pink});
      }
      if (data['coupon_applied'] == true && data['coupon_code'] != null) {
        tags.add({"text": "🏷️ CUPOM: ${data['coupon_code']}", "color": Colors.blue});
      }
      double discountAmt = double.tryParse(data['discount_amount']?.toString() ?? '0') ?? 0;
      if (tags.isEmpty && discountAmt > 0.01) {
        tags.add({"text": "🏷️ DESCONTO", "color": Colors.orange});
      }
      return tags;
    }

    final val = valorFinal(payload);
    final double originalValue = double.tryParse(payload['total_price']?.toString() ?? payload['total_value']?.toString() ?? payload['valor_total']?.toString() ?? '0') ?? 0;
    final double discAmt = originalValue > val + 0.01 ? originalValue - val : 0;
    final String pStatHist = payload['payment_status']?.toString().toLowerCase() ?? '';
    final bool quitadoHist = pStatHist == 'pago' || (pagoHist >= val && val > 0.01) || status == 'concluido' || status == 'finalizado' || status == 'pago';
    final Color payColorHist = status == 'cancelado' ? Colors.grey.shade400 : (quitadoHist ? Colors.green : (pagoHist > 0.01 ? Colors.orange : Colors.grey.shade500));
    final String payTextHist = status == 'cancelado' ? 'CANCELADO' : (quitadoHist ? 'PAGO' : (pagoHist > 0.01 ? 'ADIANTADO' : 'PGTO. PENDENTE'));

    // Classification Logic
    Color accentColor;
    IconData statusIcon;
    String statusLabel;
    
    debugPrint('origin: ${payload['origin']}');
    debugPrint('client_id: ${payload['client_id']}');
    debugPrint('created_by: ${payload['created_by']}');

    final String? clientId = payload['client_id'];
    final String? createdBy = payload['created_by'];

    final bool isManual = (clientId == null || clientId.toString().isEmpty) ||
                          (createdBy == 'dono');

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

    return GestureDetector(
      onTap: () {
        final scheduledAtRaw = payload['scheduled_at'];
        final scheduledAt = scheduledAtRaw != null ? DateTime.tryParse(scheduledAtRaw.toString()) : null;
        final appointmentId = event['id']?.toString() ?? '';
        if (widget.onNavigateToSchedule != null && scheduledAt != null && appointmentId.isNotEmpty) {
          widget.onNavigateToSchedule!(scheduledAt, appointmentId);
        } else {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => AppointmentDetailsPage(
                appointmentDoc: payload,
              ),
            ),
          );
        }
      },
      child: Container(
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
                      Text(
                        clientName,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: Colors.black,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(serviceName,
                          style:
                              TextStyle(color: Colors.grey[600], fontSize: 13)),
                      if (professionalDisplay.isNotEmpty) ...[  
                        const SizedBox(height: 3),
                        Row(
                          children: [
                            Icon(Icons.content_cut_rounded, size: 10, color: Colors.grey.shade400),
                            const SizedBox(width: 3),
                            Flexible(
                              child: Text(
                                professionalDisplay,
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                                style: TextStyle(color: Colors.grey.shade500, fontSize: 11),
                              ),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
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
                          // ✅ Tag confirmado via WhatsApp
                          if (payload['confirmed_via_whatsapp'] == true)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFF22C55E).withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: const Color(0xFF22C55E).withValues(alpha: 0.3)),
                              ),
                              child: const Text(
                                '✅ CONFIRMOU',
                                style: TextStyle(
                                  color: Color(0xFF16A34A),
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          // 💳 Forma de Pagamento
                          if (paymentMethod.isNotEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppColors.primaryPurple.withValues(alpha: 0.05),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: AppColors.primaryPurple.withValues(alpha: 0.2)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.payments_outlined, size: 10, color: AppColors.primaryPurple),
                                  const SizedBox(width: 3),
                                  Text(paymentMethod.toUpperCase(), style: const TextStyle(color: AppColors.primaryPurple, fontSize: 10, fontWeight: FontWeight.bold)),
                                ],
                              ),
                            ),
                          if (clientPhone != null && clientPhone.isNotEmpty)
                            InkWell(
                              onTap: () async {
                                final url = 'https://wa.me/${clientPhone.replaceAll(RegExp(r'\D'), '')}';
                                if (await canLaunchUrl(Uri.parse(url))) {
                                  await launchUrl(Uri.parse(url));
                                } else {
                                  if (!context.mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('Não foi possível abrir o WhatsApp para $clientPhone')),
                                  );
                                }
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.green.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.chat_rounded, color: Colors.green, size: 12),
                                    SizedBox(width: 4),
                                    Text('WhatsApp', style: TextStyle(color: Colors.green, fontSize: 10, fontWeight: FontWeight.bold)),
                                  ],
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
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (temDesconto(payload) && originalValue > val + 0.01) ...[  
                      Text(
                        NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$').format(originalValue),
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.grey.shade400,
                          decoration: TextDecoration.lineThrough,
                        ),
                      ),
                      Text(
                        '- ${NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$').format(discAmt)}',
                        style: const TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF16A34A),
                        ),
                      ),
                    ],
                    Text(
                      NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$').format(val),
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: status == 'cancelado' ? Colors.grey : Colors.black87,
                        decoration: status == 'cancelado' ? TextDecoration.lineThrough : null,
                      ),
                    ),
                    if (temDesconto(payload))
                      ...labelDesconto(payload).map((tag) =>
                        Container(
                          margin: const EdgeInsets.only(top: 3),
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: (tag['color'] as Color).withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: (tag['color'] as Color).withValues(alpha: 0.3)),
                          ),
                          child: Text(tag['text'] as String, style: TextStyle(color: tag['color'] as Color, fontSize: 8, fontWeight: FontWeight.bold)),
                        ),
                      ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(
                        color: payColorHist.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        payTextHist,
                        style: TextStyle(color: payColorHist, fontWeight: FontWeight.bold, fontSize: 8),
                      ),
                    ),
                  ],
                )
              ],
            ),
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
