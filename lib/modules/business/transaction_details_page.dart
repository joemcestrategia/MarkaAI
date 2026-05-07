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

  double _resolveDiscountAmount(Map<String, dynamic> data, double originalPrice, double finalPrice) {
    final double discountAmt = double.tryParse(data['discount_amount']?.toString() ?? '0') ?? 0;
    if (discountAmt > 0.01) return discountAmt;
    if (originalPrice > finalPrice + 0.01) return originalPrice - finalPrice;
    return 0;
  }

  Future<void> _fetchDeepDetails() async {
    final metadata = widget.appointmentData['metadata'] as Map?;
    final paymentId = metadata?['payment_id']?.toString();

    if (paymentId == null || paymentId.isEmpty) {
      setState(() {
        _errorMsg = "ID de transação não encontrado no agendamento.";
      });
      return;
    }

    setState(() => _isLoading = true);
    try {
      final details = await MercadoPagoService.verificarStatusPix(
        shopId: widget.appointmentData['shop_id'].toString(),
        paymentId: paymentId,
      );

      final double finalAmount = _resolveDisplayTotal(widget.appointmentData);

      setState(() {
        _fullTransaction = {
          'id': paymentId,
          'status': details,
          'method': widget.appointmentData['payment_method'] ?? 'Desconhecido',
          'amount': finalAmount,
          'paid_amount': double.tryParse(widget.appointmentData['paid_amount']?.toString() ?? '0') ?? 0.0,
          'created_at': widget.appointmentData['created_at'],
          'scheduled_at': widget.appointmentData['scheduled_at'],
        };
      });
    } catch (e) {
      setState(() => _errorMsg = "Erro ao conectar com a operadora: $e");
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
    final double finalAmount = (_fullTransaction!['amount'] as double);
    final double paidAmount = (_fullTransaction!['paid_amount'] as double);
    final double remaining = finalAmount - paidAmount;
    final double discountAmt = _resolveDiscountAmount(data, originalPrice, finalAmount);
    final bool hasDiscount = discountAmt > 0.01;
    final bool hasBirthday = data['birthday_discount_applied'] == true;
    final bool hasCoupon = data['coupon_applied'] == true;
    final bool isAdvancePayment = paidAmount > 0.01 && remaining > 0.01;

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
                    isAdvancePayment ? "Adiantamento pago" : "Valor pago",
                    _fmt.format(paidAmount),
                    valueColor: Colors.green,
                    bold: true,
                  ),
                  if (remaining > 0.01)
                    _buildDetailRow("Restante a pagar", _fmt.format(remaining), valueColor: Colors.red, bold: true),
                  if (remaining <= 0.01)
                    _buildDetailRow("Situação", "QUITADO ✓", valueColor: Colors.green, bold: true),
                ]),

                const SizedBox(height: 16),

                // ── INFORMAÇÕES DA TRANSAÇÃO ──
                _buildInfoCard("INFORMAÇÕES DA TRANSAÇÃO", [
                  _buildDetailRow("ID Transação", _fullTransaction!['id'], isCopyable: true),
                  _buildDetailRow("Método de pagamento", _fullTransaction!['method']),
                  _buildDetailRow("Status da operadora", status.toUpperCase()),
                  if (data['payment_id'] != null)
                    _buildDetailRow("Payment ID", data['payment_id'].toString(), isCopyable: true),
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
