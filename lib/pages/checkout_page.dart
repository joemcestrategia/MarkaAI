import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import '../../core/theme/app_colors.dart';
import '../../core/services/mercado_pago_service.dart';
import '../modules/schedule/checkout_transparente_page.dart';
import '../modules/schedule/booking_success_page.dart';
import '../core/widgets/loading_page.dart';
import '../modules/clients/my_appointments_page.dart';

class CheckoutPage extends StatefulWidget {
  final String shopId;
  final Map<String, dynamic> shopData;
  final Map<String, dynamic> shopConfig;
  final DocumentSnapshot serviceDoc;
  final DocumentSnapshot professionalDoc;
  final DateTime date;
  final TimeOfDay time;
  final String? serviceNameOverride;
  final double? servicePriceOverride;

  const CheckoutPage({
    super.key,
    required this.shopId,
    required this.shopData,
    required this.shopConfig,
    required this.serviceDoc,
    required this.professionalDoc,
    required this.date,
    required this.time,
    this.serviceNameOverride,
    this.servicePriceOverride,
  });

  @override
  State<CheckoutPage> createState() => _CheckoutPageState();
}

class _CheckoutPageState extends State<CheckoutPage> {
  final _currencyFormat = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

  bool _isLoading = false;
  int _currentStep = 0;

  String _selectedPaymentType = 'total';
  String _selectedMethod = 'pix';
  bool _paymentConfigLoaded = false;
  // Enquanto não tivermos contrato/limitação, liberar métodos para todos
  final bool _forceAllPayments = true;
  /// Dados do cartão coletados no WebView (modo "Confirmar e ir para revisão")
  Map<String, dynamic>? _storedCardData;

  double valorTotal = 0.0;
  double valorSinal = 0.0;
  double valorFinalComJuros = 0.0;
  int percentualSinalInt = 30;

  bool exigeSinal = false;
  bool aceitaPix = false;
  bool aceitaCartao = false;
  String? shopAccessToken;

  Timer? _timerPolling;

  @override
  void initState() {
    super.initState();
    _initializeCheckout();
  }

  @override
  void dispose() {
    _timerPolling?.cancel();
    super.dispose();
  }

  Future<void> _initializeCheckout() async {
    await _loadShopPaymentConfig();
    _calculateFinancials();
    _recalculateTotals();
  }

  Future<void> _loadShopPaymentConfig() async {
    try {
      final shopDoc = await FirebaseFirestore.instance.collection('shops').doc(widget.shopId).get();
      if (!shopDoc.exists) return;

      final data = shopDoc.data()!;
      final mpData = data['mercadopago'] as Map<String, dynamic>?;
      final config = data['config'] as Map<String, dynamic>? ?? widget.shopConfig;

      final percentualFromDb = config['percentual_sinal'];
      int percentualFinal = 30;
      if (percentualFromDb != null) percentualFinal = (percentualFromDb as num).toInt();

      String? token = mpData?['access_token']?.toString() ?? data['mp_access_token']?.toString();
      final isValidToken = token != null && token.length > 20;

      debugPrint('🔐 Token MP válido: $isValidToken (${token?.length ?? 0} chars)');

      setState(() {
        shopAccessToken = token;
        // Se estivermos em modo liberado, permite todos os métodos configurados mesmo sem token.
        aceitaPix = _forceAllPayments || (config['pagamento_pix'] ?? true);
        aceitaCartao = _forceAllPayments || (config['pagamento_cartao'] ?? true);
        exigeSinal = config['exigir_sinal'] ?? false;
        percentualSinalInt = percentualFinal;

        if (exigeSinal && (aceitaPix || aceitaCartao)) {
          _selectedPaymentType = 'sinal';
        } else {
          _selectedPaymentType = 'local';
        }
        _paymentConfigLoaded = true;
      });
    } catch (e) {
      debugPrint('❌ Erro config: $e');
    }
  }

  void _calculateFinancials() {
    valorTotal = widget.servicePriceOverride ?? double.tryParse(widget.serviceDoc['preco'].toString()) ?? 0.0;
    valorSinal = valorTotal * (percentualSinalInt / 100.0);
    valorFinalComJuros = valorTotal;
  }

  void _recalculateTotals() {
    setState(() {
      double base = (_selectedPaymentType == 'sinal') ? valorSinal : valorTotal;
      valorFinalComJuros = base;
    });
  }

  void _handleNextStep() async {
    switch (_currentStep) {
      case 0:
        setState(() => _currentStep = 1);
        break;
      case 1:
        // If user explicitly chose "Pagar Pessoalmente", allow proceeding immediately
        if (_selectedPaymentType == 'local') {
          setState(() => _currentStep = 2);
          break;
        }

        // Prevent proceeding if payment configuration still loading for online flows
        if (!_paymentConfigLoaded) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Aguarde, carregando opções de pagamento...")));
          return;
        }
        // If no online methods are available, silently fallback to "local" payment.
        if (_selectedPaymentType != 'local' && !aceitaPix && !aceitaCartao) {
          setState(() {
            _selectedPaymentType = 'local';
            _recalculateTotals();
            _currentStep = 2;
          });
          break;
        }
        if (_selectedMethod == 'card' && _selectedPaymentType != 'local') {
          double valorParaCobrar = (_selectedPaymentType == 'sinal') ? valorSinal : valorTotal;
          final result = await Navigator.push<Map<String, dynamic>>(
            context,
            MaterialPageRoute(
              builder: (context) => CheckoutTransparentePage(
                shopId: widget.shopId,
                valor: valorParaCobrar,
                orderId: "ORD-${DateTime.now().millisecondsSinceEpoch}",
                serviceDoc: widget.serviceDoc,
                professionalDoc: widget.professionalDoc,
                date: widget.date,
                time: widget.time,
                collectOnly: true,
              ),
            ),
          );
          if (result != null && mounted) {
            setState(() {
              _storedCardData = result;
              _currentStep = 2;
            });
          }
        } else {
          setState(() => _currentStep = 2);
        }
        break;
      case 2:
        setState(() => _currentStep = 3);
        _showConfirmationModal();
        break;
    }
  }

  void _handlePreviousStep() {
    if (_currentStep > 0) setState(() => _currentStep--);
  }

  void _showConfirmationModal() {
    String tituloPagamento = "Pagar no Local";
    String detalhePagamento = "Dinheiro ou Cartão na hora";
    String valorExibido = _currencyFormat.format(valorTotal);
    
    // 🔄 Define o texto do botão baseado no tipo de pagamento
    String textoBotao = _selectedPaymentType == 'local' ? "FINALIZAR" : "FINALIZAR E PAGAR";

    if (_selectedPaymentType != 'local') {
      double valorReal = (_selectedPaymentType == 'sinal') ? valorSinal : valorTotal;
      valorExibido = _currencyFormat.format(valorReal);

      if (_selectedMethod == 'pix') {
        tituloPagamento = "Pix (QR Code)";
        detalhePagamento = "Pagamento instantâneo";
      } else {
        tituloPagamento = "Cartão de Crédito";
        detalhePagamento = "Processamento seguro via Mercado Pago";
      }
    }

    showModalBottomSheet(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        height: MediaQuery.of(context).size.height * 0.75,
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
                const Text("Resumo do Pedido",
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppColors.primaryPurple)),
                IconButton(onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close))
              ],
            ),
            const SizedBox(height: 5),
            const Text("Confira os detalhes antes de finalizar.", style: TextStyle(color: Colors.grey)),
            const SizedBox(height: 25),
            _summaryItem(Icons.cut, "Serviço", widget.serviceNameOverride ?? widget.serviceDoc['nome']),
            _summaryItem(Icons.person, "Profissional", widget.professionalDoc['nome'] ?? ''),
            _summaryItem(Icons.calendar_today, "Data e Hora",
                "${DateFormat('dd/MM').format(widget.date)} às ${widget.time.format(context)}"),
            const Divider(height: 30),
            _summaryItem(Icons.payment, "Forma de Pagamento", tituloPagamento, subtitle: detalhePagamento),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(color: AppColors.primaryPurple.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text("TOTAL A PAGAR", style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.primaryPurple)),
                  Text(valorExibido, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: AppColors.primaryPurple)),
                ],
              ),
            ),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              height: 55,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                onPressed: () {
                  Navigator.pop(ctx);
                  // Se pagamento local, finalize imediatamente sem fluxo de pagamento
                  if (_selectedPaymentType == 'local') {
                    _saveBooking(metodo: "No Local", status: "agendado", valorPago: 0);
                  } else {
                    _executeFinalAction();
                  }
                },
                child: Text(textoBotao,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
              ),
            ),
            const SizedBox(height: 10),
            Center(child: TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Voltar e Editar")))
          ],
        ),
      ),
    );
  }

  Future<void> _executeFinalAction() async {
    debugPrint('Executando ação final | Tipo: $_selectedPaymentType | Método: $_selectedMethod');

    if (_selectedPaymentType == 'local') {
      debugPrint('→ Pagamento LOCAL');
      _saveBooking(metodo: "No Local", status: "agendado", valorPago: 0);
    } else if (_selectedMethod == 'pix') {
      debugPrint('→ Pagamento PIX');
      double valor = (_selectedPaymentType == 'sinal') ? valorSinal : valorTotal;
      String desc = (_selectedPaymentType == 'sinal') ? "Sinal" : "Total";
      _generatePix(valor, desc);
    } else {
      debugPrint('→ Pagamento CARTÃO → cobrando com dados já coletados');
      double valorParaCobrar = (_selectedPaymentType == 'sinal') ? valorSinal : valorTotal;
      if (_storedCardData != null) {
        await _processarPagamentoComCartaoArmazenado(
          valor: valorParaCobrar,
          cardToken: _storedCardData!['cardToken'] as String,
          installments: _storedCardData!['installments'] as int,
          email: _storedCardData!['email'] as String,
          paymentMethodId: _storedCardData!['paymentMethodId'] as String?,
          issuerId: _storedCardData!['issuerId'],
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Dados do cartão não encontrados. Preencha o cartão novamente.")),
        );
      }
    }
  }

  Future<void> _processarPagamentoComCartaoArmazenado({
    required double valor,
    required String cardToken,
    required int installments,
    required String email,
    String? paymentMethodId,
    dynamic issuerId,
  }) async {
    setState(() => _isLoading = true);
    try {
      final idToken = await _getPaymentIdToken();
      if (idToken == null) return;

      final response = await http.post(
        Uri.parse('https://us-central1-wismart-118c3.cloudfunctions.net/criarPagamento'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'data': {
            'cardToken': cardToken,
            'email': email,
            'installments': installments,
            'valor': valor,
            'shopId': widget.shopId,
            'orderId': 'ORD-${DateTime.now().millisecondsSinceEpoch}',
            'descricao': "Reserva: ${widget.serviceDoc['nome'] ?? 'Serviço'}",
            'idToken': idToken,
            if (paymentMethodId != null) 'paymentMethodId': paymentMethodId,
            if (issuerId != null) 'issuerId': issuerId,
          }
        }),
      );

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result['success'] == true && result['paymentId'] != null) {
          await _saveBooking(
            metodo: "Cartão de Crédito",
            status: "confirmado",
            valorPago: valor,
            paymentId: result['paymentId'].toString(),
          );
        } else {
          _showError(result['error']?.toString() ?? 'Pagamento recusado');
        }
      } else {
        final error = jsonDecode(response.body);
        _showError(error['error']?.toString() ?? 'Erro no pagamento');
      }
    } catch (e) {
      _showError('Erro ao processar pagamento: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<String?> _getPaymentIdToken() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _showError('Não foi possível validar sua sessão para o pagamento. Tente novamente.');
      return null;
    }
    try {
      return await user.getIdToken(true);
    } catch (_) {
      try {
        return await user.getIdToken();
      } catch (_) {
        _showError('Não foi possível validar sua sessão para o pagamento. Tente novamente.');
        return null;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    double valorExibido = valorFinalComJuros;
    if (_selectedPaymentType == 'local') {
      valorExibido = valorTotal;
    } else if (_selectedPaymentType == 'sinal' && _selectedMethod != 'card') valorExibido = valorSinal;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Pagamento"),
        backgroundColor: AppColors.primaryPurple,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      backgroundColor: const Color(0xFFF5F7FA),
      body: SafeArea(
        child: Column(
          children: [
            _buildStepIndicator(),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildResumoHeader(valorExibido),
                    const SizedBox(height: 25),
                    if (_currentStep == 0) _buildStep1_TipoValor(),
                    if (_currentStep == 1) _buildStep2_MetodoPagamento(),
                    if (_currentStep == 2) _buildStep3_Confirmacao(),
                  ],
                ),
              ),
            ),
            _buildActionButtons(),
          ],
        ),
      ),
    );
  }

  Widget _buildStepIndicator() {
    List<String> stepLabels = ['Valor', 'Método', 'Confirmação', 'Revisão'];
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(4, (index) {
              bool isActive = index <= _currentStep;
              bool isCurrent = index == _currentStep;
              return Column(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isActive ? AppColors.primaryPurple : Colors.grey[300],
                    ),
                    child: Center(
                      child: Text(
                        '${index + 1}',
                        style: TextStyle(
                          color: isActive ? Colors.white : Colors.grey[600],
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    stepLabels[index],
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                      color: isCurrent ? AppColors.primaryPurple : Colors.grey,
                    ),
                  ),
                ],
              );
            }),
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: LinearProgressIndicator(
              value: (_currentStep + 1) / 4,
              minHeight: 4,
              backgroundColor: Colors.grey[300],
              valueColor: AlwaysStoppedAnimation<Color>(AppColors.primaryPurple),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStep1_TipoValor() {
    if (!_paymentConfigLoaded) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Column(
            children: const [
              SizedBox(height: 8),
              CircularProgressIndicator(),
              SizedBox(height: 12),
              Text("Carregando opções de pagamento...", style: TextStyle(color: Colors.grey)),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text("O que deseja pagar?", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: AppColors.primaryPurple)),
        const SizedBox(height: 20),
        if (exigeSinal && (aceitaPix || aceitaCartao))
          _buildPaymentTypeCard(
            value: 'sinal',
            title: "💰 Pagar Adiantamento",
            subtitle: "$percentualSinalInt% do valor agora",
            amount: valorSinal,
            badge: "SINAL",
            badgeColor: Colors.orange,
          ),
        const SizedBox(height: 12),
        if (aceitaPix || aceitaCartao)
          _buildPaymentTypeCard(
            value: 'total',
            title: "✅ Pagar Valor Total",
            subtitle: "Valor completo agora",
            amount: valorTotal,
            badge: "COMPLETO",
            badgeColor: Colors.green,
          ),
        const SizedBox(height: 12),
        _buildPaymentTypeCard(
          value: 'local',
          title: "🏪 Pagar Pessoalmente",
          subtitle: "Dinheiro ou cartão na hora",
          amount: valorTotal,
          badge: "LOCAL",
          badgeColor: Colors.blue,
        ),
      ],
    );
  }

  Widget _buildPaymentTypeCard({
    required String value,
    required String title,
    required String subtitle,
    required double amount,
    required String badge,
    required Color badgeColor,
  }) {
    bool isSelected = value == _selectedPaymentType;
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedPaymentType = value;
          _recalculateTotals();
        });
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primaryPurple.withValues(alpha: 0.08) : Colors.white,
          border: Border.all(
            color: isSelected ? AppColors.primaryPurple : Colors.grey[300]!,
            width: isSelected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected ? AppColors.primaryPurple : Colors.grey[400]!,
                  width: 2,
                ),
              ),
              child: isSelected
                  ? Center(
                      child: Container(
                        width: 12,
                        height: 12,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.primaryPurple,
                        ),
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  Text(subtitle, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: badgeColor.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    badge,
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: badgeColor),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _currencyFormat.format(amount),
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppColors.primaryPurple),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStep2_MetodoPagamento() {
    if (_selectedPaymentType == 'local') {
      return Column(
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.blue[50],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.blue[200]!),
            ),
            child: Row(
              children: [
                const Icon(Icons.info, color: Colors.blue),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    "Você pagará ${_currencyFormat.format(valorTotal)} no local do atendimento.",
                    style: const TextStyle(fontSize: 14, color: Colors.blue),
                  ),
                )
              ],
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text("Escolha a forma de pagamento", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: AppColors.primaryPurple)),
        const SizedBox(height: 20),
        Row(
          children: [
            if (aceitaPix)
              Expanded(
                child: _buildPaymentMethodCard(
                  id: 'pix',
                  icon: Icons.qr_code,
                  label: 'PIX',
                  description: 'Instantâneo',
                ),
              ),
            if (aceitaPix && aceitaCartao) const SizedBox(width: 12),
            if (aceitaCartao)
              Expanded(
                child: _buildPaymentMethodCard(
                  id: 'card',
                  icon: Icons.credit_card,
                  label: 'CARTÃO',
                  description: 'Com parcelas',
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildPaymentMethodCard({
    required String id,
    required IconData icon,
    required String label,
    required String description,
  }) {
    bool isSelected = _selectedMethod == id;
    return GestureDetector(
      onTap: () {
        debugPrint('Método selecionado: $id');
        setState(() {
          _selectedMethod = id;
          _recalculateTotals();
        });
      },
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primaryPurple : Colors.white,
          border: Border.all(
            color: isSelected ? AppColors.primaryPurple : Colors.grey[300]!,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Icon(icon, size: 32, color: isSelected ? Colors.white : AppColors.primaryPurple),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: isSelected ? Colors.white : Colors.black,
              ),
            ),
            Text(
              description,
              style: TextStyle(
                fontSize: 11,
                color: isSelected ? Colors.white70 : Colors.grey,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStep3_Confirmacao() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text("Confirmação final", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: AppColors.primaryPurple)),
        const SizedBox(height: 20),
        // Prioriza o tipo de pagamento: se local, mostra mensagem local independente do método selecionado
        if (_selectedPaymentType == 'local')
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.blue.shade200),
            ),
            child: const Text(
              "Pagamento será realizado no local do atendimento.",
              style: TextStyle(fontSize: 14, color: Colors.blue),
            ),
          )
        else if (_selectedMethod == 'card')
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.purple.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.purple.shade200),
            ),
            child: const Text(
              "Você será redirecionado para a página segura de pagamento com cartão do Mercado Pago.",
              style: TextStyle(fontSize: 14, color: Colors.purple),
            ),
          )
        else if (_selectedMethod == 'pix')
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.green.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.green.shade200),
            ),
            child: const Text(
              "Você receberá o QR Code PIX no próximo passo.",
              style: TextStyle(fontSize: 14, color: Colors.green),
            ),
          )
        else
          const SizedBox.shrink(),
      ],
    );
  }

  Widget _buildActionButtons() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: const BoxDecoration(
        color: Colors.white,
        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10)],
      ),
      child: Row(
        children: [
          if (_currentStep > 0)
            Expanded(
              child: OutlinedButton(
                onPressed: _handlePreviousStep,
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppColors.primaryPurple),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: const Text("Voltar", style: TextStyle(color: AppColors.primaryPurple)),
              ),
            ),
          if (_currentStep > 0) const SizedBox(width: 12),
          Expanded(
            child: ElevatedButton(
              onPressed: _isLoading ? null : _handleNextStep,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryPurple,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: _isLoading
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : Text(
                      _currentStep == 2 ? "REVISAR" : "PRÓXIMO",
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResumoHeader(double v) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text("Total a Pagar", style: TextStyle(fontSize: 14, color: Colors.grey)),
          Text(
            _currencyFormat.format(v),
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: AppColors.primaryPurple,
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryItem(IconData icon, String title, String value, {String? subtitle}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 15),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(8)),
            child: Icon(icon, size: 20, color: Colors.grey[700]),
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                if (subtitle != null)
                  Text(subtitle, style: TextStyle(fontSize: 13, color: Colors.grey[600])),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _generatePix(double amount, String desc) async {
    if (shopAccessToken == null) return;
    // show full-screen loading
    if (mounted) Navigator.push(context, MaterialPageRoute(builder: (_) => const AppLoadingPage(message: 'Gerando QR Code...'), fullscreenDialog: true));
    try {
      final user = FirebaseAuth.instance.currentUser!;
      final result = await MercadoPagoService.gerarPix(
        accessToken: shopAccessToken!,
        amount: amount,
        emailCliente: user.email ?? "cliente@app.com",
        description: desc,
      );
      final qrCode64 = result['point_of_interaction']['transaction_data']['qr_code_base64'];
      final copyPaste = result['point_of_interaction']['transaction_data']['qr_code'];
      final paymentId = result['id'].toString();
      if (mounted) {
        _startPixMonitoring(paymentId, amount);
        // close loading
        Navigator.pop(context);
        _showPixModal(qrCode64, copyPaste, paymentId, amount);
      }
    } catch (e) {
      _showError("Erro ao gerar PIX: $e");
    } finally {
      if (mounted) {
        // ensure loading is closed if still open
        try { Navigator.pop(context); } catch (_) {}
        setState(() => _isLoading = false);
      }
    }
  }

  void _startPixMonitoring(String paymentId, double valorPago) {
    if (paymentId.isEmpty) return;
    _timerPolling?.cancel();
    _timerPolling = Timer.periodic(const Duration(seconds: 3), (timer) async {
      try {
        final status = await MercadoPagoService.verificarStatusPix(
          accessToken: shopAccessToken!,
          paymentId: paymentId,
        );
        if (status == 'approved') {
          timer.cancel();
          if (mounted) {
            Navigator.pop(context);
            Navigator.pop(context);
            _saveBooking(metodo: "Pix", status: "confirmado", valorPago: valorPago, paymentId: paymentId);
          }
        }
      } catch (e) {}
    });
  }

  void _showPixModal(String qr64, String copyPaste, String paymentId, double valorPago) {
    // Abre tela full-screen dedicada para o QR code (melhor experiência)
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (c) => PixPaymentPage(
          qrBase64: qr64,
          copyPaste: copyPaste,
          paymentId: paymentId,
          amount: valorPago,
          onPaid: () {
            // Ao confirmar que pagou, fecha a tela e salva o agendamento
            Navigator.pop(c);
            Navigator.pop(context);
            _saveBooking(metodo: "Pix", status: "pendente_verificacao", valorPago: valorPago, paymentId: paymentId);
          },
        ),
      ),
    );
  }

 

  Future<void> _saveBooking({
    required String metodo,
    required String status,
    required double valorPago,
    String? paymentId,
  }) async {
    // show full-screen loading while saving booking
    if (mounted) Navigator.push(context, MaterialPageRoute(builder: (_) => const AppLoadingPage(message: 'Finalizando agendamento...'), fullscreenDialog: true));
    setState(() => _isLoading = true);
    try {
      final user = FirebaseAuth.instance.currentUser!;
      final bookingDate = DateTime(
        widget.date.year,
        widget.date.month,
        widget.date.day,
        widget.time.hour,
        widget.time.minute,
      );

      // Validação: permitir agendamentos múltiplos (configuração da loja)
      final permitirMultiplos = (widget.shopConfig['permitir_multiplos'] ?? true) as bool;
      if (!permitirMultiplos) {
        final now = DateTime.now();
        // Para evitar necessidade de índice, buscamos agendamentos do cliente e filtramos localmente.
        final clientAppts = await FirebaseFirestore.instance
            .collection('appointments')
            .where('clientId', isEqualTo: user.uid)
            .get();
        final conflicting = clientAppts.docs.where((d) {
          final data = d.data();
          final sId = data['shopId']?.toString() ?? '';
          final status = (data['status'] ?? '').toString();
          final ts = data['data_agendamento'];
          DateTime? dt;
          try {
            if (ts is Timestamp) {
              dt = ts.toDate();
            } else if (ts is DateTime) dt = ts;
          } catch (_) { dt = null; }
          if (sId != widget.shopId) return false;
          if (!['agendado', 'confirmado', 'pendente', 'pendente_verificacao'].contains(status)) return false;
          if (dt == null) return false;
          return dt.isAfter(now) || dt.isAtSameMomentAs(now);
        }).toList();
        if (conflicting.isNotEmpty) {
          // show nicer modal instead of snackbar
          if (mounted) await _showConflictDialog();
          setState(() => _isLoading = false);
          return;
        }
      }

      await FirebaseFirestore.instance.collection('appointments').add({
        'shopId': widget.shopId,
        'clientId': user.uid,
        'client_nome': user.displayName,
        'servico_nome': widget.serviceNameOverride ?? widget.serviceDoc['nome'],
        'profissionalId': widget.professionalDoc.id,
        'servicoId': widget.serviceDoc.id,
        'valor_total': valorTotal,
        'valor_pago': valorPago,
        'restante_a_pagar': (valorTotal - valorPago),
        'data_agendamento': Timestamp.fromDate(bookingDate),
        'horario': widget.time.format(context),
        'status': status,
        'metodo_pagamento': metodo,
        'payment_id': paymentId,
        'criado_em': FieldValue.serverTimestamp(),
        'valor_sinal': (metodo.contains('Sinal') || _selectedPaymentType == 'sinal') ? valorPago : 0,
      });

      if (mounted) {
        final svcName = widget.serviceNameOverride ?? widget.serviceDoc['nome'] ?? 'Serviço';
        final profName = widget.professionalDoc['nome'] ?? 'Profissional';
        final dateStr = DateFormat('dd/MM/yyyy').format(widget.date);
        final timeStr = widget.time.format(context);
        final paidFlag = (valorPago > 0);
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(
            builder: (c) => BookingSuccessPage(
              serviceName: svcName,
              professionalName: profName,
              date: dateStr,
              time: timeStr,
              isPaid: paidFlag,
            ),
          ),
          (r) => r.isFirst,
        );
        // close loading if present
        try { Navigator.pop(context); } catch (_) {}
      }
    } catch (e) {
      // close loading if present then show error
      try { Navigator.pop(context); } catch (_) {}
      _showError("Erro salvar: $e");
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _showError(String m) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(m), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _showConflictDialog() async {
    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (ctx) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.event_busy, size: 48, color: Colors.orange),
                const SizedBox(height: 12),
                const Text('Agendamento ativo', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                const Text(
                  'Você já possui um agendamento ativo nesta loja. Aguarde a conclusão antes de agendar novamente.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(ctx), child: const Text('Fechar'))),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: AppColors.primaryPurple),
                        onPressed: () {
                          Navigator.pop(ctx);
                          // open My Appointments (if logged)
                          try {
                            Navigator.push(context, MaterialPageRoute(builder: (_) => const MyAppointmentsPage()));
                          } catch (_) {}
                        },
                        child: const Text('Ver Agendamentos'),
                      ),
                    ),
                  ],
                )
              ],
            ),
          ),
        );
      },
    );
  }
}

// Página full-screen para exibir QR Code PIX com estilo aprimorado
class PixPaymentPage extends StatelessWidget {
  final String qrBase64;
  final String copyPaste;
  final String paymentId;
  final double amount;
  final VoidCallback onPaid;

  const PixPaymentPage({
    super.key,
    required this.qrBase64,
    required this.copyPaste,
    required this.paymentId,
    required this.amount,
    required this.onPaid,
  });

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: AppColors.primaryPurple,
        foregroundColor: Colors.white,
        title: const Text('Pagar via PIX', style: TextStyle(color: Colors.white)),
        elevation: 0,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [AppColors.primaryPurple, Colors.deepPurple.shade400]),
                borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(20), bottomRight: Radius.circular(20)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Valor', style: TextStyle(color: Colors.white70, fontSize: 12)),
                  const SizedBox(height: 6),
                  Text(currency.format(amount), style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
            const SizedBox(height: 18),
            Expanded(
              child: Center(
                child: qrBase64.isNotEmpty
                    ? Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 12)]),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Logo roxo centralizado acima do QR
                            Image.asset('assets/images/logo_purple.png', height: 56),
                            const SizedBox(height: 12),
                            Image.memory(base64Decode(qrBase64)),
                          ],
                        ),
                      )
                    : Column(mainAxisAlignment: MainAxisAlignment.center, children: const [Icon(Icons.qr_code, size: 80, color: Colors.grey), SizedBox(height: 12), Text('Erro ao gerar QR')]),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('Pix Copia e Cola', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(10)),
                    child: Row(
                      children: [
                        Expanded(child: Text(copyPaste, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontFamily: 'monospace'))),
                        IconButton(
                          icon: const Icon(Icons.copy, color: AppColors.primaryPurple),
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: copyPaste));
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Código copiado!")));
                          },
                        )
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: AppColors.primaryPurple, minimumSize: const Size(double.infinity, 52)),
                    onPressed: onPaid,
                    child: const Text('JÁ REALIZEI O PAGAMENTO', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Voltar', style: TextStyle(color: Colors.black54)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}