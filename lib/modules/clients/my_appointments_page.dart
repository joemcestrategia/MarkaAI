import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../core/theme/app_colors.dart';
import '../../core/services/mercado_pago_service.dart';
import '../../core/widgets/loading_page.dart';
import '../schedule/checkout_transparente_page.dart';
import '../schedule/booking_page.dart';
import '../schedule/booking_success_page.dart';
import '../../pages/pix_payment_page.dart';
import '../../core/services/client_verification_service.dart';
import 'dart:async';
import '../public/public_shop_page.dart';
import '../business/subscription_service.dart';
import '../../core/widgets/supabase_stream_widget.dart';

class MyAppointmentsPage extends StatefulWidget {
  const MyAppointmentsPage({super.key});

  @override
  State<MyAppointmentsPage> createState() => MyAppointmentsPageState();
}

class MyAppointmentsPageState extends State<MyAppointmentsPage>
    with SingleTickerProviderStateMixin {
  final currencyFormat = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
  Timer? _timerPolling;
  final Map<String, Future<Map<String, dynamic>?>> _shopDataCache = {};
  late TabController _tabController;

  /// BUG #1 FIX: Garante que o JWT do usuário está fresco antes de invocar Edge Functions.
  /// O token expira em ~1h. Se o cliente retorna ao app após um agendamento anterior,
  /// o token pode estar inválido, causando erro 401 "invalid JWT" na Edge Function.
  Future<bool> _ensureFreshSession() async {
    try {
      final response = await Supabase.instance.client.auth.refreshSession();
      return response.session != null;
    } catch (e) {
      debugPrint('⚠️ [Auth] Falha ao renovar sessão: $e');
      return false;
    }
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  /// Método público para forçar a atualização (ainda útil para disparar micro-ajustes se necessário)
  Future<void> refreshData() async {
    if (mounted) setState(() {});
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
    final today = DateTime(now.year, now.month, now.day);
    final apptDay = DateTime(appointmentDate.year, appointmentDate.month, appointmentDate.day);

    // Próximos: futuros ou hoje que não foram cancelados/concluídos
    return (appointmentDate.isAfter(now) || apptDay.isAtSameMomentAs(today)) &&
        !status.contains('cancelado') &&
        status != 'concluido';
  }

  double _getTotalValue(Map<String, dynamic> appointment) {
    return ((appointment['total_payable'] ??
            appointment['valor_com_desconto'] ??
            appointment['total_price'] ??
            appointment['total_value'] ??
            appointment['valor_total'] ??
            appointment['valor'] ??
            0) as num)
        .toDouble();
  }

  double _getPaidValue(Map<String, dynamic> appointment) {
    final meta = appointment['metadata'] as Map<String, dynamic>? ?? {};
    final metaPaid = (meta['valor_pago'] ?? 0) as num;
    final directPaid = (appointment['valor_pago'] ?? appointment['paid_amount'] ?? 0) as num;
    return (metaPaid > directPaid ? metaPaid : directPaid).toDouble();
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

  Future<Map<String, dynamic>?> _getCachedShopData(String shopId) {
    return _shopDataCache.putIfAbsent(shopId, () => _getShopData(shopId));
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
    final valorTotal = _getTotalValue(appointment);
    final valorPago = _getPaidValue(appointment);
    final valorRestante = valorTotal - valorPago;

    if (valorRestante <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Não há valor pendente para este agendamento.')),
      );
      return;
    }

    final shopId = appointment['shop_id'] as String?;
    if (shopId == null) {
      _showError('Loja não identificada no agendamento.');
      return;
    }

    // BUG #3 FIX: Verificar plano e configuração da loja antes de exibir opções de
    // pagamento online. Lojas no plano Free não possuem pagamento online habilitado.
    // Verificação assíncrona — exibe loading enquanto consulta o backend.
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    bool aceitaPix = false;
    bool aceitaCartao = false;

    try {
      final shopPlan = await SubscriptionService.getShopPlan(shopId);
      final planAllowsOnline =
          SubscriptionService.planSupportsOnlinePayment(shopPlan);

      if (planAllowsOnline) {
        final shopDoc = await Supabase.instance.client
            .from('shops')
            .select('config, mercadopago, mp_access_token')
            .eq('id', shopId)
            .maybeSingle();
        final config = (shopDoc?['config'] as Map<String, dynamic>?) ?? {};
        final mpData = (shopDoc?['mercadopago'] as Map<String, dynamic>?) ?? {};
        final mpToken = mpData['access_token']?.toString() ??
            shopDoc?['mp_access_token']?.toString() ?? '';
        final hasMpToken = mpToken.length > 20;
        aceitaPix = hasMpToken && config['pagamento_pix'] == true;
        aceitaCartao = hasMpToken && config['pagamento_cartao'] == true;
      }
    } catch (e) {
      debugPrint('❌ [PaymentOptions] Erro ao verificar plano da loja: $e');
    } finally {
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop(); // Close loading
      }
    }

    if (!mounted) return;

    if (!aceitaPix && !aceitaCartao) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Esta loja não oferece pagamento online. Pague diretamente no estabelecimento.'),
          duration: Duration(seconds: 4),
        ),
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
                if (aceitaPix)
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
                if (aceitaPix && aceitaCartao) const SizedBox(width: 12),
                if (aceitaCartao)
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

    if (!mounted) return;

    final navigator = Navigator.of(context, rootNavigator: true);
    navigator.push(
      MaterialPageRoute(
        builder: (_) => const AppLoadingPage(message: 'Gerando QR Code...'),
        fullscreenDialog: true,
      ),
    );

    try {
      if (shopId == null) {
        if (navigator.canPop()) navigator.pop();
        _showError('Erro ao processar pagamento: loja não configurada');
        return;
      }

      // BUG #1 FIX: Renovar o JWT antes de invocar a Edge Function de PIX.
      // O token expira em ~1h. Se o cliente retorna ao app após um agendamento anterior,
      // o token pode estar inválido, causando erro 401 "invalid JWT" na Edge Function.
      final sessionOk = await _ensureFreshSession();
      if (!sessionOk) {
        if (navigator.canPop()) navigator.pop();
        _showError(
            'Sessão expirada. Por favor, saia e entre novamente para realizar o pagamento.');
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

      if (navigator.canPop()) navigator.pop(); // fechar loading

      // Inicia polling de status
      _startPixMonitoring(appointment, paymentId, amount);

      if (!mounted) return;
      _isPixPageOpen = true;
      // Abre a mesma tela de PIX usada no checkout (rootNavigator para cobrir toda a tela,
      // incluindo a NavigationBar do ClientHomePage, assim como no checkout_page.dart)
      await Navigator.of(context, rootNavigator: true).push(
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
              if (_isPixPageOpen && mounted) {
                _isPixPageOpen = false;
                Navigator.of(context, rootNavigator: true).pop();
              }
              _updateAppointmentPayment(appointment, amount, 'Pix', paymentId);
              _navigateToPaymentSuccess(appointment);
            },
          ),
        ),
      );
      _isPixPageOpen = false;
      _timerPolling?.cancel(); // Cancel polling when user closes PIX page without paying
    } catch (e) {
      if (navigator.canPop()) navigator.pop(); // fechar loading
      _showError("Erro ao gerar PIX: $e");
    }
  }

  bool _isPixPageOpen = false;

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
            if (_isPixPageOpen) {
              _isPixPageOpen = false;
              Navigator.of(context, rootNavigator: true).pop(); // Fecha o modal do PIX somente se estiver aberto
              _navigateToPaymentSuccess(appointment);
            } else {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Pagamento aprovado!'),
                  backgroundColor: Colors.green,
                ),
              );
            }
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

    // BUG #2 FIX: Aplicar a taxa de cartão da loja ao valor antes de enviar ao gateway.
    // No fluxo de novo agendamento, checkout_page.dart calcula e passa o valor já com taxa.
    // Neste fluxo de pagamento posterior, 'amount' é o valor bruto do serviço sem taxa.
    final config = (shopData['config'] as Map<String, dynamic>?) ?? {};
    final cardTaxPercent = double.tryParse(
            (config['tax_percent'] ?? config['porcentagem_a_vista'] ?? '0')
                .toString()) ??
        0.0;
    final amountWithTax = cardTaxPercent > 0
        ? double.parse(
            (amount * (1 + cardTaxPercent / 100)).toStringAsFixed(2))
        : amount;
    debugPrint(
        '💳 [MyAppointments] Taxa cartão: $cardTaxPercent% | Valor: R\$$amount → R\$$amountWithTax');

    // Coleta dados do cartão (collectOnly: true) — o pagamento é processado aqui,
    // não no CheckoutReviewPage (que criaria um novo agendamento via pushAndRemoveUntil).
    final cardData = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (context) => CheckoutTransparentePage(
          shopId: shopId,
          valor: amountWithTax,
          orderId:
              "ORD-REMAINING-${appointment['id']}-${DateTime.now().millisecondsSinceEpoch}",
          serviceDoc: serviceData,
          professionalDoc: professionalData ?? shopData,
          date: appointmentDate,
          time: TimeOfDay.fromDateTime(appointmentDate),
          collectOnly: true,
          skipPlanCheck: true,
        ),
      ),
    );

    if (cardData == null || !mounted) return;

    // Cobrar o cartão e atualizar o agendamento existente
    final navigator = Navigator.of(context, rootNavigator: true);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final user = Supabase.instance.client.auth.currentUser!;
      final chargeResult = await MercadoPagoService.criarPagamentoCartao(
        shopId: shopId,
        cardToken: cardData['cardToken'],
        amount: amountWithTax,
        installments: cardData['installments'],
        email: user.email ?? 'cliente@markaai.com.br',
        description: "Pagamento - ${appointment['service_name'] ?? 'Serviço'}",
        cpf: cardData['cpf'],
        paymentMethodId: cardData['paymentMethodId'],
        issuerId: cardData['issuerId'],
      );

      navigator.pop();

      if (chargeResult['success'] == true) {
        await _updateAppointmentPayment(
          appointment,
          amount,
          'Cartão de Crédito',
          chargeResult['paymentId'].toString(),
        );
        _navigateToPaymentSuccess(appointment);
      } else {
        final errMsg = chargeResult['error']?.toString() ?? 'Pagamento recusado.';
        _showError(errMsg);
      }
    } catch (e) {
      navigator.pop();
      _showError('Erro ao processar cartão: $e');
    }
  }

  Future<void> _updateAppointmentPayment(
    Map<String, dynamic> appointment,
    double paidAmount,
    String method,
    String paymentId,
  ) async {
    final currentPaid = _getPaidValue(appointment);
    final newPaid = currentPaid + paidAmount;
    final valorTotal = _getTotalValue(appointment);
    final currentMeta = (appointment['metadata'] as Map<String, dynamic>?) ?? {};

    // Preserve 'concluido' status — don't downgrade already-completed appointments
    final currentStatus = appointment['status']?.toString().toLowerCase() ?? '';
    final newStatus = currentStatus == 'concluido' ? 'concluido' : 'confirmado';

    await Supabase.instance.client
        .from('appointments')
        .update({
      'payment_method': method,
      'status': newStatus,
      'valor_pago': newPaid,
      'paid_amount': newPaid,
      'remaining_amount': valorTotal - newPaid,
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
    final today = DateTime(now.year, now.month, now.day);
    final apptDay = DateTime(appointmentDate.year, appointmentDate.month, appointmentDate.day);

    // Não mostrar ações se já passou de hoje, foi cancelado ou concluído
    return (appointmentDate.isAfter(now) || apptDay.isAtSameMomentAs(today)) &&
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
      _showLatePolicyInfoModal(appointment['shop_name']?.toString() ?? 'o estabelecimento');
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
      await Supabase.instance.client
          .from('appointments')
          .update({
            'status': 'cancelado',
          })
          .eq('id', appointment['id']);

      if (mounted) Navigator.of(context, rootNavigator: true).pop(); // close loading
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
      Navigator.of(context, rootNavigator: true).pop(); // close loading
      _showError('Não foi possível cancelar: $e');
    }
  }

  bool _isLoadingCancel = false;

  // Exibe o modal com os detalhes e as ações do agendamento
  void _showAppointmentDetails(Map<String, dynamic> appointment, bool isUpcoming,
      String shopName, String shopLogo) {
    final valorTotal = _getTotalValue(appointment);
    final valorPago = _getPaidValue(appointment);
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
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Builder(
                  builder: (context) {
                    final method = (appointment['payment_method']?.toString() ?? 'local').toLowerCase();
                    IconData icon = Icons.payments;
                    if (method.contains('pix')) icon = Icons.qr_code;
                    else if (method.contains('cart') || method.contains('card')) icon = Icons.credit_card;
                    
                    return Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.primaryPurple.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(icon, color: AppColors.primaryPurple),
                    );
                  },
                ),
                title: const Text('Meio de Pagamento',
                    style: TextStyle(fontSize: 14, color: Colors.grey)),
                subtitle: Text(
                  (appointment['payment_method']?.toString() ?? 'Pagamento no Local'),
                  style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.black),
                ),
                trailing: Builder(
                  builder: (context) {
                    final pStatus = appointment['payment_status']?.toString().toLowerCase();
                    final isPaid = pStatus == 'pago' || valorPago >= (valorTotal - 0.05);
                    final color = isPaid ? Colors.green : Colors.orange;
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: color.withValues(alpha: 0.3)),
                      ),
                      child: Text(
                        isPaid ? "PAGO" : "PENDENTE",
                        style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12),
                      ),
                    );
                  },
                ),
              ),
              const Divider(height: 32),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Valor do serviço:',
                      style: TextStyle(color: Colors.grey)),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      if (appointment['total_price'] != null || appointment['discount_amount'] != null)
                        Builder(
                          builder: (context) {
                            final double original = double.tryParse((appointment['total_price'] ?? 0).toString()) ?? 0;
                            final double discount = double.tryParse((appointment['discount_amount'] ?? 0).toString()) ?? 0;
                            final double finalBase = double.tryParse((appointment['valor_com_desconto'] ?? valorTotal).toString()) ?? 0;
                            
                            // Tenta obter o desconto de várias formas para compatibilidade
                            double discountValue = discount > 0 ? discount : (original - finalBase);
                            double originalPrice = original > finalBase ? original : (finalBase + discountValue);

                            if (discountValue > 0.01) {
                              return Text(
                                "${currencyFormat.format(originalPrice)} (- ${currencyFormat.format(discountValue)})",
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey,
                                  decoration: TextDecoration.lineThrough,
                                ),
                              );
                            }
                            return const SizedBox.shrink();
                          }
                        ),
                      Text(currencyFormat.format(valorTotal),
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                    ],
                  ),
                ],
              ),
              if (appointment['coupon_applied'] == true) ...[
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Cupom aplicado:',
                        style: TextStyle(color: Colors.blue, fontSize: 13, fontWeight: FontWeight.w500)),
                    Text(
                      appointment['coupon_code']?.toString() ?? 'Ativo',
                      style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                  ],
                ),
              ],
              if (appointment['birthday_discount_applied'] == true) ...[
                const SizedBox(height: 8),
                const Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Presente aniversário:',
                        style: TextStyle(color: Colors.pink, fontSize: 13, fontWeight: FontWeight.w500)),
                    Text(
                      'Aplicado',
                      style: TextStyle(color: Colors.pink, fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                  ],
                ),
              ],
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
              if (valorRestante > 0 && !(appointment['status']?.toString().toLowerCase().contains('cancelado') ?? false)) ...[
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _showPaymentOptions(appointment);
                    },
                    icon: const Icon(Icons.payments_outlined),
                    label: const Text('PAGAR AGORA',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF25D366),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                    ),
                  ),
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
                          final validation = await ClientVerificationService.canModifyAppointment(appointment, isReschedule: true);
                          if (!validation['can']) {
                            if (!mounted) return;
                            _showLatePolicyInfoModal(appointment['shop_name']?.toString() ?? 'o estabelecimento');
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
                      Navigator.of(context, rootNavigator: true).pop(); // close loading

                      if (shopDoc != null) {
                        final slug = shopDoc['slug'];
                        if (slug != null && slug.toString().isNotEmpty) {
                          if (!mounted) return;
                          Navigator.of(context, rootNavigator: true).push(
                            MaterialPageRoute(
                              builder: (_) => PublicShopPage(
                                slug: slug,
                                isReschedule: true,
                                rescheduleAppointmentId: appointment['id'],
                                oldDate: DateTime.tryParse(appointment['scheduled_at']?.toString() ?? ''),
                                oldProfessional: appointment['professional_id']?.toString(),
                                oldServiceName: appointment['service_name']?.toString(),
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
                      if (mounted) {
                        Navigator.of(context, rootNavigator: true).pop();
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
    final professionalId = (appointment['professional_id'] ?? appointment['profissionalId']).toString();
    final serviceId = (appointment['service_id'] ?? appointment['servicoId']).toString();

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
      Navigator.of(context, rootNavigator: true).pop(); // close loading

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

      Navigator.of(context, rootNavigator: true).push(
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
        Navigator.of(context, rootNavigator: true).pop(); // fechar loading
        _showError('Erro ao carregar dados para reagendar: $e');
      }
    }
  }

  void _showLatePolicyInfoModal(String shopName) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.info_outline, color: AppColors.primaryPurple),
            SizedBox(width: 10),
            Text("Atenção", style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              "O prazo para cancelamento ou reagendamento via aplicativo expirou para este agendamento.",
              style: TextStyle(color: Colors.grey[800], fontSize: 15),
            ),
            const SizedBox(height: 16),
            Text(
              "Por favor, entre em contato direto com $shopName para verificar as possibilidades devido ao imprevisto.",
              style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 15),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.purple.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                "Uma justificativa plausível é o ideal nessas situações para que o estabelecimento possa te ajudar da melhor forma.",
                style: TextStyle(fontStyle: FontStyle.italic, color: AppColors.primaryPurple, fontSize: 13),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("ENTENDI", style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.primaryPurple)),
          ),
        ],
      ),
    );
  }

  void _showError(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: Colors.red),
      );
    }
  }

  void _navigateToPaymentSuccess(Map<String, dynamic> appointment) {
    if (!mounted) return;
    final ts = appointment['scheduled_at'];
    final date = ts is String ? DateTime.parse(ts) : ts as DateTime;
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(
        builder: (_) => BookingSuccessPage(
          serviceName: appointment['service_name'] ?? 'Serviço',
          professionalName: appointment['professional_name'] ?? 'Profissional',
          date: DateFormat('dd/MM/yyyy').format(date),
          time: DateFormat('HH:mm').format(date),
          isPaid: true,
          title: 'Pagamento Confirmado!',
          subtitle: 'Seu pagamento foi processado com sucesso!',
        ),
      ),
    );
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
      body: SupabaseStreamWidget<List<Map<String, dynamic>>>(
        stream: Supabase.instance.client
            .from('appointments')
            .stream(primaryKey: ['id'])
            .eq('client_id', user.id)
            .order('scheduled_at', ascending: false),
        isEmpty: (data) => data.isEmpty,
        emptyBuilder: (context) => const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.event_busy, size: 80, color: Colors.grey),
              SizedBox(height: 20),
              Text('Nenhum agendamento encontrado',
                  style: TextStyle(color: Colors.grey)),
            ],
          ),
        ),
        builder: (context, allAppointmentsRaw) {
          // Filtro de 30 dias aplicado no lado do cliente para flexibilidade máxima
          final now = DateTime.now();
          final cutoffDate = now.subtract(const Duration(days: 31)); // 31 para margem de segurança
          
          final allAppointments = allAppointmentsRaw.where((apt) {
            final ts = apt['scheduled_at'];
            if (ts == null) return false;
            final dt = ts is String ? DateTime.parse(ts) : ts as DateTime;
            return dt.isAfter(cutoffDate);
          }).toList();

          if (allAppointments.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.event_busy, size: 80, color: Colors.grey),
                  SizedBox(height: 20),
                  Text('Nenhum agendamento recente',
                      style: TextStyle(color: Colors.grey)),
                ],
              ),
            );
          }

          final upcomingAppointments = _filterAppointments(allAppointments, true);
          final historyAppointments = _filterAppointments(allAppointments, false);

          return TabBarView(
            controller: _tabController,
            children: [
              RefreshIndicator(
                onRefresh: refreshData,
                color: AppColors.primaryPurple,
                child: _buildAppointmentsList(upcomingAppointments, true),
              ),
              RefreshIndicator(
                onRefresh: refreshData,
                color: AppColors.primaryPurple,
                child: _buildAppointmentsList(historyAppointments, false),
              ),
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
    final valorTotal = _getTotalValue(appointment);
    final valorPago = _getPaidValue(appointment);
    final valorRestante = valorTotal - valorPago;
    final ts = appointment['scheduled_at'];
    DateTime appointmentDate = ts is String ? DateTime.parse(ts) : ts;

    return FutureBuilder<Map<String, dynamic>?>(
      future: _getCachedShopData(shopId),
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
                  const SizedBox(height: 12),
                  // Pagamento e Status
                  Row(
                    children: [
                      // Meio de Pagamento
                      Builder(
                        builder: (context) {
                          final method = (appointment['payment_method']?.toString() ?? 'local').toLowerCase();
                          IconData icon = Icons.payments;
                          String label = "Local";
                          Color color = Colors.grey;

                          if (method.contains('pix')) {
                            icon = Icons.qr_code;
                            label = "PIX";
                            color = const Color(0xFF00BFA5);
                          } else if (method.contains('cart') || method.contains('card')) {
                            icon = Icons.credit_card;
                            label = "Cartão";
                            color = AppColors.primaryPurple;
                          }

                          return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(icon, size: 14, color: color),
                                const SizedBox(width: 4),
                                Text(
                                  label,
                                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                      const SizedBox(width: 8),
                      // Status do Pagamento (Pago / Pendente)
                      Builder(
                        builder: (context) {
                          final isPaid = valorPago >= (valorTotal - 0.05); // Margem para erros de double
                          final color = isPaid ? Colors.green : Colors.orange;
                          final label = isPaid ? "PAGO" : "PGTO PENDENTE";

                          return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              label,
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                  const Divider(height: 32),
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
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                               if (appointment['total_price'] != null)
                                Builder(
                                  builder: (context) {
                                    final double original = double.tryParse(appointment['total_price'].toString()) ?? 0;
                                    // Use valor_com_desconto se disponível para comparar o desconto real (sem taxas)
                                    final double finalBase = double.tryParse((appointment['valor_com_desconto'] ?? valorTotal).toString()) ?? 0;
                                    final double discountValue = original - finalBase;
                                    
                                    if (discountValue > 0.01) {
                                      return Text(
                                        "${currencyFormat.format(original)} (- ${currencyFormat.format(discountValue)})",
                                        style: const TextStyle(
                                          fontSize: 10,
                                          color: Colors.grey,
                                          decoration: TextDecoration.lineThrough,
                                        ),
                                      );
                                    }
                                    return const SizedBox.shrink();
                                  }
                                ),
                              Text(currencyFormat.format(valorTotal),
                                  style:
                                      const TextStyle(fontWeight: FontWeight.bold)),
                            ],
                          ),
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
                  if (appointment['coupon_applied'] == true || appointment['birthday_discount_applied'] == true) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: [
                        if (appointment['coupon_applied'] == true)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.blue.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              "CUPOM: ${appointment['coupon_code'] ?? 'ATIVO'}",
                              style: const TextStyle(color: Colors.blue, fontSize: 9, fontWeight: FontWeight.bold),
                            ),
                          ),
                        if (appointment['birthday_discount_applied'] == true)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.pink.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              "ANIVERSÁRIO",
                              style: TextStyle(color: Colors.pink, fontSize: 9, fontWeight: FontWeight.bold),
                            ),
                          ),
                      ],
                    ),
                  ],
                  if (valorRestante > 0 && !(appointment['status']?.toString().toLowerCase().contains('cancelado') ?? false)) ...[
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
