import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter/services.dart';
import '../../core/theme/app_colors.dart';
import '../../core/services/mercado_pago_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class TransactionDetailsPage extends StatefulWidget {
  final Map<String, dynamic> appointmentData;

  const TransactionDetailsPage({
    super.key,
    required this.appointmentData,
  });

  @override
  State<TransactionDetailsPage> createState() => _TransactionDetailsPageState();
}

class _TransactionDetailsPageState extends State<TransactionDetailsPage> {
  bool _isLoading = false;
  Map<String, dynamic>? _fullTransaction;
  Map<String, dynamic>? _advanceTransaction;
  Map<String, dynamic>? _completionTransaction;
  Map<String, dynamic>? _legacyTransaction;
  bool _isManualCompletion = false;
  String? _errorMsg;

  final _fmt = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

  @override
  void initState() {
    super.initState();
    _fetchDeepDetails();
  }

  /// Retorna o valor final do serviço após descontos aplicados.
  double _resolveDisplayTotal(Map<String, dynamic> data) {
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
    return totalPrice;
  }

  double _resolveDiscountAmount(Map<String, dynamic> data, double original, double finalAmt) {
    final double discountAmt = double.tryParse(data['discount_amount']?.toString() ?? '0') ?? 0;
    if (discountAmt > 0.01) return discountAmt;
    
    final hasBirthday = data['birthday_discount_applied'] == true;
    final hasCoupon = data['coupon_applied'] == true;
    if (hasBirthday) {
      final pct = double.tryParse(data['birthday_discount_percent']?.toString() ?? '0') ?? 0;
      if (pct > 0) return original * (pct / 100);
    }
    if (hasCoupon) {
      final pct = double.tryParse(data['coupon_discount_percent']?.toString() ?? '0') ?? 0;
      if (pct > 0) return original * (pct / 100);
    }
    
    if (original > 0 && finalAmt > 0 && finalAmt < original - 0.01) {
      final double possibleDiscount = original - finalAmt;
      final double paidAmount = double.tryParse(data['paid_amount']?.toString() ?? '0') ?? 0;
      final double remainingAmount = double.tryParse(data['remaining_amount']?.toString() ?? '0') ?? 0;
      
      // Impede interpretar o pagamento parcial (sinal) ou o restante como se fosse um desconto
      if ((possibleDiscount - paidAmount).abs() < 0.01 || (possibleDiscount - remainingAmount).abs() < 0.01) {
        return 0;
      }
      return possibleDiscount;
    }
    return 0;
  }


  Map<String, dynamic> _mapMpData(Map<String, dynamic>? mpData, String paymentId) {
    if (mpData == null) return {'id': paymentId, 'status': 'pending', 'amount': 0.0, 'method': 'Desconhecido'};
    return {
      'id': paymentId,
      'status': mpData['status']?.toString().toLowerCase() ?? 'pending',
      'method': mpData['payment_method_id']?.toString() ?? 'Desconhecido',
      'amount': mpData['transaction_amount'] != null ? (mpData['transaction_amount'] as num).toDouble() : 0.0,
      'payment_date': mpData['date_approved']?.toString() ?? mpData['date_created']?.toString(),
    };
  }

  Future<void> _fetchDeepDetails() async {
    final metadata = widget.appointmentData['metadata'] as Map?;
    final advancePaymentId = metadata?['advance_payment_id']?.toString();
    final completionPaymentId = metadata?['completion_payment_id']?.toString();
    final legacyPaymentId = metadata?['payment_id']?.toString() ?? widget.appointmentData['payment_id']?.toString();

    if ((advancePaymentId == null || advancePaymentId.isEmpty) && 
        (legacyPaymentId == null || legacyPaymentId.isEmpty)) {
      setState(() {
        _errorMsg = "ID de transação não encontrado no agendamento.";
      });
      return;
    }

    setState(() => _isLoading = true);
    try {
      final double finalAmount = _resolveDisplayTotal(widget.appointmentData);
      
      if (advancePaymentId != null && advancePaymentId.isNotEmpty) {
        final mpData1 = await MercadoPagoService.obterDetalhesPagamento(shopId: widget.appointmentData['shop_id'].toString(), paymentId: advancePaymentId);
        _advanceTransaction = _mapMpData(mpData1, advancePaymentId);
      }
      
      if (completionPaymentId != null && completionPaymentId.isNotEmpty) {
        if (completionPaymentId == 'manual') {
          _isManualCompletion = true;
          
          // Tenta descobrir o valor do segundo pagamento
          final double valorSinal = double.tryParse(widget.appointmentData['valor_sinal']?.toString() ?? '0') ?? 0;
          final double paidAmount = double.tryParse(widget.appointmentData['paid_amount']?.toString() ?? '0') ?? 0;
          final double rest = finalAmount - valorSinal;
          
          _completionTransaction = {
            'id': 'manual',
            'status': 'approved',
            'method': metadata?['completion_payment_method'] ?? 'Presencial/Manual',
            'amount': rest > 0 ? rest : (paidAmount > valorSinal ? paidAmount - valorSinal : 0.0),
            'payment_date': metadata?['completion_paid_at'] ?? widget.appointmentData['pago_em'],
          };
        } else {
          final mpData2 = await MercadoPagoService.obterDetalhesPagamento(shopId: widget.appointmentData['shop_id'].toString(), paymentId: completionPaymentId);
          _completionTransaction = _mapMpData(mpData2, completionPaymentId);
        }
      }
      
      if (_advanceTransaction == null && _completionTransaction == null && legacyPaymentId != null && legacyPaymentId.isNotEmpty) {
        // Tenta buscar no Mercado Pago por external_reference para "resgatar" os dois pagamentos
        final payments = await MercadoPagoService.buscarPagamentosPorReferencia(
            shopId: widget.appointmentData['shop_id'].toString(), 
            externalReference: widget.appointmentData['id'].toString());
        
        if (payments != null && payments.isNotEmpty) {
          if (payments.length >= 2) {
            // A API de busca retorna sort=date_created&criteria=desc (mais novo primeiro)
            final oldTx = payments.last as Map<String, dynamic>; // mais antigo (sinal)
            final newTx = payments.first as Map<String, dynamic>; // mais novo (restante)
            
            _advanceTransaction = _mapMpData(oldTx, oldTx['id']?.toString() ?? '');
            _completionTransaction = _mapMpData(newTx, newTx['id']?.toString() ?? '');
          } else {
             // Só encontrou um, trata como legado normal
             final tx = payments.first as Map<String, dynamic>;
             _legacyTransaction = _mapMpData(tx, tx['id']?.toString() ?? legacyPaymentId);
          }
        } else {
          // Fallback se a busca não retornar nada
          final mpDataLegacy = await MercadoPagoService.obterDetalhesPagamento(shopId: widget.appointmentData['shop_id'].toString(), paymentId: legacyPaymentId);
          _legacyTransaction = _mapMpData(mpDataLegacy, legacyPaymentId);
        }
      }
      
      // Cria _fullTransaction baseando no que temos, para não quebrar outras partes
      var baseTx = _legacyTransaction ?? _advanceTransaction;
      if (baseTx != null) {
        _fullTransaction = {
          'id': baseTx['id'],
          'status': baseTx['status'],
          'method': baseTx['method'],
          'amount': baseTx['amount'],
          'paid_amount': double.tryParse(widget.appointmentData['paid_amount']?.toString() ?? '0') ?? 0.0,
          'payment_date': baseTx['payment_date'],
          'created_at': widget.appointmentData['created_at'],
          'scheduled_at': widget.appointmentData['scheduled_at'],
        };
      } else if (_completionTransaction != null) {
         _fullTransaction = {
          'id': _completionTransaction!['id'],
          'status': _completionTransaction!['status'],
          'method': _completionTransaction!['method'],
          'amount': _completionTransaction!['amount'],
          'paid_amount': double.tryParse(widget.appointmentData['paid_amount']?.toString() ?? '0') ?? 0.0,
          'payment_date': _completionTransaction!['payment_date'],
          'created_at': widget.appointmentData['created_at'],
          'scheduled_at': widget.appointmentData['scheduled_at'],
        };
      }

    } catch (e) {
      setState(() => _errorMsg = "Erro ao conectar com a operadora: ");
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _shareSummary() {
    if (_fullTransaction == null) return;

    final data = widget.appointmentData;
    final date = DateFormat('dd/MM/yyyy HH:mm').format(DateTime.parse(_fullTransaction!['scheduled_at']));
    final double originalPrice = double.tryParse(data['total_price']?.toString() ?? '0') ?? 0;
    final double finalAmount = _fullTransaction!['amount'] as double;
    final double paidAmount = _fullTransaction!['paid_amount'] as double;
    final double discountAmt = _resolveDiscountAmount(data, originalPrice, finalAmount);
    final status = _fullTransaction!['status'].toString().toUpperCase();
    final id = _fullTransaction!['id'];
    final bool hasBirthday = data['birthday_discount_applied'] == true;
    final bool hasCoupon = data['coupon_applied'] == true;

    final buffer = StringBuffer();
    buffer.writeln("📌 *Comprovante de Transação - MarkaAI*");
    buffer.writeln("Cliente: ${data['client_name'] ?? 'Cliente'}");
    buffer.writeln("Serviço: ${data['service_name'] ?? 'Serviço'}");
    buffer.writeln("Data: $date");
    if (discountAmt > 0.01) {
      buffer.writeln("Preço original: ${_fmt.format(originalPrice)}");
      if (hasBirthday) buffer.writeln("🎂 Desconto aniversário: -${_fmt.format(discountAmt)}");
      if (hasCoupon) buffer.writeln("🏷️ Cupom ${data['coupon_code'] ?? ''}: -${_fmt.format(discountAmt)}");
    }
    buffer.writeln("Valor final: ${_fmt.format(finalAmount)}");
    buffer.writeln("Valor pago: ${_fmt.format(paidAmount)}");
    final remaining = finalAmount - paidAmount;
    if (remaining > 0.01) buffer.writeln("Restante: ${_fmt.format(remaining)}");
    buffer.writeln("Status: $status");
    buffer.writeln("---");
    buffer.writeln("ID Transação: $id");
    buffer.writeln("---");
    buffer.writeln("_Emitido via MarkaAI Business_");

    Share.share(buffer.toString());
  }

  void _copyTechnicalData() {
    if (_fullTransaction == null) return;
    Clipboard.setData(ClipboardData(text: _fullTransaction.toString()));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Dados técnicos copiados para o clipboard.")),
    );
  }

  Future<void> _processRefund() async {
    final method = _fullTransaction?['method']?.toString().toLowerCase() ?? '';
    final isCard = method.contains('cartão') || method.contains('credit');

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Confirmar Reembolso?"),
        content: Text(isCard
          ? "O estorno será solicitado automaticamente à operadora do cartão. Esta ação é irreversível."
          : "Para pagamentos via PIX, você deve realizar a devolução manualmente via banco. Deseja marcar este agendamento como REEMBOLSADO no sistema?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("CANCELAR")),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text("CONFIRMAR"),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isLoading = true);
    try {
      if (isCard) {
        await Supabase.instance.client.functions.invoke('refund-payment', body: {
          'payment_id': _fullTransaction!['id'],
          'shop_id': widget.appointmentData['shop_id'],
        });
      }

      await Supabase.instance.client
          .from('appointments')
          .update({'status': 'reembolsado'})
          .eq('id', widget.appointmentData['id']);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Reembolso processado com sucesso."), backgroundColor: Colors.green),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Erro ao processar reembolso: $e"), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FB),
      appBar: AppBar(
        title: const Text("Detalhes da Transação", style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.share_outlined),
            onPressed: _shareSummary,
          ),
        ],
      ),
      body: _isLoading
        ? const Center(child: CircularProgressIndicator(color: AppColors.primaryPurple))
        : _errorMsg != null
          ? _buildErrorView()
          : _buildMainView(),
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.orange),
            const SizedBox(height: 16),
            Text(_errorMsg!, textAlign: TextAlign.center, style: const TextStyle(fontSize: 16)),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("VOLTAR"),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildMainView() {
    final data = widget.appointmentData;
    final status = _fullTransaction?['status']?.toString().toLowerCase() ?? 'pending';
    final isApproved = status == 'approved' || status == 'accredited';
    final statusLabel = isApproved
        ? "PAGAMENTO APROVADO"
        : (status == 'rejected' ? "PAGAMENTO RECUSADO" : "AGUARDANDO / PENDENTE");

    final double originalPrice = double.tryParse(data['total_price']?.toString() ?? '0') ?? 0;
    final double finalAmount = _resolveDisplayTotal(data);
    final double paidAmount = double.tryParse(data['paid_amount']?.toString() ?? '0') ?? 0;
    final double valorSinal = double.tryParse(data['valor_sinal']?.toString() ?? '0') ?? 0;
    final double remaining = finalAmount - paidAmount;
    final double discountAmt = _resolveDiscountAmount(data, originalPrice, finalAmount);
    final bool hasDiscount = discountAmt > 0.01;
    final bool hasBirthday = data['birthday_discount_applied'] == true;
    final bool hasCoupon = data['coupon_applied'] == true;
    final bool isAdvancePayment = valorSinal > 0.01 || (paidAmount > 0.01 && remaining > 0.01);

    return SingleChildScrollView(
      child: Column(
        children: [
          // ── CABEÇALHO GRADIENTE ──
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 24),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [AppColors.primaryPurple, Color(0xFF4A148C)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Column(
              children: [
                // Preço original riscado (se houver desconto)
                if (hasDiscount) ...[
                  Text(
                    _fmt.format(originalPrice),
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.5),
                      fontSize: 16,
                      decoration: TextDecoration.lineThrough,
                      decorationColor: Colors.white54,
                    ),
                  ),
                  const SizedBox(height: 4),
                ],
                Text(
                  hasDiscount ? "VALOR COM DESCONTO" : "VALOR TOTAL",
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.2),
                ),
                const SizedBox(height: 6),
                Text(
                  _fmt.format(finalAmount),
                  style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.w900),
                ),
                // Badges de desconto
                if (hasBirthday || hasCoupon) ...[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    children: [
                      if (hasBirthday)
                        _buildHeaderBadge(
                          icon: Icons.cake_outlined,
                          label: () {
                            final pct = double.tryParse(data['birthday_discount_percent']?.toString() ?? '0') ?? 0;
                            return pct > 0 ? "-${pct.toStringAsFixed(0)}% ANIVERSÁRIO" : "ANIVERSÁRIO";
                          }(),
                          color: Colors.pink,
                        ),
                      if (hasCoupon)
                        _buildHeaderBadge(
                          icon: Icons.confirmation_number_outlined,
                          label: "CUPOM: ${data['coupon_code'] ?? 'ATIVO'}",
                          color: Colors.blue,
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(30),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(isApproved ? Icons.check_circle : Icons.warning, color: Colors.white, size: 18),
                      const SizedBox(width: 8),
                      Text(statusLabel, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                    ],
                  ),
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── BREAKDOWN FINANCEIRO ──
                _buildInfoCard("RESUMO FINANCEIRO", [
                  _buildDetailRow("Preço original do serviço", _fmt.format(originalPrice)),
                  if (hasDiscount) ...[
                    if (hasBirthday)
                      _buildDetailRow(
                        "🎂 Desconto aniversário",
                        "- ${_fmt.format(discountAmt)}",
                        valueColor: Colors.pink,
                      ),
                    if (hasCoupon)
                      _buildDetailRow(
                        "🏷️ Cupom ${data['coupon_code'] ?? ''}",
                        "- ${_fmt.format(discountAmt)}",
                        valueColor: Colors.blue,
                      ),
                    if (!hasBirthday && !hasCoupon)
                      _buildDetailRow("Desconto aplicado", "- ${_fmt.format(discountAmt)}", valueColor: Colors.orange),
                    _buildDividerRow(),
                    _buildDetailRow("Valor final com desconto", _fmt.format(finalAmount), bold: true),
                  ],
                  _buildDividerRow(),
                  _buildDetailRow(
                    isAdvancePayment ? "Total já pago" : "Valor pago",
                    _fmt.format(paidAmount),
                    valueColor: Colors.green,
                    bold: true,
                  ),
                  if (remaining > 0.01)
                    _buildDetailRow("Restante a cobrar", _fmt.format(remaining), valueColor: Colors.red, bold: true),
                  if (remaining <= 0.01)
                    _buildDetailRow("Situação", "QUITADO ✓", valueColor: Colors.green, bold: true),
                ]),

                if (isAdvancePayment) ...[
                  const SizedBox(height: 16),
                  _buildInfoCard("DETALHES DO ADIANTAMENTO (SINAL)", [
                    _buildDetailRow("Valor do sinal pago", _fmt.format(valorSinal > 0 ? valorSinal : paidAmount), valueColor: Colors.orange, bold: true),
                    _buildDetailRow("Status do pagamento", status.toUpperCase(), valueColor: isApproved ? Colors.green : Colors.orange),
                    if (data['payment_id'] != null)
                      _buildDetailRow("ID Transação MP", data['payment_id'].toString(), isCopyable: true),
                    Builder(builder: (context) {
                      final paymentDate = _fullTransaction?['payment_date']?.toString() ?? data['pago_em']?.toString();
                      if (paymentDate == null || paymentDate.isEmpty) return const SizedBox.shrink();
                      String formattedDate = paymentDate;
                      try {
                        formattedDate = DateFormat('dd/MM/yyyy HH:mm').format(DateTime.parse(paymentDate));
                      } catch (_) {}
                      return _buildDetailRow("Pago em", formattedDate);
                    }),
                  ]),
                ],

                const SizedBox(height: 16),

                // ── INFORMAÇÕES DA TRANSAÇÃO ──
                if (_legacyTransaction != null)
                  _buildInfoCard("INFORMAÇÕES DA TRANSAÇÃO", [
                    _buildDetailRow("ID Operação", _legacyTransaction!['id'], isCopyable: true),
                    _buildDetailRow("Método de pagamento", _legacyTransaction!['method']),
                    _buildDetailRow("Valor", _fmt.format(_legacyTransaction!['amount']), bold: true),
                    _buildDetailRow("Status da operadora", _legacyTransaction!['status'].toString().toUpperCase()),
                    Builder(builder: (context) {
                      final paymentDate = _legacyTransaction!['payment_date']?.toString() ?? data['pago_em']?.toString();
                      if (paymentDate == null || paymentDate.isEmpty) return const SizedBox.shrink();
                      String formattedDate = paymentDate;
                      try {
                        formattedDate = DateFormat('dd/MM/yyyy HH:mm').format(DateTime.parse(paymentDate));
                      } catch (_) {}
                      return _buildDetailRow("Data do pagamento", formattedDate);
                    }),
                  ]),

                if (_advanceTransaction != null)
                  _buildInfoCard("TRANSAÇÃO 1 — ADIANTAMENTO (SINAL)", [
                    _buildDetailRow("ID Operação", _advanceTransaction!['id'], isCopyable: true),
                    _buildDetailRow("Método de pagamento", _advanceTransaction!['method']),
                    _buildDetailRow("Status da operadora", _advanceTransaction!['status'].toString().toUpperCase(), valueColor: _advanceTransaction!['status'] == 'approved' ? Colors.green : Colors.orange),
                    _buildDetailRow("Valor", _fmt.format(_advanceTransaction!['amount']), bold: true),
                    Builder(builder: (context) {
                      final paymentDate = _advanceTransaction!['payment_date']?.toString();
                      if (paymentDate == null || paymentDate.isEmpty) return const SizedBox.shrink();
                      String formattedDate = paymentDate;
                      try {
                        formattedDate = DateFormat('dd/MM/yyyy HH:mm').format(DateTime.parse(paymentDate));
                      } catch (_) {}
                      return _buildDetailRow("Data do pagamento", formattedDate);
                    }),
                  ]),

                if (_advanceTransaction != null) const SizedBox(height: 16),

                if (_completionTransaction != null)
                  _buildInfoCard(_isManualCompletion ? "PAGAMENTO DO RESTANTE (PRESENCIAL/MANUAL)" : "TRANSAÇÃO 2 — PAGAMENTO DO RESTANTE (APP)", [
                    if (!_isManualCompletion)
                      _buildDetailRow("ID Operação", _completionTransaction!['id'], isCopyable: true),
                    _buildDetailRow("Método de pagamento", _completionTransaction!['method']),
                    _buildDetailRow("Status", _completionTransaction!['status'].toString().toUpperCase(), valueColor: _completionTransaction!['status'] == 'approved' ? Colors.green : Colors.orange),
                    _buildDetailRow("Valor", _fmt.format(_completionTransaction!['amount']), bold: true),
                    Builder(builder: (context) {
                      final paymentDate = _completionTransaction!['payment_date']?.toString();
                      if (paymentDate == null || paymentDate.isEmpty) return const SizedBox.shrink();
                      String formattedDate = paymentDate;
                      try {
                        formattedDate = DateFormat('dd/MM/yyyy HH:mm').format(DateTime.parse(paymentDate));
                      } catch (_) {}
                      return _buildDetailRow("Data do pagamento", formattedDate);
                    }),
                  ]),
                const SizedBox(height: 16),

                // ── AUDITORIA ──
                _buildInfoCard("AUDITORIA DE SISTEMA", [
                  if (_fullTransaction!['created_at'] != null)
                    _buildDetailRow(
                      "Criado em",
                      DateFormat('dd/MM/yyyy HH:mm:ss').format(DateTime.parse(_fullTransaction!['created_at'])),
                    ),
                  _buildDetailRow(
                    "Agendado para",
                    DateFormat('dd/MM/yyyy HH:mm:ss').format(DateTime.parse(_fullTransaction!['scheduled_at'])),
                  ),
                  _buildDetailRow("ID Agendamento", widget.appointmentData['id']?.toString() ?? '-', isCopyable: true),
                  _buildDetailRow("Origem", "Agendamento Online Cliente"),
                ]),

                const SizedBox(height: 24),

                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _copyTechnicalData,
                    icon: const Icon(Icons.code),
                    label: const Text("COPIAR DADOS TÉCNICOS (JSON)"),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      side: const BorderSide(color: Colors.grey),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _processRefund,
                    icon: const Icon(Icons.refresh),
                    label: const Text("SOLICITAR REEMBOLSO / ESTORNO"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red.shade700,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      elevation: 0,
                    ),
                  ),
                ),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderBadge({required IconData icon, required String label, required Color color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: Colors.white),
          const SizedBox(width: 4),
          Text(label, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildInfoCard(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(title, style: TextStyle(color: Colors.grey.shade600, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.1)),
        ),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 10, offset: const Offset(0, 4)),
            ],
          ),
          child: Column(children: children),
        ),
      ],
    );
  }

  Widget _buildDividerRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Divider(height: 1, color: Colors.grey.shade200),
    );
  }

  Widget _buildDetailRow(String label, String value, {bool isCopyable = false, Color? valueColor, bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(label, style: TextStyle(color: Colors.grey.shade500, fontSize: 13)),
          ),
          Flexible(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    value,
                    style: TextStyle(
                      fontWeight: bold ? FontWeight.bold : FontWeight.w600,
                      fontSize: 13,
                      color: valueColor ?? Colors.black87,
                    ),
                    textAlign: TextAlign.end,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (isCopyable) ...[
                  const SizedBox(width: 8),
                  InkWell(
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: value));
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Copiado!")));
                    },
                    child: Icon(Icons.copy, size: 14, color: AppColors.primaryPurple),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
