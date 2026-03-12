import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:brasil_fields/brasil_fields.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_colors.dart';
import '../../core/services/mercado_pago_service.dart';
import '../../widgets/stripe_text_field.dart';
import 'checkout_review_page.dart';

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

  double _taxaCredito = 0.0;
  double _valorComTaxa = 0.0;
  bool _showProfessional = true;

  final List<dynamic> _paymentItems = [];

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

      final config = data['config'] as Map<String, dynamic>? ?? {};
      _showProfessional = config['cliente_escolhe_prof'] ?? true;
      _taxaCredito =
          (config['tax_percent'] ?? config['porcentagem_a_vista'] ?? 0)
              .toDouble();

      final rawTotal = widget.valor * (1 + (_taxaCredito / 100));
      _valorComTaxa = double.parse(rawTotal.toStringAsFixed(2));

      _paymentItems.add({
        'label': 'Reserva na ${data['nome'] ?? 'Loja'}',
        'amount': _valorComTaxa.toStringAsFixed(2),
      });

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
          amount: _valorComTaxa,
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

      final tokenData = await MercadoPagoService.getCardToken(
        publicKey: _publicKey!,
        cardNumber: _cardNumberController.text.replaceAll(' ', ''),
        cardholderName: _holderNameController.text,
        expirationMonth: month,
        expirationYear: year,
        securityCode: _cvvController.text,
      );

      final cardToken = tokenData['id']?.toString() ?? '';

      if (cardToken.isEmpty) {
        _showError('Não conseguimos validar seu cartão. Verifique os dados.');
        return;
      }

      if (!mounted) return;

      final lastFour = _cardNumberController.text
          .replaceAll(' ', '')
          .substring(_cardNumberController.text.replaceAll(' ', '').length - 4);

      final user = FirebaseAuth.instance.currentUser;

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => CheckoutReviewPage(
            paymentData: {
              'cardToken': cardToken,
              'valor': _valorComTaxa,
              'email': user?.email ?? 'cliente@markaai.com.br',
              'installments': _selectedInstallment['installments'],
              'lastFour': lastFour,
              'paymentMethodId': tokenData['payment_method_id'],
              'issuerId': tokenData['issuer_id'],
              'cpf': _cpfController.text,
            },
            serviceDoc: widget.serviceDoc,
            professionalDoc: widget.professionalDoc,
            date: widget.date,
            time:
                '${widget.time.hour.toString().padLeft(2, '0')}:${widget.time.minute.toString().padLeft(2, '0')}',
            shopId: widget.shopId,
            orderId: widget.orderId,
            showProfessional: _showProfessional,
          ),
        ),
      );

      // Notify the system that autofill is complete
      TextInput.finishAutofillContext();
    } catch (e) {
      _showError(_getFriendlyErrorMessage(e.toString()));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  bool _isValidCpf(String cpf) {
    cpf = cpf.replaceAll(RegExp(r'[^0-9]'), '');
    if (cpf.length != 11) return false;
    if (RegExp(r'^(\d)\1{10}$').hasMatch(cpf)) return false;

    List<int> digits = cpf.split('').map(int.parse).toList();

    int sum1 = 0;
    for (int i = 0; i < 9; i++) {
      sum1 += digits[i] * (10 - i);
    }
    int rest1 = (sum1 * 10) % 11;
    if (rest1 == 10) rest1 = 0;
    if (digits[9] != rest1) return false;

    int sum2 = 0;
    for (int i = 0; i < 10; i++) {
      sum2 += digits[i] * (11 - i);
    }
    int rest2 = (sum2 * 10) % 11;
    if (rest2 == 10) rest2 = 0;
    if (digits[10] != rest2) return false;

    return true;
  }

  String _getFriendlyErrorMessage(String? code, {String? statusDetail}) {
    // Check common raw error strings first (from Exception messages or API responses)
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
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.error_outline,
                    color: Colors.red, size: 48),
              ),
              const SizedBox(height: 24),
              const Text(
                'Ops! No momento não\nconseguimos prosseguir',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1A1A1A),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[600],
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1A1A1A),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  child: const Text('Tentar Novamente',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
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
          : Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AutofillGroup(
                      child: Expanded(
                        child: SingleChildScrollView(
                          physics: const ClampingScrollPhysics(),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'TOTAL A PAGAR',
                                        style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.grey[600],
                                            letterSpacing: 1.1),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'R\$ ${_valorComTaxa.toStringAsFixed(2).replaceFirst('.', ',')}',
                                        style: const TextStyle(
                                            fontSize: 28,
                                            fontWeight: FontWeight.bold,
                                            color: AppColors.primaryPurple),
                                      ),
                                    ],
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 6),
                                    decoration: BoxDecoration(
                                      color:
                                          Colors.green.withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.credit_card,
                                            size: 14, color: Colors.green),
                                        SizedBox(width: 4),
                                        Text(
                                          'Até 12x no cartão',
                                          style: const TextStyle(
                                              color: Colors.green,
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              if (_taxaCredito > 0)
                                Padding(
                                  padding: const EdgeInsets.only(top: 2.0),
                                  child: Text(
                                    'Inclui ${_taxaCredito.toStringAsFixed(1)}% de taxa',
                                    style: TextStyle(
                                        fontSize: 11, color: Colors.grey[500]),
                                  ),
                                ),
                              const SizedBox(height: 16),
                              StripeTextField(
                                label: 'Número do Cartão',
                                hintText: '0000 0000 0000 0000',
                                keyboardType: TextInputType.number,
                                autofillHints: const [
                                  AutofillHints.creditCardNumber
                                ],
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly,
                                  CartaoBancarioInputFormatter(),
                                ],
                                controller: _cardNumberController,
                                onChanged: _onCardNumberChanged,
                                textInputAction: TextInputAction.next,
                                validator: (v) =>
                                    v!.isEmpty ? 'Obrigatório' : null,
                                suffixIcon: const Icon(Icons.credit_card,
                                    color: Colors.grey),
                              ),
                              const SizedBox(height: 16),
                              StripeTextField(
                                label: 'Nome no Cartão',
                                hintText: 'COMO ESTA NO CARTÃO',
                                autofillHints: const [
                                  AutofillHints.creditCardName
                                ],
                                controller: _holderNameController,
                                textInputAction: TextInputAction.next,
                                validator: (v) =>
                                    v!.isEmpty ? 'Obrigatório' : null,
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Expanded(
                                    child: StripeTextField(
                                      label: 'Validade',
                                      hintText: 'MM/AA',
                                      keyboardType: TextInputType.number,
                                      autofillHints: const [
                                        AutofillHints.creditCardExpirationDate
                                      ],
                                      inputFormatters: [
                                        FilteringTextInputFormatter.digitsOnly,
                                        ValidadeCartaoInputFormatter(),
                                      ],
                                      controller: _expiryController,
                                      textInputAction: TextInputAction.next,
                                      validator: (v) =>
                                          v!.isEmpty ? 'Obrigatório' : null,
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: StripeTextField(
                                      label: 'CVC',
                                      hintText: '123',
                                      keyboardType: TextInputType.number,
                                      autofillHints: const [
                                        AutofillHints.creditCardSecurityCode
                                      ],
                                      inputFormatters: [
                                        FilteringTextInputFormatter.digitsOnly,
                                        LengthLimitingTextInputFormatter(4),
                                      ],
                                      controller: _cvvController,
                                      textInputAction: TextInputAction.next,
                                      validator: (v) =>
                                          v!.isEmpty ? 'Obrigatório' : null,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
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
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                        color: Colors.grey[200]!, width: 1.5),
                                  ),
                                  child: DropdownButtonHideUnderline(
                                    child: DropdownButton<dynamic>(
                                      value: _selectedInstallment,
                                      isExpanded: true,
                                      items: _installments.map((inst) {
                                        return DropdownMenuItem<dynamic>(
                                          value: inst,
                                          child:
                                              Text(inst['recommended_message']),
                                        );
                                      }).toList(),
                                      onChanged: (val) => setState(
                                          () => _selectedInstallment = val),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 16),
                              ],
                              StripeTextField(
                                label: 'CPF do Titular',
                                hintText: '000.000.000-00',
                                keyboardType: TextInputType.number,
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly,
                                  CpfInputFormatter(),
                                ],
                                controller: _cpfController,
                                textInputAction: TextInputAction.done,
                                validator: (v) {
                                  if (v == null || v.isEmpty) {
                                    return 'Obrigatório';
                                  }
                                  if (!_isValidCpf(v)) return 'CPF inválido';
                                  return null;
                                },
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16.0),
                      child: SizedBox(
                        width: double.infinity,
                        height: 52,
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
                                  'Continuar para Revisão',
                                  style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white),
                                ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Center(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.lock_outline,
                              size: 14, color: Colors.grey[400]),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              'Pagamento seguro via Mercado Pago',
                              style: TextStyle(
                                  fontSize: 11, color: Colors.grey[500]),
                              textAlign: TextAlign.center,
                            ),
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
