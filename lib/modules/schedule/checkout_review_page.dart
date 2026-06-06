import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import '../../core/theme/app_colors.dart';
import '../../core/services/mercado_pago_service.dart';
import 'package:markaai/modules/schedule/booking_success_page.dart';

class CheckoutReviewPage extends StatefulWidget {
  final Map<String, dynamic> paymentData;
  final Map<String, dynamic> serviceDoc;
  final Map<String, dynamic> professionalDoc;
  final DateTime date;
  final String time;
  final String shopId;
  final String orderId;
  final bool showProfessional;
  final Map<String, dynamic>? selectedVariation;

  const CheckoutReviewPage({
    super.key,
    required this.paymentData,
    required this.serviceDoc,
    required this.professionalDoc,
    required this.date,
    required this.time,
    required this.shopId,
    required this.orderId,
    this.showProfessional = true,
    this.selectedVariation,
  });

  @override
  State<CheckoutReviewPage> createState() => _CheckoutReviewPageState();
}

class _CheckoutReviewPageState extends State<CheckoutReviewPage> {
  bool _isProcessing = false;

  Future<void> _confirmBooking() async {
    setState(() => _isProcessing = true);

    try {
      // Forçar refresh do JWT para evitar erro 401 na Edge Function
      final sessionResult = await Supabase.instance.client.auth.refreshSession();
      if (sessionResult.session == null) {
        throw Exception('Sua sessão expirou. Faça login novamente para continuar.');
      }

      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) throw Exception('Usuário não autenticado');

      final result = await MercadoPagoService.criarPagamentoCartao(
        shopId: widget.shopId,
        cardToken: widget.paymentData['cardToken'],
        amount: (widget.paymentData['valor'] as num).toDouble(),
        installments: widget.paymentData['installments'],
        email: user.email ?? 'cliente@markaai.com.br',
        description: "Reserva: ${widget.serviceDoc['name'] ?? 'Serviço'}",
        cpf: widget.paymentData['cpf'],
        paymentMethodId: widget.paymentData['paymentMethodId'],
        issuerId: widget.paymentData['issuerId'],
      );

      if (result['success'] == true) {
        await _saveAppointment(result['paymentId']?.toString() ?? '');
      } else {
        _showError(_getFriendlyErrorMessage(result['error']?.toString(),
            statusDetail: result['status_detail']?.toString()));
      }
    } catch (e) {
      _showError('Erro ao confirmar reserva: $e');
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _saveAppointment(String paymentId) async {
    final user = Supabase.instance.client.auth.currentUser!;
    final bookingDate = DateTime(
      widget.date.year,
      widget.date.month,
      widget.date.day,
      int.parse(widget.time.split(':')[0]),
      int.parse(widget.time.split(':')[1]),
    );

    final int durationMin =
        int.tryParse(widget.serviceDoc['duration_min']?.toString() ?? '30') ?? 30;
    final DateTime endDate = bookingDate.add(Duration(minutes: durationMin));

    // Fetch user profile for phone and photo
    String clientName = user.userMetadata?['full_name']?.toString().trim().isNotEmpty == true
        ? user.userMetadata!['full_name'].toString().trim()
        : (user.userMetadata?['name']?.toString().trim().isNotEmpty == true
            ? user.userMetadata!['name'].toString().trim()
            : 'Cliente');
    String? clientPhone;
    String? clientPhoto = user.userMetadata?['avatar_url']?.toString() ?? user.userMetadata?['picture']?.toString();
    try {
      final userDoc = await Supabase.instance.client
          .from('users')
          .select('phone, photo_url, name')
          .eq('id', user.id)
          .maybeSingle();
      if (userDoc != null) {
        clientPhone = userDoc['phone']?.toString();
        if (clientPhone != null && clientPhone.trim().isEmpty) clientPhone = null;
        final dbPhoto = userDoc['photo_url']?.toString();
        if ((clientPhoto == null || clientPhoto.isEmpty) && dbPhoto != null && dbPhoto.isNotEmpty) {
          clientPhoto = dbPhoto;
        }
        final dbName = userDoc['name']?.toString();
        if (dbName != null && dbName.trim().isNotEmpty) clientName = dbName.trim();
      }
    } catch (_) {}

    await Supabase.instance.client.from('appointments').insert({
      'shop_id': widget.shopId,
      'client_id': user.id,
      'client_name': clientName,
      'client_email': user.email ?? 'cliente@markaai.com.br',
      'client_phone': clientPhone,
      'client_photo': clientPhoto,
      'service_id': widget.serviceDoc['id'],
      'service_name': widget.selectedVariation != null
          ? '${widget.serviceDoc['name'] ?? 'Serviço'} (${widget.selectedVariation!['name']})'
          : widget.serviceDoc['name'] ?? 'Serviço',
      'professional_id': widget.professionalDoc['id'],
      'professional_name': widget.professionalDoc['name'] ??
          widget.professionalDoc['nome'] ??
          'Profissional',
      'scheduled_at': bookingDate.toIso8601String(),
      'status': 'confirmado',
      'payment_method': 'Cartão de Crédito',
      'total_price': widget.paymentData['valor'],
      'total_value': widget.paymentData['valor'],
      'duration_min': durationMin,
      'end_at': endDate.toIso8601String(),
      'metadata': {'payment_id': paymentId},
    });

    if (mounted) {
      final durationMin =
          int.tryParse(widget.serviceDoc['duration_min']?.toString() ?? '60') ?? 60;
      final shopInfo = await Supabase.instance.client
          .from('shops')
          .select('name, address, address_number, city')
          .eq('id', widget.shopId)
          .maybeSingle();
      final sName = shopInfo?['name']?.toString() ?? '';
      final addrParts = [
        shopInfo?['address'],
        shopInfo?['address_number'] != null ? 'nº ${shopInfo!['address_number']}' : null,
        shopInfo?['city'],
      ].where((e) => e != null && e.toString().isNotEmpty).join(', ');
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(
          builder: (_) => BookingSuccessPage(
            serviceName: widget.serviceDoc['name'] ?? 'Serviço',
            professionalName: widget.professionalDoc['name'] ?? 'Profissional',
            date: DateFormat('dd/MM/yyyy').format(widget.date),
            time: widget.time,
            isPaid: true,
            shopName: sName,
            shopAddress: addrParts,
            durationMin: durationMin,
          ),
        ),
        (route) => false,
      );
    }
  }

  String _getFriendlyErrorMessage(String? code, {String? statusDetail}) {
    final lowerCode = code?.toLowerCase() ?? '';

    if (lowerCode.contains('invalid transaction amount') ||
        lowerCode.contains('amount must be greater')) {
      return 'O valor desta reserva é inferior ao mínimo permitido para pagamentos online.';
    }

    if (lowerCode.contains('expiration_month') ||
        lowerCode.contains('expiration_year') ||
        lowerCode.contains('invalid parameter expiration')) {
      return 'A data de expiração do cartão parece estar incorreta. Verifique o mês e o ano.';
    }

    if (lowerCode.contains('security_code') ||
        lowerCode.contains('cvv') ||
        lowerCode.contains('cvc')) {
      return 'O código de segurança (CVV) do cartão é inválido. Verifique o número atrás do cartão.';
    }

    if (lowerCode.contains('card_number') ||
        lowerCode.contains('invalid parameter card_number')) {
      return 'O número do cartão é inválido ou incompleto.';
    }

    if (statusDetail != null) {
      switch (statusDetail) {
        case 'cc_rejected_bad_filled_card_number':
          return 'O número do cartão é inválido. Verifique o número digitado.';
        case 'cc_rejected_bad_filled_date':
          return 'A data de expiração está incorreta. Verifique o mês e o ano.';
        case 'cc_rejected_bad_filled_other':
          return 'Alguns dados do cartão estão incorretos. Por favor, revise.';
        case 'cc_rejected_bad_filled_security_code':
          return 'O código de segurança (atrás do cartão) é inválido. Verifique o número digitado.';
        case 'cc_rejected_blacklist':
          return 'Não foi possível processar este cartão por regras de segurança. Tente usar outro.';
        case 'cc_rejected_call_for_authorize':
          return 'O pagamento não foi autorizado pelo seu banco. Entre em contato com eles para liberar a transação.';
        case 'cc_rejected_card_disabled':
          return 'Este cartão está desativado. Verifique com seu banco ou use outro cartão.';
        case 'cc_rejected_card_error':
          return 'Ocorreu um erro ao processar o cartão. Tente novamente em instantes.';
        case 'cc_rejected_duplicated_payment':
          return 'Identificamos um pagamento idêntico recente. Verifique se a cobrança já não foi realizada.';
        case 'cc_rejected_high_risk':
          return 'O sistema de segurança recusou o pagamento. Tente outro cartão ou método de pagamento.';
        case 'cc_rejected_insufficient_amount':
          return 'Saldo ou limite insuficiente no cartão. Verifique com seu banco.';
        case 'cc_rejected_invalid_installments':
          return 'Este cartão não aceita o número de parcelas selecionado.';
        case 'cc_rejected_max_attempts':
          return 'Limite de tentativas excedido para este cartão. Tente usar outro ou aguarde um momento.';
        case 'cc_rejected_other_reason':
          return 'A operadora do cartão não autorizou o pagamento por algum motivo interno. Verifique com seu banco.';
      }
    }

    if (code != null) {
      switch (code) {
        case '205':
        case 'E301':
          return 'O número do cartão é inválido ou não foi informado.';
        case '208':
        case '209':
        case '325':
        case '326':
          return 'A data de expiração do cartão é inválida.';
        case '224':
        case 'E302':
          return 'O código de segurança (CVV) é inválido.';
        case '221':
        case '316':
          return 'O nome do titular do cartão é inválido ou incompleto.';
        case '324':
          return 'O CPF informado é inválido.';
        case '310':
          return 'O valor não é válido para este cartão.';
      }
    }

    return 'Não conseguimos processar seu pagamento. Verifique os dados do cartão e tente novamente.';
  }

  void _showError(String message) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.error_outline, color: Colors.red),
            SizedBox(width: 8),
            Text('Ops! No Pagamento'),
          ],
        ),
        content: Text(
          message,
          style: const TextStyle(fontSize: 16),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('ENTENDI',
                style: TextStyle(
                    color: AppColors.primaryPurple,
                    fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('dd/MM/yyyy');
    final secondaryColor = Colors.grey[600];

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: const Text('Revisar Reserva',
            style: TextStyle(color: Colors.black, fontWeight: FontWeight.w700)),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new,
              color: Colors.black, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 24),
                  _buildSectionHeader('Detalhes da Reserva'),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: _cardDecoration(),
                    child: Column(
                      children: [
                        _buildEnhancedReviewItem(
                          icon: Icons.auto_awesome,
                          label: 'Serviço',
                          value: widget.serviceDoc['name'] ?? 'Serviço',
                        ),
                        if (widget.showProfessional) ...[
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 16),
                            child: Divider(height: 1),
                          ),
                          _buildEnhancedReviewItem(
                            icon: Icons.person_outline,
                            label: 'Profissional',
                            value: widget.professionalDoc['name'] ??
                                'Profissional',
                          ),
                        ],
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 16),
                          child: Divider(height: 1),
                        ),
                        _buildEnhancedReviewItem(
                          icon: Icons.calendar_today_outlined,
                          label: 'Data e Hora',
                          value:
                              '${dateFormat.format(widget.date)} às ${widget.time}',
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  _buildSectionHeader('Pagamento'),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: _cardDecoration(),
                    child: Column(
                      children: [
                        _buildEnhancedReviewItem(
                          icon: Icons.credit_card_outlined,
                          label: 'Método Pagamento',
                          value: 'Cartão de Crédito',
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: AppColors.primaryPurple
                                    .withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(Icons.credit_card,
                                  color: AppColors.primaryPurple, size: 20),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '•••• •••• •••• ${widget.paymentData['lastFour']}',
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: 1.2,
                                    ),
                                  ),
                                  Text(
                                    '${widget.paymentData['installments']}x de R\$ ${(widget.paymentData['valor'] / widget.paymentData['installments']).toStringAsFixed(2)}',
                                    style: TextStyle(
                                        color: secondaryColor, fontSize: 13),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  offset: const Offset(0, -4),
                  blurRadius: 10,
                ),
              ],
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(24),
                topRight: Radius.circular(24),
              ),
            ),
            child: SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Valor Total',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w500),
                      ),
                      Text(
                        'R\$ ${widget.paymentData['valor'].toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          color: AppColors.primaryPurple,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      onPressed: _isProcessing ? null : _confirmBooking,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primaryPurple,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: _isProcessing
                          ? const SizedBox(
                              height: 24,
                              width: 24,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : const Text(
                              'Confirmar e Reservar',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
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

  BoxDecoration _cardDecoration() {
    return BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.03),
          blurRadius: 10,
          offset: const Offset(0, 4),
        ),
      ],
      border: Border.all(color: Colors.white),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title.toUpperCase(),
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w800,
        color: Colors.grey[500],
        letterSpacing: 1.2,
      ),
    );
  }

  Widget _buildEnhancedReviewItem({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: Colors.grey[400]),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(fontSize: 13, color: Colors.grey[500]),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
