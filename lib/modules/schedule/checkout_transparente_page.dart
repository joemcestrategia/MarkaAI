import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'package:brasil_fields/brasil_fields.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_colors.dart';
import '../../core/services/mercado_pago_service.dart';
import '../../widgets/stripe_text_field.dart';
import 'booking_success_page.dart';

class CheckoutTransparentePage extends StatefulWidget {
  final String shopId;
  final double valor;
  final String orderId;
  final DocumentSnapshot serviceDoc;
  final DocumentSnapshot professionalDoc;
  final DateTime date;
  final TimeOfDay time;
  final bool collectOnly;
  final bool skipPlanCheck;

  const CheckoutTransparentePage({
    super.key,
    required this.shopId,
    required this.valor,
    required this.orderId,
    required this.serviceDoc,
    required this.professionalDoc,
    required this.date,
    required this.time,
    this.collectOnly = false,
    this.skipPlanCheck = false,
  });

  @override
  State<CheckoutTransparentePage> createState() =>
      _CheckoutTransparentePageState();
}

class _CheckoutTransparentePageState extends State<CheckoutTransparentePage> {
  final _formKey = GlobalKey<FormState>();
  final _cardNumberController = TextEditingController();
  final _holderNameController = TextEditingController();
  final _expiryController = TextEditingController();
  final _cvvController = TextEditingController();
  final _cpfController = TextEditingController();

  bool _isLoading = false;
  String? _publicKey;
  List<dynamic> _installments = [];
  dynamic _selectedInstallment;

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  Future<void> _loadConfig() async {
    setState(() => _isLoading = true);
    try {
      final doc = await FirebaseFirestore.instance
          .collection('shops')
          .doc(widget.shopId)
          .get();
      final data = doc.data() ?? {};
      final mp = data['mercadopago'] as Map<String, dynamic>?;
      _publicKey =
          (mp?['public_key'] as String?) ?? (data['mp_public_key'] as String?);

      if (_publicKey == null) {
        throw Exception('Mercado Pago não configurado para esta loja.');
      }

      // Pre-fill user data
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();
        final userData = userDoc.data();
        if (userData != null) {
          _holderNameController.text =
              userData['nome'] ?? user.displayName ?? '';
          _cpfController.text = userData['cpf'] ?? userData['documento'] ?? '';
        }
      }
    } catch (e) {
      _showError(e.toString());
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _onCardNumberChanged(String value) async {
    final cleanValue = value.replaceAll(' ', '');
    if (cleanValue.length >= 6) {
      final bin = cleanValue.substring(0, 6);
      if (_publicKey != null) {
        final costs = await MercadoPagoService.getInstallmentsWithBin(
          publicKey: _publicKey!,
          amount: widget.valor,
          bin: bin,
        );
        setState(() {
          _installments = costs;
          if (_installments.isNotEmpty) {
            _selectedInstallment = _installments[0];
          }
        });
      }
    } else {
      setState(() {
        _installments = [];
        _selectedInstallment = null;
      });
    }
  }

  Future<void> _processPayment() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedInstallment == null) {
      _showError('Selecione o número de parcelas.');
      return;
    }

    setState(() => _isLoading = true);
    try {
      final expiry = _expiryController.text.split('/');
      final month = expiry[0];
      final year = '20${expiry[1]}';

      final cardToken = await MercadoPagoService.getCardToken(
        publicKey: _publicKey!,
        cardNumber: _cardNumberController.text,
        cardholderName: _holderNameController.text,
        expirationMonth: month,
        expirationYear: year,
        securityCode: _cvvController.text,
      );

      if (widget.collectOnly) {
        if (!mounted) return;
        Navigator.pop(context, {
          'cardToken': cardToken,
          'installments': _selectedInstallment['installments'],
          'email': FirebaseAuth.instance.currentUser?.email ?? '',
          'paymentMethodId': 'credit_card', // For simplification
        });
        return;
      }

      // Full payment logic
      final idToken = await _getPaymentIdToken();
      if (idToken == null) return;

      final response = await http.post(
        Uri.parse(
            'https://us-central1-wismart-118c3.cloudfunctions.net/criarPagamento'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'data': {
            'cardToken': cardToken,
            'email': FirebaseAuth.instance.currentUser?.email ?? '',
            'installments': _selectedInstallment['installments'],
            'valor': widget.valor,
            'shopId': widget.shopId,
            'orderId': widget.orderId,
            'descricao': "Reserva: ${widget.serviceDoc['nome'] ?? 'Serviço'}",
            'idToken': idToken,
            'cpf': _cpfController.text.replaceAll(RegExp(r'[^0-9]'), ''),
            'paymentMethodId': 'credit_card',
          }
        }),
      );

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result['success'] == true) {
          await _salvarAgendamento(result['paymentId'].toString());
        } else {
          _showError(result['error'] ?? 'Pagamento recusado');
        }
      } else {
        final error = jsonDecode(response.body);
        _showError(error['error']?.toString() ?? 'Erro no pagamento');
      }
    } catch (e) {
      _showError('Erro ao processar pagamento: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<String?> _getPaymentIdToken() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;
    return await user.getIdToken();
  }

  Future<void> _salvarAgendamento(String paymentId) async {
    try {
      final user = FirebaseAuth.instance.currentUser!;
      final bookingDate = DateTime(widget.date.year, widget.date.month,
          widget.date.day, widget.time.hour, widget.time.minute);

      final timeStr =
          '${widget.time.hour.toString().padLeft(2, '0')}:${widget.time.minute.toString().padLeft(2, '0')}';

      await FirebaseFirestore.instance.collection('appointments').add({
        'shopId': widget.shopId,
        'clientId': user.uid,
        'serviceId': widget.serviceDoc.id,
        'professionalId': widget.professionalDoc.id,
        'date': Timestamp.fromDate(bookingDate),
        'time': timeStr,
        'status': 'confirmado',
        'paymentId': paymentId,
        'paymentMethod': 'Cartão de Crédito',
        'valor': widget.valor,
        'created_at': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => BookingSuccessPage(
              serviceName: widget.serviceDoc['nome'] ?? 'Serviço',
              date:
                  "${widget.date.day.toString().padLeft(2, '0')}/${widget.date.month.toString().padLeft(2, '0')}/${widget.date.year}",
              time:
                  "${widget.time.hour.toString().padLeft(2, '0')}:${widget.time.minute.toString().padLeft(2, '0')}",
              professionalName:
                  widget.professionalDoc['nome'] ?? 'Profissional',
              isPaid: true,
            ),
          ),
        );
      }
    } catch (e) {
      _showError('Erro ao agendar: $e');
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FB),
      appBar: AppBar(
        title: const Text('Checkout Seguro',
            style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _isLoading && _publicKey == null
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'TOTAL A PAGAR',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey[600],
                          letterSpacing: 1.1),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'R\$ ${widget.valor.toStringAsFixed(2).replaceFirst('.', ',')}',
                      style: const TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                          color: AppColors.primaryPurple),
                    ),
                    const SizedBox(height: 32),
                    StripeTextField(
                      label: 'Número do Cartão',
                      hintText: '0000 0000 0000 0000',
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        CartaoBancarioInputFormatter(),
                      ],
                      controller: _cardNumberController,
                      onChanged: _onCardNumberChanged,
                      validator: (v) => v!.isEmpty ? 'Obrigatório' : null,
                      suffixIcon:
                          const Icon(Icons.credit_card, color: Colors.grey),
                    ),
                    const SizedBox(height: 20),
                    StripeTextField(
                      label: 'Nome no Cartão',
                      hintText: 'COMO ESTA NO CARTÃO',
                      controller: _holderNameController,
                      validator: (v) => v!.isEmpty ? 'Obrigatório' : null,
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: StripeTextField(
                            label: 'Validade',
                            hintText: 'MM/AA',
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                              ValidadeCartaoInputFormatter(),
                            ],
                            controller: _expiryController,
                            validator: (v) => v!.isEmpty ? 'Obrigatório' : null,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: StripeTextField(
                            label: 'CVC',
                            hintText: '123',
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                              LengthLimitingTextInputFormatter(4),
                            ],
                            controller: _cvvController,
                            validator: (v) => v!.isEmpty ? 'Obrigatório' : null,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    StripeTextField(
                      label: 'CPF do Titular',
                      hintText: '000.000.000-00',
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        CpfInputFormatter(),
                      ],
                      controller: _cpfController,
                      validator: (v) => v!.isEmpty ? 'Obrigatório' : null,
                    ),
                    const SizedBox(height: 32),
                    if (_installments.isNotEmpty) ...[
                      Text(
                        'PARCELAMENTO',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey[600],
                            letterSpacing: 1.1),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          border:
                              Border.all(color: Colors.grey[200]!, width: 1.5),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<dynamic>(
                            value: _selectedInstallment,
                            isExpanded: true,
                            items: _installments.map((inst) {
                              return DropdownMenuItem<dynamic>(
                                value: inst,
                                child: Text(inst['recommended_message']),
                              );
                            }).toList(),
                            onChanged: (val) =>
                                setState(() => _selectedInstallment = val),
                          ),
                        ),
                      ),
                      const SizedBox(height: 40),
                    ],
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _processPayment,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primaryPurple,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8)),
                          elevation: 0,
                        ),
                        child: _isLoading
                            ? const CircularProgressIndicator(
                                color: Colors.white)
                            : const Text(
                                'Pagar Agora',
                                style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white),
                              ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Center(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.lock_outline,
                              size: 16, color: Colors.grey[400]),
                          const SizedBox(width: 4),
                          Text(
                            'Pagamento processado com segurança pelo Mercado Pago',
                            style: TextStyle(
                                fontSize: 12, color: Colors.grey[500]),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
