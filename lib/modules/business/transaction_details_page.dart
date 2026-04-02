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

  @override
  void initState() {
    super.initState();
    _fetchDeepDetails();
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
      // Tenta buscar detalhes frescos da API
      final details = await MercadoPagoService.verificarStatusPix(
        shopId: widget.appointmentData['shop_id'].toString(),
        paymentId: paymentId,
      );
      
      // Nota: No momento verificarStatusPix retorna apenas String de status.
      // Em uma implementação real, o backend deveria retornar o JSON completo.
      // Por enquanto, usaremos os dados do metadata + o status atualizado.
      
      setState(() {
        _fullTransaction = {
          'id': paymentId,
          'status': details,
          'method': widget.appointmentData['payment_method'] ?? 'Desconhecido',
          'amount': double.tryParse(widget.appointmentData['total_price']?.toString() ?? '0') ?? 0.0,
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

    final date = DateFormat('dd/MM/yyyy HH:mm').format(DateTime.parse(_fullTransaction!['scheduled_at']));
    final total = _fullTransaction!['amount'].toStringAsFixed(2);
    final status = _fullTransaction!['status'].toString().toUpperCase();
    final id = _fullTransaction!['id'];

    final text = """
📌 *Comprovante de Transação - MarkaAI*
Cliente: ${widget.appointmentData['client_name'] ?? 'Cliente'}
Serviço: ${widget.appointmentData['service_name'] ?? 'Serviço'}
Data: $date
Valor Total: R\$ $total
Status: $status
---
ID Transação: $id
---
_Emitido via MarkaAI Business_
""";

    Share.share(text);
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
        // Chamada fictícia para Supabase Function de Reembolso
        await Supabase.instance.client.functions.invoke('refund-payment', body: {
          'payment_id': _fullTransaction!['id'],
          'shop_id': widget.appointmentData['shop_id'],
        });
      }

      // Atualiza status no banco local
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
    final status = _fullTransaction?['status']?.toString().toLowerCase() ?? 'pending';
    final isApproved = status == 'approved' || status == 'accredited';
    final statusLabel = isApproved ? "PAGAMENTO APROVADO" : (status == 'rejected' ? "PAGAMENTO RECUSADO" : "AGUARDANDO/PENDENTE");

    return SingleChildScrollView(
      child: Column(
        children: [
          // Header Purple
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [AppColors.primaryPurple, Color(0xFF4A148C)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Column(
              children: [
                Text(
                  "VALOR TOTAL",
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.2),
                ),
                const SizedBox(height: 8),
                Text(
                  "R\$ ${_fullTransaction!['amount'].toStringAsFixed(2)}",
                  style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 16),
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
                      Text(
                        statusLabel,
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                      ),
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
                _buildInfoCard("INFORMAÇÕES TÉCNICAS", [
                  _buildDetailRow("ID Transação", _fullTransaction!['id'], isCopyable: true),
                  _buildDetailRow("Método", _fullTransaction!['method']),
                  _buildDetailRow("Val. Adiantamento", "R\$ ${_fullTransaction!['paid_amount'].toStringAsFixed(2)}"),
                  _buildDetailRow("Status API", status),
                ]),
                const SizedBox(height: 16),
                _buildInfoCard("AUDITORIA DE SISTEMA", [
                  _buildDetailRow("Criado em", DateFormat('dd/MM/yyyy HH:mm:ss').format(DateTime.parse(_fullTransaction!['created_at']))),
                  _buildDetailRow("Agendado para", DateFormat('dd/MM/yyyy HH:mm:ss').format(DateTime.parse(_fullTransaction!['scheduled_at']))),
                  _buildDetailRow("Origem", "Agendamento Online Cliente"),
                ]),
                const SizedBox(height: 32),
                
                // Botões de Ação
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _copyTechnicalData,
                    icon: const Icon(Icons.code),
                    label: const Text("COPIAR DADOS TÉCNICOS (JSON)"),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
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
                      padding: const EdgeInsets.symmetric(vertical: 16),
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

  Widget _buildDetailRow(String label, String value, {bool isCopyable = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: Colors.grey.shade500, fontSize: 13)),
          Flexible(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    value,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
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
