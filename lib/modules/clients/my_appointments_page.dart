import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../core/theme/app_colors.dart';
import '../../core/services/mercado_pago_service.dart';
import '../schedule/checkout_transparente_page.dart';
import '../schedule/booking_page.dart';
import '../../pages/pix_payment_page.dart';
import '../../core/services/client_verification_service.dart';
import 'dart:async';
import '../public/public_shop_page.dart';

class MyAppointmentsPage extends StatefulWidget {
  const MyAppointmentsPage({super.key});

  @override
  State<MyAppointmentsPage> createState() => _MyAppointmentsPageState();
}

class _MyAppointmentsPageState extends State<MyAppointmentsPage>
    with SingleTickerProviderStateMixin {
  final currencyFormat = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
  Timer? _timerPolling;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _timerPolling?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  bool _isUpcoming(Map<String, dynamic> data) {
    final status = data['status']?.toString().toLowerCase() ?? '';
    final ts = data['scheduled_at'];
    DateTime? appointmentDate;
    if (ts is String) {
      appointmentDate = DateTime.parse(ts);
    } else if (ts is DateTime) {
      appointmentDate = ts;
    }
    
    if (appointmentDate == null) return false;
    
    final now = DateTime.now();

    // Próximos: futuros e não cancelados/concluídos
    return appointmentDate.isAfter(now) &&
        !status.contains('cancelado') &&
        status != 'concluido';
  }

  List<Map<String, dynamic>> _filterAppointments(
      List<Map<String, dynamic>> appointments, bool upcoming) {
    return appointments
        .where((apt) => upcoming ? _isUpcoming(apt) : !_isUpcoming(apt))
        .toList();
  }

  Future<Map<String, dynamic>> _getShopData(String shopId) async {
    try {
      final data = await Supabase.instance.client
          .from('shops')
          .select('nome, logo_url')
          .eq('id', shopId)
          .maybeSingle();

      if (data != null) {
        return {
          'nome': data['nome'] ?? 'Estabelecimento',
          'logo': data['logo_url'] ?? '',
        };
      }
    } catch (e) {
      debugPrint('Erro ao buscar dados da loja: $e');
    }
    return {'nome': 'Estabelecimento', 'logo': ''};
  }

  Color _getStatusColor(String? status) {
    switch (status?.toLowerCase()) {
      case 'confirmado':
      case 'concluido':
        return Colors.green;
      case 'pendente':
      case 'agendado':
        return Colors.orange;
      case 'cancelado':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  String _getStatusText(String? status) {
    switch (status?.toLowerCase()) {
      case 'confirmado':
        return 'Confirmado';
      case 'concluido':
        return 'Concluído';
      case 'pendente':
        return 'Pendente';
      case 'agendado':
        return 'Agendado';
      case 'cancelado':
        return 'Cancelado';
      default:
        return 'Desconhecido';
    }
  }

  Future<void> _showPaymentOptions(Map<String, dynamic> appointment) async {
    final valorTotal = (appointment['valor_total'] ?? appointment['valor'] ?? 0).toDouble();
    final valorPago = (appointment['valor_pago'] ?? 0).toDouble();
    final valorRestante = valorTotal - valorPago;

    if (valorRestante <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Não há valor pendente para este agendamento.')),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        height: MediaQuery.of(context).size.height * 0.4,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
        ),
        padding: const EdgeInsets.all(25),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  "Pagar Valor Restante",
                  style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primaryPurple),
                ),
                IconButton(
                    onPressed: () => Navigator.pop(ctx),
                    icon: const Icon(Icons.close))
              ],
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(
                color: AppColors.primaryPurple.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text("VALOR A PAGAR",
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  Text(
                    currencyFormat.format(valorRestante),
                    style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                        color: AppColors.primaryPurple),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            const Text("Escolha a forma de pagamento:",
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 15),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _processPixPayment(appointment, valorRestante);
                    },
                    icon: const Icon(Icons.qr_code),
                    label: const Text("PIX"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF25D366),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _processCardPayment(appointment, valorRestante);
                    },
                    icon: const Icon(Icons.credit_card),
                    label: const Text("CARTÃO"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryPurple,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
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

  Future<void> _processPixPayment(
      Map<String, dynamic> appointment, double amount) async {
    final shopId = appointment['shop_id'];

    try {
      if (shopId == null) {
        _showError('Erro ao processar pagamento: loja não configurada');
        return;
      }

      final user = Supabase.instance.client.auth.currentUser!;
      final result = await MercadoPagoService.gerarPix(
        shopId: shopId,
        amount: amount,
        emailCliente: user.email ?? "cliente@app.com",
        description:
            "Pagamento restante - ${appointment['service_name'] ?? 'Serviço'}",
      );

      final qrCode64 =
          result['point_of_interaction']['transaction_data']['qr_code_base64'];
      final copyPaste =
          result['point_of_interaction']['transaction_data']['qr_code'];
      final paymentId = result['id'].toString();

      if (!mounted) return;

      // Atualiza imediatamente o paymentId no agendamento para evitar perda caso o usuário feche o app
      try {
        final currentMeta = (appointment['metadata'] as Map<String, dynamic>?) ?? {};
        await Supabase.instance.client
            .from('appointments')
            .update({'metadata': {...currentMeta, 'payment_id': paymentId}})
            .eq('id', appointment['id']);
      } catch (e) {
        debugPrint('Erro ao salvar paymentId no restante: $e');
      }

      // Inicia polling de status
      _startPixMonitoring(appointment, paymentId, amount);

      // Abre a mesma tela de PIX usada no checkout
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PixPaymentPage(
            qrBase64: qrCode64,
            copyPaste: copyPaste,
            paymentId: paymentId,
            amount: amount,
            onManualCheck: () async {
              try {
                final status = await MercadoPagoService.verificarStatusPix(
                  shopId: shopId,
                  paymentId: paymentId,
                );
                return status == 'approved';
              } catch (e) {
                return false;
              }
            },
            onPaid: () {
              _timerPolling?.cancel();
              Navigator.pop(context);
              _updateAppointmentPayment(appointment, amount, 'Pix', paymentId);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Pagamento aprovado!'),
                  backgroundColor: Colors.green,
                ),
              );
            },
          ),
        ),
      );
    } catch (e) {
      _showError("Erro ao gerar PIX: $e");
    }
  }

  void _startPixMonitoring(
      Map<String, dynamic> appointment, String paymentId, double amount) {
    final shopId = appointment['shop_id'];

    _timerPolling?.cancel();
    _timerPolling = Timer.periodic(const Duration(seconds: 3), (timer) async {
      try {
        final status = await MercadoPagoService.verificarStatusPix(
          shopId: shopId,
          paymentId: paymentId,
        );

        if (status == 'approved') {
          timer.cancel();
          await _updateAppointmentPayment(
              appointment, amount, 'Pix', paymentId);
          if (mounted) {
            Navigator.pop(context); // Fecha o modal do PIX
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Pagamento aprovado!'),
                backgroundColor: Colors.green,
              ),
            );
          }
        }
      } catch (e) {
        debugPrint('Erro ao verificar status PIX: $e');
      }
    });
  }

  Future<void> _processCardPayment(
      Map<String, dynamic> appointment, double amount) async {
    final shopId = appointment['shop_id'] as String;
    
    final serviceData = await Supabase.instance.client
        .from('services')
        .select()
        .eq('id', appointment['service_id'])
        .maybeSingle();

    final shopData = await Supabase.instance.client
        .from('shops')
        .select()
        .eq('id', shopId)
        .maybeSingle();
        
    final professionalData = appointment['professional_id'] != null
        ? await Supabase.instance.client
            .from('employees')
            .select()
            .eq('id', appointment['professional_id'])
            .maybeSingle()
        : null;

    final ts = appointment['scheduled_at'];
    DateTime appointmentDate = ts is String ? DateTime.parse(ts) : ts;

    if (!mounted) return;
    if (serviceData == null || shopData == null) {
      _showError('Dados do serviço ou loja não encontrados.');
      return;
    }

    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (context) => CheckoutTransparentePage(
          shopId: shopId,
          valor: amount,
          orderId:
              "ORD-REMAINING-${appointment['id']}-${DateTime.now().millisecondsSinceEpoch}",
          serviceDoc: serviceData,
          professionalDoc: professionalData ?? shopData,
          date: appointmentDate,
          time: TimeOfDay.fromDateTime(appointmentDate),
          collectOnly: false,
          skipPlanCheck: true,
        ),
      ),
    );

    if (result != null && result['success'] == true) {
      await _updateAppointmentPayment(
        appointment,
        amount,
        'Cartão de Crédito',
        result['paymentId'].toString(),
      );
    }
  }

  Future<void> _updateAppointmentPayment(
    Map<String, dynamic> appointment,
    double paidAmount,
    String method,
    String paymentId,
  ) async {
    final currentMeta = (appointment['metadata'] as Map<String, dynamic>?) ?? {};
    final currentPaid = ((currentMeta['valor_pago'] ?? 0) as num).toDouble();
    final newPaid = currentPaid + paidAmount;
    final valorTotal = ((appointment['total_value'] ?? 0) as num).toDouble();

    await Supabase.instance.client
        .from('appointments')
        .update({
      'payment_method': method,
      'status': 'confirmado',
      'metadata': {
        ...currentMeta,
        'payment_id': paymentId,
        'valor_pago': newPaid,
        'restante_a_pagar': valorTotal - newPaid,
      },
    })
    .eq('id', appointment['id']);

    if (mounted) {
      setState(() {});
    }
  }

  bool _shouldShowActions(Map<String, dynamic> appointment) {
    final status = appointment['status']?.toString().toLowerCase() ?? '';
    final ts = appointment['scheduled_at'];
    DateTime? appointmentDate;
    if (ts is String) {
      appointmentDate = DateTime.parse(ts);
    } else if (ts is DateTime) {
      appointmentDate = ts;
    }
    
    if (appointmentDate == null) return false;
    final now = DateTime.now();

    // Não mostrar ações se já passou, foi cancelado ou concluído
    return appointmentDate.isAfter(now) &&
        !status.contains('cancelado') &&
        status != 'concluido';
  }

  // Determina se o cliente pode cancelar (se for gratuito)
  bool _canCancelAppointment(Map<String, dynamic> appointment) {
    final ts = appointment['scheduled_at'];
    DateTime? appointmentDate;
    if (ts is String) {
      appointmentDate = DateTime.parse(ts);
    } else if (ts is DateTime) {
      appointmentDate = ts;
    }
    
    if (appointmentDate == null) return false;
    final now = DateTime.now();

    // Verifica se o agendamento é futuro
    if (!appointmentDate.isAfter(now)) return false;

    return true;
  }

  Future<void> _cancelAppointment(Map<String, dynamic> appointment) async {
    if (!mounted) return;
    final confirm = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: EdgeInsets.fromLTRB(
              24, 24, 24, MediaQuery.of(ctx).padding.bottom + 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.cancel_outlined, color: Colors.red),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Cancelar Agendamento',
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Text(
                'Tem certeza que deseja cancelar este agendamento? Esta ação não poderá ser desfeita.',
                style: TextStyle(fontSize: 15, color: Colors.black87),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        side: BorderSide(color: Colors.grey.shade400),
                        foregroundColor: Colors.black87,
                      ),
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('VOLTAR',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  _isLoadingCancel ? const CircularProgressIndicator() : Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        elevation: 0,
                      ),
                      child: const Text('CANCELAR',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              )
            ],
          ),
        );
      },
    );

    if (confirm != true) return;

    // --- NOVA VALIDAÇÃO DE POLÍTICA ---
    final validation = await ClientVerificationService.canModifyAppointment(appointment);
    if (!validation['can']) {
      if (!mounted) return;
      _showError(validation['reason']);
      return;
    }

    // Loading indicator
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(child: CircularProgressIndicator()),
    );

    try {
      await Supabase.instance.client.functions.invoke('cancelAppointment', body: {
        'appointmentId': appointment['id'],
        'requestRefund': false,
      });

      if (mounted) Navigator.pop(context); // close loading
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Agendamento cancelado com sucesso!'),
          backgroundColor: Colors.green,
        ),
      );
      setState(() {}); // Refresh
    } catch (e) {
      if (!mounted) return;
      if (Navigator.canPop(context)) Navigator.pop(context);
      _showError('Não foi possível cancelar: $e');
    }
  }

  bool _isLoadingCancel = false;

  // Exibe o modal com os detalhes e as ações do agendamento
  void _showAppointmentDetails(Map<String, dynamic> appointment, bool isUpcoming,
      String shopName, String shopLogo) {
    final valorTotal = (appointment['valor_total'] ?? appointment['valor'] ?? 0).toDouble();
    final valorPago = (appointment['valor_pago'] ?? 0).toDouble();
    final valorRestante = valorTotal - valorPago;
    final ts = appointment['scheduled_at'];
    DateTime appointmentDate = ts is String ? DateTime.parse(ts) : ts;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: EdgeInsets.fromLTRB(
              24, 24, 24, MediaQuery.of(ctx).padding.bottom + 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Detalhes do Agendamento',
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: shopLogo.isNotEmpty
                          ? CachedNetworkImage(
                              imageUrl: shopLogo,
                              fit: BoxFit.cover,
                              errorWidget: (_, __, ___) => const Icon(
                                  Icons.store,
                                  color: AppColors.primaryPurple),
                            )
                          : const Icon(Icons.store,
                                  color: AppColors.primaryPurple),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          shopName,
                          style: const TextStyle(
                              fontSize: 14,
                              color: Colors.grey,
                              fontWeight: FontWeight.w600),
                        ),
                        Builder(
                          builder: (context) {
                            final rawServiceName = (appointment['service_name'] ?? appointment['servico_nome'] ?? '').toString().trim();
                            final serviceName = (rawServiceName.toLowerCase() == 'null' || rawServiceName.isEmpty) ? 'Serviço' : rawServiceName;
                            return Text(
                              serviceName,
                              style: const TextStyle(
                                  fontSize: 18, fontWeight: FontWeight.bold),
                            );
                          }
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.primaryPurple.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.calendar_today,
                      color: AppColors.primaryPurple),
                ),
                title: const Text('Data e Hora',
                    style: TextStyle(fontSize: 14, color: Colors.grey)),
                subtitle: Text(
                  '${DateFormat('dd/MM/yyyy').format(appointmentDate)} às ${DateFormat('HH:mm').format(appointmentDate)}',
                  style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.black),
                ),
              ),
              const Divider(height: 32),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Valor do serviço:',
                      style: TextStyle(color: Colors.grey)),
                  Text(currencyFormat.format(valorTotal),
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Total pago:',
                      style: TextStyle(color: Colors.grey)),
                  Text(
                    currencyFormat.format(valorPago),
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: valorPago > 0 ? Colors.green : Colors.grey),
                  ),
                ],
              ),
              if (valorRestante > 0) ...[
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Valor a pagar no local:',
                        style: TextStyle(
                            color: Colors.grey, fontWeight: FontWeight.bold)),
                    Text(
                      currencyFormat.format(valorRestante),
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, color: Colors.orange),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 32),
              if (isUpcoming && _shouldShowActions(appointment)) ...[
                Row(
                  children: [
                    if (_canCancelAppointment(appointment))
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () {
                            Navigator.pop(ctx);
                            _cancelAppointment(appointment);
                          },
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.red,
                            side: const BorderSide(color: Colors.red),
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                          child: const Text('CANCELAR',
                              style: TextStyle(fontWeight: FontWeight.bold)),
                        ),
                      ),
                    if (_canCancelAppointment(appointment))
                      const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () async {
                          // --- NOVA VALIDAÇÃO DE POLÍTICA ---
                          final validation = await ClientVerificationService.canModifyAppointment(appointment);
                          if (!validation['can']) {
                            if (!mounted) return;
                            _showError(validation['reason']);
                            return;
                          }

                          if (!mounted) return;
                          Navigator.pop(ctx);
                          // Reagendar usando a tela de agendamento ou escolher novo serviço
                          _promptRescheduleType(appointment, shopName);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primaryPurple,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text('REAGENDAR',
                            style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ] else ...[
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(ctx),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.grey[200],
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('VOLTAR',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                )
              ]
            ],
          ),
        );
      },
    );
  }

  Future<void> _promptRescheduleType(
      Map<String, dynamic> appointment, String shopName) async {
    final shopId = (appointment['shop_id'] ?? appointment['shopId']) as String;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: EdgeInsets.fromLTRB(
              24, 24, 24, MediaQuery.of(ctx).padding.bottom + 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Opções de Reagendamento',
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              const Text(
                'Você deseja reagendar para o mesmo serviço contratado, ou prefere explorar a loja e escolher um serviço diferente?',
                style: TextStyle(fontSize: 15, color: Colors.black87),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.grey[200],
                    foregroundColor: Colors.black87,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () {
                    Navigator.pop(ctx);
                    _rescheduleViaBookingPage(appointment);
                  },
                  child: const Text('MANTER MESMO SERVIÇO',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryPurple,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () async {
                    Navigator.pop(ctx);
                    showDialog(
                      context: context,
                      barrierDismissible: false,
                      builder: (ctx2) =>
                          const Center(child: CircularProgressIndicator()),
                    );

                    try {
                      final shopDoc = await Supabase.instance.client
                          .from('shops')
                          .select('slug')
                          .eq('id', shopId)
                          .maybeSingle();

                      if (!mounted) return;
                      Navigator.pop(context); // close loading

                      if (shopDoc != null) {
                        final slug = shopDoc['slug'];
                        if (slug != null && slug.toString().isNotEmpty) {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => PublicShopPage(
                                slug: slug,
                                isReschedule: true,
                                rescheduleAppointmentId: appointment['id'],
                              ),
                            ),
                          );
                        } else {
                          _showError('Link da loja indisponível.');
                        }
                      } else {
                        _showError('Loja não encontrada.');
                      }
                    } catch (e) {
                      if (mounted && Navigator.canPop(context)) {
                        Navigator.pop(context);
                      }
                      _showError('Erro ao carregar loja: $e');
                    }
                  },
                  child: const Text('MUDAR DE SERVIÇO',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _rescheduleViaBookingPage(Map<String, dynamic> appointment) async {
    final shopId = (appointment['shop_id'] ?? appointment['shopId']) as String;
    final professionalId = appointment['profissionalId'] as String;
    final serviceId = appointment['servicoId'] as String;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final supabase = Supabase.instance.client;
      // Fetch shop, employee and service
      final shopData = await supabase.from('shops').select().eq('id', shopId).maybeSingle();
      final profData = await supabase.from('employees').select().eq('id', professionalId).maybeSingle();
      final serviceData = await supabase.from('services').select().eq('id', serviceId).maybeSingle();

      if (!mounted) return;
      Navigator.pop(context); // close loading

      if (shopData == null || profData == null || serviceData == null) {
        String missing = '';
        if (shopData == null) missing += 'Loja ';
        if (profData == null) missing += 'Profissional ';
        if (serviceData == null) missing += 'Serviço ';
        _showError(
            'Não foi possível carregar os detalhes ($missing) para reagendar.');
        return;
      }

      final shopConfig = shopData['config'] as Map<String, dynamic>? ?? {};
      final intervalMinutes = shopConfig['intervalo_agenda_min'] ?? 60;
      final minAdvanceHours =
          shopConfig['limite_minimo_agendamento_horas'] ?? 7;

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => BookingTimePage(
            shop: shopData,
            serviceDoc: serviceData,
            professionalDoc: profData,
            shopConfig: shopConfig,
            intervalMinutes: intervalMinutes,
            minAdvanceHours: minAdvanceHours,
            isReschedule: true,
            appointmentId: appointment['id'],
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // fechar loading
        _showError('Erro ao carregar dados para reagendar: $e');
      }
    }
  }

  void _showError(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;

    if (user == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Meus Agendamentos'),
          backgroundColor: AppColors.primaryPurple,
          foregroundColor: Colors.white,
        ),
        body: const Center(child: Text('Você precisa estar logado')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Meus Agendamentos'),
        backgroundColor: AppColors.primaryPurple,
        foregroundColor: Colors.white,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          indicatorWeight: 3,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          labelStyle:
              const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          unselectedLabelStyle: const TextStyle(fontSize: 14),
          tabs: const [
            Tab(text: 'Próximos'),
            Tab(text: 'Histórico'),
          ],
        ),
      ),
      backgroundColor: const Color(0xFFF5F7FA),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: Supabase.instance.client
            .from('appointments')
            .stream(primaryKey: ['id'])
            .eq('client_id', user.id)
            .order('scheduled_at', ascending: false),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
             return Center(child: Text('Erro: ${snapshot.error}'));
          }

          final allAppointments = snapshot.data ?? [];
          if (allAppointments.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.event_busy, size: 80, color: Colors.grey),
                  SizedBox(height: 20),
                  Text('Nenhum agendamento encontrado',
                      style: TextStyle(color: Colors.grey)),
                ],
              ),
            );
          }

          final upcomingAppointments =
              _filterAppointments(allAppointments, true);
          final historyAppointments =
              _filterAppointments(allAppointments, false);

          return TabBarView(
            controller: _tabController,
            children: [
              _buildAppointmentsList(upcomingAppointments, true),
              _buildAppointmentsList(historyAppointments, false),
            ],
          );
        },
      ),
    );
  }

  Widget _buildAppointmentsList(
      List<Map<String, dynamic>> appointments, bool isUpcoming) {
    if (appointments.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isUpcoming ? Icons.event_available : Icons.history,
              size: 80,
              color: Colors.grey,
            ),
            const SizedBox(height: 20),
            Text(
              isUpcoming
                  ? 'Nenhum agendamento futuro'
                  : 'Nenhum histórico ainda',
              style: const TextStyle(color: Colors.grey, fontSize: 16),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: appointments.length,
      itemBuilder: (context, index) {
        final appointment = appointments[index];
        return _buildAppointmentCard(appointment, isUpcoming);
      },
    );
  }

  Widget _buildAppointmentCard(Map<String, dynamic> appointment, bool isUpcoming) {
    final shopId = appointment['shop_id'];
    final valorTotal = (appointment['valor_total'] ?? appointment['valor'] ?? 0).toDouble();
    final valorPago = (appointment['valor_pago'] ?? 0).toDouble();
    final valorRestante = valorTotal - valorPago;
    final ts = appointment['scheduled_at'];
    DateTime appointmentDate = ts is String ? DateTime.parse(ts) : ts;

    return FutureBuilder<Map<String, dynamic>>(
      future: _getShopData(shopId),
      builder: (context, shopSnapshot) {
        final shopData =
            shopSnapshot.data ?? {'nome': 'Carregando...', 'logo': ''};
        final shopName = shopData['nome'] as String;
        final shopLogo = shopData['logo'] as String;

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          elevation: 2,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => _showAppointmentDetails(
                appointment, isUpcoming, shopName, shopLogo),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header com logo e nome do estabelecimento
                  Row(
                    children: [
                      // Logo do estabelecimento
                      Container(
                        width: 50,
                        height: 50,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: shopLogo.isNotEmpty
                              ? CachedNetworkImage(
                                  imageUrl: shopLogo,
                                  fit: BoxFit.cover,
                                  placeholder: (_, __) => Container(
                                    color: AppColors.primaryPurple
                                        .withValues(alpha: 0.1),
                                    child: const Icon(Icons.store,
                                        color: AppColors.primaryPurple),
                                  ),
                                  errorWidget: (_, __, ___) => Container(
                                    color: AppColors.primaryPurple
                                        .withValues(alpha: 0.1),
                                    child: const Icon(Icons.store,
                                        color: AppColors.primaryPurple),
                                  ),
                                )
                              : Container(
                                  color: AppColors.primaryPurple
                                      .withValues(alpha: 0.1),
                                  child: const Icon(Icons.store,
                                      color: AppColors.primaryPurple),
                                ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      // Nome do estabelecimento e status
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              shopName,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Colors.grey,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Builder(
                              builder: (context) {
                                final rawServiceName = (appointment['service_name'] ?? appointment['servico_nome'] ?? '').toString().trim();
                                final serviceName = (rawServiceName.toLowerCase() == 'null' || rawServiceName.isEmpty) ? 'Serviço' : rawServiceName;
                                return Text(
                                  serviceName,
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                );
                              }
                            ),
                          ],
                        ),
                      ),
                      // Status badge
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: _getStatusColor(appointment['status'])
                              .withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          _getStatusText(appointment['status']),
                          style: TextStyle(
                            color: _getStatusColor(appointment['status']),
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // Data e hora
                  Row(
                    children: [
                      const Icon(Icons.calendar_today,
                          size: 16, color: Colors.grey),
                      const SizedBox(width: 8),
                      Text(
                        DateFormat('dd/MM/yyyy').format(appointmentDate),
                        style: const TextStyle(
                            color: Colors.grey, fontWeight: FontWeight.w500),
                      ),
                      const SizedBox(width: 16),
                      const Icon(Icons.access_time,
                          size: 16, color: Colors.grey),
                      const SizedBox(width: 8),
                      Text(
                        DateFormat('HH:mm').format(appointmentDate),
                        style: const TextStyle(
                            color: Colors.grey, fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                  const Divider(height: 24),
                  // Valores
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Valor Total:',
                              style:
                                  TextStyle(fontSize: 12, color: Colors.grey)),
                          Text(currencyFormat.format(valorTotal),
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold)),
                        ],
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Pago:',
                              style:
                                  TextStyle(fontSize: 12, color: Colors.grey)),
                          Text(
                            currencyFormat.format(valorPago),
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: valorPago > 0 ? Colors.green : Colors.grey,
                            ),
                          ),
                        ],
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Restante:',
                              style:
                                  TextStyle(fontSize: 12, color: Colors.grey)),
                          Text(
                            currencyFormat.format(valorRestante),
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: valorRestante > 0
                                  ? Colors.orange
                                  : Colors.green,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  if (isUpcoming && valorRestante > 0 && _shouldShowActions(appointment)) ...[
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () => _showPaymentOptions(appointment),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primaryPurple,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8)),
                        ),
                        child: const Text('PAGAR RESTANTE',
                            style: TextStyle(
                                fontSize: 12, fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
