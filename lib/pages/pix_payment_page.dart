import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../../core/theme/app_colors.dart';

/// Tela reutilizável para pagamento via PIX — usada tanto no checkout de
/// agendamento quanto no "pagar restante" nos agendamentos do cliente.
class PixPaymentPage extends StatefulWidget {
  final String qrBase64;
  final String copyPaste;
  final String paymentId;
  final double amount;
  final Future<bool> Function() onManualCheck;
  final VoidCallback onPaid;

  const PixPaymentPage({
    super.key,
    required this.qrBase64,
    required this.copyPaste,
    required this.paymentId,
    required this.amount,
    required this.onManualCheck,
    required this.onPaid,
  });

  @override
  State<PixPaymentPage> createState() => _PixPaymentPageState();
}

class _PixPaymentPageState extends State<PixPaymentPage> {
  bool _isVerifying = false;

  Future<void> _handleManualVerification() async {
    setState(() => _isVerifying = true);
    final isApproved = await widget.onManualCheck();
    setState(() => _isVerifying = false);

    if (isApproved) {
      widget.onPaid();
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                "Pagamento ainda não identificado. Aguarde uns instantes ou realize o PIX primeiro."),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 4),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: AppColors.primaryPurple,
        foregroundColor: Colors.white,
        title:
            const Text('Pagar via PIX', style: TextStyle(color: Colors.white)),
        elevation: 0,
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Header com valor
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [
                  AppColors.primaryPurple,
                  Colors.deepPurple.shade400
                ]),
                borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(20),
                    bottomRight: Radius.circular(20)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Valor a pagar',
                      style: TextStyle(color: Colors.white70, fontSize: 12)),
                  const SizedBox(height: 4),
                  Text(currency.format(widget.amount),
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold)),
                ],
              ),
            ),

            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    // QR Code
                    widget.qrBase64.isNotEmpty
                        ? Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                boxShadow: [
                                  BoxShadow(
                                      color:
                                          Colors.black.withValues(alpha: 0.05),
                                      blurRadius: 8)
                                ]),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Image.asset('assets/images/logo_purple.png',
                                    height: 32),
                                const SizedBox(height: 8),
                                Image.memory(base64Decode(widget.qrBase64),
                                    height: 240),
                              ],
                            ),
                          )
                        : const Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                                Icon(Icons.qr_code,
                                    size: 60, color: Colors.grey),
                                SizedBox(height: 8),
                                Text('Erro ao gerar QR')
                              ]),

                    // Pix Copia e Cola
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text('Pix Copia e Cola',
                            style: TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 14)),
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 8),
                          decoration: BoxDecoration(
                              color: Colors.grey[100],
                              borderRadius: BorderRadius.circular(8)),
                          child: Row(
                            children: [
                              Expanded(
                                  child: Text(widget.copyPaste,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          fontFamily: 'monospace',
                                          fontSize: 12))),
                              IconButton(
                                constraints: const BoxConstraints(),
                                padding: EdgeInsets.zero,
                                icon: const Icon(Icons.copy,
                                    color: AppColors.primaryPurple, size: 20),
                                onPressed: () {
                                  Clipboard.setData(
                                      ClipboardData(text: widget.copyPaste));
                                  ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                          content: Text("Código copiado!")));
                                },
                              )
                            ],
                          ),
                        ),
                      ],
                    ),

                    // Botões
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primaryPurple,
                              minimumSize: const Size(double.infinity, 48)),
                          onPressed:
                              _isVerifying ? null : _handleManualVerification,
                          child: _isVerifying
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                      color: Colors.white, strokeWidth: 2))
                              : const Text('JÁ REALIZEI O PAGAMENTO',
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13)),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Voltar',
                              style: TextStyle(
                                  color: Colors.black54, fontSize: 13)),
                        ),
                        const SizedBox(height: 30),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
