import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import '../../core/theme/app_colors.dart';
import '../../core/services/mercado_pago_service.dart';
import '../modules/business/subscription_service.dart';
import '../modules/schedule/checkout_transparente_page.dart';
import '../modules/schedule/booking_success_page.dart';
import 'pix_payment_page.dart';
import '../core/services/client_verification_service.dart';
import '../core/services/coupon_service.dart';
import '../core/widgets/loading_page.dart';
import '../modules/clients/my_appointments_page.dart';
import '../modules/clients/client_home_page.dart';

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
  final bool fromSubdomain;

  Map<String, dynamic> get serviceData =>
      serviceDoc.data() as Map<String, dynamic>;

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
    this.fromSubdomain = false,
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

  /// Dados do cartão coletados no WebView (modo "Confirmar e ir para revisão")
  Map<String, dynamic>? _storedCardData;

  double valorTotal = 0.0;
  double valorSinal = 0.0;
  double valorFinalComJuros = 0.0;
  int percentualSinalInt = 30;

  bool exigeSinal = false;
  bool aceitaPix = false;
  bool aceitaCartao = false;
  bool aceitaDinheiro = true;
  String? shopAccessToken;

  // Novos campos para VIP e Aniversário
  bool _isBirthdayMonth = false;
  bool _isProblematic = false;
  String? _userPhone;
  double _birthdayDiscountPercent = 0.0;
  bool _birthdayDiscountEnabled = false;

  // Cupons
  final _couponController = TextEditingController();
  bool _couponApplied = false;
  double _couponDiscountPercent = 0.0;
  String? _appliedCouponId;
  String? _appliedCouponCode;

  Timer? _timerPolling;

  @override
  void initState() {
    super.initState();
    debugPrint(
        '🚀 CheckoutPage: initState | shopId: ${widget.shopId} | serviceId: ${widget.serviceDoc.id}');
    _initializeCheckout();
  }

  @override
  void dispose() {
    _timerPolling?.cancel();
    _couponController.dispose();
    super.dispose();
  }

  Future<void> _initializeCheckout() async {
    await _loadShopPaymentConfig();
    _calculateFinancials();
    _recalculateTotals();
  }

  Future<void> _loadShopPaymentConfig() async {
    try {
      final shopDoc = await FirebaseFirestore.instance
          .collection('shops')
          .doc(widget.shopId)
          .get();
      if (!shopDoc.exists) return;

      final data = shopDoc.data()!;
      final mpData = data['mercadopago'] as Map<String, dynamic>?;
      final config =
          data['config'] as Map<String, dynamic>? ?? widget.shopConfig;

      final percentualFromDb = config['percentual_sinal'];
      int percentualFinal = 30;
      if (percentualFromDb != null) {
        percentualFinal = (percentualFromDb as num).toInt();
      }

      String? token = mpData?['access_token']?.toString() ??
          data['mp_access_token']?.toString();
      final isValidToken = token != null && token.length > 20;

      debugPrint(
          '🔐 Token MP válido: $isValidToken (${token?.length ?? 0} chars)');

      // Verifica o plano da loja para habilitar pagamento online.
      // Usamos getShopPlan(shopId) — não getCurrentPlan() — pois o usuário
      // logado aqui é o CLIENTE, não o dono da loja.
      final shopPlan = await SubscriptionService.getShopPlan(widget.shopId);
      final planAllowsOnline =
          SubscriptionService.planSupportsOnlinePayment(shopPlan);

      // Extrai configurações de restrição e descontos
      final bool birthdayEnabled =
          config['birthday_pix_discount_enabled'] ?? false;
      final double birthdayPercent = double.tryParse(
              config['birthday_pix_discount_percent']?.toString() ?? "0.0") ??
          0.0;

      // Pre-calcula as flags da loja antes de disparar o VIP check
      final bool baseAceitaPix =
          planAllowsOnline && (config['pagamento_pix'] ?? false);
      final bool baseAceitaCartao =
          planAllowsOnline && (config['pagamento_cartao'] ?? false);
      bool baseAceitaDinheiro = config['pagamento_dinheiro'] ?? true;
      final bool baseExigeSinal = config['exigir_sinal'] ?? false;

      // Carrega status do cliente (VIP/Aniversário) se logado antes de dar o setState final
      final user = FirebaseAuth.instance.currentUser;
      bool isBirthday = false;
      bool isProblematic = false;
      String? userPhone;

      if (user != null) {
        final status = await ClientVerificationService.getClientStatus(
            user.uid, widget.shopId);
        isProblematic = status['isProblematic'] ?? false;
        isBirthday = await ClientVerificationService.isBirthdayMonth(user.uid);

        if (isBirthday && birthdayEnabled) {
          final hasUsed =
              await ClientVerificationService.hasUsedBirthdayDiscountInYear(
                  user.uid, widget.shopId);
          if (hasUsed) isBirthday = false;
        }

        // Busca telefone do perfil para validação
        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();
        if (userDoc.exists) {
          userPhone =
              userDoc.data()?['telefone'] ?? userDoc.data()?['whatsapp'];
          if (userPhone != null && userPhone.trim().isEmpty) userPhone = null;
        }
      }

      if (mounted) {
        debugPrint(
            '👤 Status Cliente: Problemático=$isProblematic, Niver=$isBirthday');
        debugPrint('🚫 Restrições: Aceita Dinheiro Final=$baseAceitaDinheiro');

        setState(() {
          shopAccessToken = token;
          aceitaPix = baseAceitaPix;
          aceitaCartao = baseAceitaCartao;
          aceitaDinheiro = baseAceitaDinheiro;
          exigeSinal = baseExigeSinal;
          percentualSinalInt = percentualFinal;

          // Atualiza flags de configuração no estado
          _birthdayDiscountEnabled = birthdayEnabled;
          _birthdayDiscountPercent = birthdayPercent;

          // Atualiza status do cliente no estado
          _isBirthdayMonth = isBirthday;
          _isProblematic = isProblematic;
          _userPhone = userPhone;

          // Seleção inicial inteligente
          if (exigeSinal && (aceitaPix || aceitaCartao)) {
            _selectedPaymentType = 'sinal';
          } else if (aceitaDinheiro) {
            _selectedPaymentType = 'local';
          } else {
            _selectedPaymentType = 'total';
          }

          _paymentConfigLoaded = true;
        });
      }
    } catch (e) {
      debugPrint('❌ Erro config: $e');
      if (mounted) setState(() => _paymentConfigLoaded = true);
    }
  }

  void _calculateFinancials() {
    valorTotal = widget.servicePriceOverride ??
        double.tryParse(widget.serviceDoc['preco'].toString()) ??
        0.0;
    valorSinal = valorTotal * (percentualSinalInt / 100.0);
    valorFinalComJuros = valorTotal;
  }

  void _recalculateTotals() {
    setState(() {
      double base = (_selectedPaymentType == 'sinal') ? valorSinal : valorTotal;
      double totalDiscountPercent = 0.0;

      // Aplica desconto de aniversário se for PIX e estiver no mês
      if (_selectedMethod == 'pix' &&
          _isBirthdayMonth &&
          _birthdayDiscountEnabled &&
          _selectedPaymentType != 'local') {
        totalDiscountPercent += _birthdayDiscountPercent;
      }

      // Aplica desconto de cupom se for PIX e estiver aplicado
      if (_selectedMethod == 'pix' &&
          _couponApplied &&
          _selectedPaymentType != 'local') {
        totalDiscountPercent += _couponDiscountPercent;
      }

      // Limita desconto a 100% (segurança)
      if (totalDiscountPercent > 100) totalDiscountPercent = 100;

      base = base * (1 - (totalDiscountPercent / 100.0));
      valorFinalComJuros = base;
    });
  }

  Future<void> _applyCoupon() async {
    final code = _couponController.text.trim();
    if (code.isEmpty) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() => _isLoading = true);
    final result = await CouponService.validateCoupon(
      shopId: widget.shopId,
      code: code,
      userId: user.uid,
    );
    setState(() => _isLoading = false);

    if (result.isValid) {
      setState(() {
        _couponApplied = true;
        _couponDiscountPercent = result.discountPercent ?? 0.0;
        _appliedCouponId = result.couponId;
        _appliedCouponCode = code.toUpperCase();
      });
      _recalculateTotals();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Cupom '$_appliedCouponCode' aplicado com sucesso!"),
            backgroundColor: Colors.green,
          ),
        );
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.message ?? "Cupom inválido."),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _removeCoupon() {
    setState(() {
      _couponApplied = false;
      _couponDiscountPercent = 0.0;
      _appliedCouponId = null;
      _appliedCouponCode = null;
      _couponController.clear();
    });
    _recalculateTotals();
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text("Cupom removido.")));
  }

  void _handleNextStep() async {
    debugPrint(
        '🚩 Tentativa de Avançar | isProblematic: $_isProblematic | phone: $_userPhone');

    // 1. Bloqueia Problemático
    if (_isProblematic) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Sem disponibilidade para este horário."),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // 2. Bloqueia sem Telefone
    if (_userPhone == null || _userPhone!.isEmpty) {
      _showMissingPhoneDialog();
      return;
    }

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
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text("Aguarde, carregando opções de pagamento...")));
          return;
        }
        // If no online methods are available, silently fallback to "local" payment.
        if (_selectedPaymentType != 'local' && !aceitaPix && !aceitaCartao) {
          if (aceitaDinheiro) {
            setState(() {
              _selectedPaymentType = 'local';
              _recalculateTotals();
              _currentStep = 2;
            });
          } else {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text("A loja não possui meios de pagamento ativos.")));
          }
          break;
        }
        if (_selectedMethod == 'card' && _selectedPaymentType != 'local') {
          double valorParaCobrar =
              (_selectedPaymentType == 'sinal') ? valorSinal : valorTotal;

          setState(() => _isLoading = true);
          final user = FirebaseAuth.instance.currentUser;
          if (user == null) {
            setState(() => _isLoading = false);
            return;
          }

          try {
            final savedCardsSnap = await FirebaseFirestore.instance
                .collection('users')
                .doc(user.uid)
                .collection('saved_cards')
                .where('shopId', isEqualTo: widget.shopId)
                .get();

            setState(() => _isLoading = false);

            if (!mounted) return;
            if (savedCardsSnap.docs.isNotEmpty) {
              final sheetResult = await showModalBottomSheet<dynamic>(
                context: context,
                isScrollControlled: true,
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                ),
                builder: (context) {
                  return _SavedCardsSheet(
                    shopId: widget.shopId,
                    valor: valorParaCobrar,
                    onAddNewCard: () => Navigator.pop(context, 'NEW_CARD'),
                    onCardSelected: (cardData, cvv, installments) {
                      Navigator.pop(context, {
                        'useSavedCard': true,
                        'cardId': cardData['cardId'],
                        'customerId': cardData['customerId'],
                        'cvv': cvv,
                        'installments': installments,
                        'paymentMethodId': cardData['paymentMethodId'],
                      });
                    },
                  );
                },
              );

              if (sheetResult == null) {
                return; // User closed bottom sheet without selecting
              }

              if (sheetResult == 'NEW_CARD') {
                final result = await _pushCheckoutTransparente(valorParaCobrar);
                if (result != null && mounted) {
                  setState(() {
                    _storedCardData = result;
                    _currentStep = 2;
                  });
                }
              } else if (sheetResult is Map<String, dynamic>) {
                setState(() {
                  _storedCardData = sheetResult;
                  _currentStep = 2;
                });
              }
            } else {
              final result = await _pushCheckoutTransparente(valorParaCobrar);
              if (result != null && mounted) {
                setState(() {
                  _storedCardData = result;
                  _currentStep = 2;
                });
              }
            }
          } catch (e) {
            setState(() => _isLoading = false);
            _showError('Erro ao buscar cartões salvos: $e');
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

  Future<Map<String, dynamic>?> _pushCheckoutTransparente(
      double valorParaCobrar) async {
    return await Navigator.push<Map<String, dynamic>>(
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
          skipPlanCheck: true, // plano já verificado no checkout
        ),
      ),
    );
  }

  void _handlePreviousStep() {
    if (_currentStep > 0) setState(() => _currentStep--);
  }

  void _showConfirmationModal() {
    showModalBottomSheet(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => Container(
          height: MediaQuery.of(context).size.height * 0.9,
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
          ),
          child: Column(
            children: [
              // Header Fixo
              Padding(
                padding: const EdgeInsets.fromLTRB(25, 20, 15, 10),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text("Resumo do Pedido",
                        style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: AppColors.primaryPurple)),
                    IconButton(
                        onPressed: () => Navigator.pop(ctx),
                        icon: const Icon(Icons.close))
                  ],
                ),
              ),

              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 25),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text("Confira os detalhes antes de finalizar.",
                          style: TextStyle(color: Colors.grey)),
                      const SizedBox(height: 25),
                      _summaryItem(
                          Icons.cut,
                          "Serviço",
                          widget.serviceNameOverride ??
                              widget.serviceDoc['nome']),
                      _summaryItem(Icons.person, "Profissional",
                          widget.professionalDoc['nome'] ?? ''),
                      _summaryItem(Icons.calendar_today, "Data e Hora",
                          "${DateFormat('dd/MM').format(widget.date)} às ${widget.time.format(context)}"),
                      const Divider(height: 30),

                      // Detalhes Pagamento Scrollable
                      Builder(builder: (context) {
                        String tituloPagamento = "Pagar no Local";
                        String detalhePagamento = "Dinheiro ou Cartão na hora";

                        if (_selectedPaymentType != 'local') {
                          if (_selectedMethod == 'pix') {
                            tituloPagamento = "Pix (QR Code)";
                            detalhePagamento = "Pagamento instantâneo";
                          } else {
                            tituloPagamento = "Cartão de Crédito";
                            detalhePagamento =
                                "Processamento seguro via Mercado Pago";
                          }
                        }
                        return _summaryItem(Icons.payment, "Forma de Pagamento",
                            tituloPagamento,
                            subtitle: detalhePagamento);
                      }),
                      const Divider(height: 30),

                      // CAMPO DE CUPOM (SOMENTE PIX OU TOTAL)
                      if (_selectedMethod == 'pix' &&
                          _selectedPaymentType != 'local') ...[
                        const Text("Tem um cupom?",
                            style: TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 13)),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: SizedBox(
                                height: 45,
                                child: TextField(
                                  controller: _couponController,
                                  decoration: InputDecoration(
                                    hintText: "Código do Cupom",
                                    hintStyle: const TextStyle(fontSize: 13),
                                    enabled: !_couponApplied,
                                    contentPadding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 8),
                                    border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8)),
                                    fillColor: _couponApplied
                                        ? Colors.grey[100]
                                        : Colors.white,
                                    filled: true,
                                  ),
                                  textCapitalization:
                                      TextCapitalization.characters,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            SizedBox(
                              height: 45,
                              child: ElevatedButton(
                                onPressed: () async {
                                  if (_couponApplied) {
                                    _removeCoupon();
                                  } else {
                                    await _applyCoupon();
                                  }
                                  setModalState(() {});
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: _couponApplied
                                      ? Colors.red.shade50
                                      : AppColors.primaryPurple,
                                  foregroundColor: _couponApplied
                                      ? Colors.red
                                      : Colors.white,
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8)),
                                ),
                                child: Text(
                                    _couponApplied ? "REMOVER" : "APLICAR"),
                              ),
                            ),
                          ],
                        ),
                        if (_couponApplied)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              "Cupom aplicado: -${_couponDiscountPercent.round()}%",
                              style: const TextStyle(
                                  color: Colors.green,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold),
                            ),
                          ),
                        const SizedBox(height: 20),
                      ],

                      // Espaçamento para o teclado se necessário
                      SizedBox(
                          height: MediaQuery.of(context).viewInsets.bottom),
                    ],
                  ),
                ),
              ),

              // Rodapé Fixo com Botões (Sempre Visível)
              Container(
                padding: EdgeInsets.fromLTRB(
                    25, 15, 25, MediaQuery.of(context).padding.bottom + 20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      offset: const Offset(0, -4),
                      blurRadius: 10,
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Builder(builder: (context) {
                      String valorExibido = _currencyFormat.format(valorTotal);
                      String textoBotao = _selectedPaymentType == 'local'
                          ? "FINALIZAR AGENDAMENTO"
                          : "FINALIZAR E PAGAR AGORA";

                      if (_selectedPaymentType != 'local') {
                        valorExibido =
                            _currencyFormat.format(valorFinalComJuros);
                      }

                      return Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(15),
                            decoration: BoxDecoration(
                                color: AppColors.primaryPurple
                                    .withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(10)),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text("TOTAL A PAGAR",
                                    style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: AppColors.primaryPurple)),
                                Text(valorExibido,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 20,
                                        color: AppColors.primaryPurple)),
                              ],
                            ),
                          ),
                          const SizedBox(height: 15),
                          SizedBox(
                            width: double.infinity,
                            height: 55,
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.green,
                                  elevation: 2,
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12))),
                              onPressed: () {
                                debugPrint(
                                    '🏁 Clique em Finalizar Modal | isProblematic: $_isProblematic | phone: $_userPhone');

                                // Segurança final: Problemático
                                if (_isProblematic) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                          "Sem disponibilidade para este horário."),
                                      backgroundColor: Colors.orange,
                                    ),
                                  );
                                  return;
                                }

                                // Segurança final: Telefone
                                if (_userPhone == null || _userPhone!.isEmpty) {
                                  Navigator.pop(ctx);
                                  _showMissingPhoneDialog();
                                  return;
                                }

                                Navigator.pop(ctx);
                                if (_selectedPaymentType == 'local') {
                                  _saveBooking(
                                      metodo: "No Local",
                                      status: "agendado",
                                      valorPago: 0);
                                } else {
                                  _executeFinalAction();
                                }
                              },
                              child: Text(textoBotao,
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16)),
                            ),
                          ),
                        ],
                      );
                    }),
                    const SizedBox(height: 8),
                    TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: Text("Voltar e Editar",
                            style: TextStyle(color: Colors.grey[600]))),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _executeFinalAction() async {
    debugPrint(
        'Executando ação final | Tipo: $_selectedPaymentType | Método: $_selectedMethod');

    if (_selectedPaymentType == 'local') {
      debugPrint('→ Pagamento LOCAL');
      _saveBooking(metodo: "No Local", status: "agendado", valorPago: 0);
    } else if (_selectedMethod == 'pix') {
      debugPrint('→ Pagamento PIX');
      double valor =
          (_selectedPaymentType == 'sinal') ? valorSinal : valorTotal;
      String desc = (_selectedPaymentType == 'sinal') ? "Sinal" : "Total";
      _generatePix(valor, desc);
    } else {
      debugPrint('→ Pagamento CARTÃO → cobrando com dados já coletados');
      double valorParaCobrar =
          (_selectedPaymentType == 'sinal') ? valorSinal : valorTotal;
      if (_storedCardData != null) {
        if (_storedCardData!['useSavedCard'] == true) {
          final fUser = FirebaseAuth.instance.currentUser;
          await _processarPagamentoCartaoSalvo(
            valor: valorParaCobrar,
            cardId: _storedCardData!['cardId'] as String,
            customerId: _storedCardData!['customerId'] as String,
            securityCode: _storedCardData!['cvv'] as String,
            installments: _storedCardData!['installments'] as int,
            email: fUser?.email ?? '',
            paymentMethodId: _storedCardData!['paymentMethodId'] as String?,
          );
        } else {
          await _processarPagamentoComCartaoArmazenado(
            valor: valorParaCobrar,
            cardToken: _storedCardData!['cardToken'] as String,
            installments: _storedCardData!['installments'] as int,
            email: _storedCardData!['email'] as String,
            paymentMethodId: _storedCardData!['paymentMethodId'] as String?,
            issuerId: _storedCardData!['issuerId'],
          );
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text(
                  "Dados do cartão não encontrados. Preencha o cartão novamente.")),
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
        Uri.parse(
            'https://us-central1-wismart-118c3.cloudfunctions.net/criarPagamento'),
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

  Future<void> _processarPagamentoCartaoSalvo({
    required double valor,
    required String cardId,
    required String customerId,
    required String securityCode,
    required int installments,
    required String email,
    String? paymentMethodId,
  }) async {
    setState(() => _isLoading = true);
    try {
      final idToken = await _getPaymentIdToken();
      if (idToken == null) return;

      final response = await http.post(
        Uri.parse(
            'https://us-central1-wismart-118c3.cloudfunctions.net/cobrarCartaoSalvo'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'data': {
            'cardId': cardId,
            'customerId': customerId,
            'securityCode': securityCode,
            'email': email,
            'installments': installments,
            'amount': valor,
            'shopId': widget.shopId,
            'description': "Reserva: ${widget.serviceDoc['nome'] ?? 'Serviço'}",
            'idToken':
                idToken, // Required for Auth validation in our onCall function
          }
        }),
      );

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result['result'] != null &&
            result['result']['status'] == 'approved') {
          await _saveBooking(
            metodo: "Cartão Salvo",
            status: "confirmado",
            valorPago: valor,
            paymentId: result['result']['id'].toString(),
          );
        } else if (result['result'] != null &&
            result['result']['status'] == 'pending') {
          _showError(
              'Seu pagamento está em análise. Tente novamente mais tarde.');
        } else {
          _showError(result['error']?.toString() ?? 'Pagamento recusado.');
        }
      } else {
        final error = jsonDecode(response.body);
        _showError(error['error']?.toString() ?? 'Erro no pagamento');
      }
    } catch (e) {
      _showError('Erro ao processar pagamento com cartão salvo: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<String?> _getPaymentIdToken() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _showError(
          'Não foi possível validar sua sessão para o pagamento. Tente novamente.');
      return null;
    }
    try {
      return await user.getIdToken(true);
    } catch (_) {
      try {
        return await user.getIdToken();
      } catch (_) {
        _showError(
            'Não foi possível validar sua sessão para o pagamento. Tente novamente.');
        return null;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    double valorExibido = valorFinalComJuros;
    if (_selectedPaymentType == 'local') {
      valorExibido = valorTotal;
    } else if (_selectedPaymentType == 'sinal' && _selectedMethod != 'card') {
      valorExibido = valorSinal;
    }

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
                    if (_currentStep == 0) ...[
                      if (_isBirthdayMonth && _birthdayDiscountEnabled)
                        _buildBirthdayBanner(),
                      _buildStep1TipoValor(),
                    ],
                    if (_currentStep == 1) ...[
                      if (_isBirthdayMonth && _birthdayDiscountEnabled)
                        _buildBirthdayBanner(),
                      _buildStep2MetodoPagamento(),
                    ],
                    if (_currentStep == 2) _buildStep3Confirmacao(),
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
                      color:
                          isActive ? AppColors.primaryPurple : Colors.grey[300],
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
                      fontWeight:
                          isCurrent ? FontWeight.bold : FontWeight.normal,
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
              valueColor:
                  AlwaysStoppedAnimation<Color>(AppColors.primaryPurple),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStep1TipoValor() {
    if (!_paymentConfigLoaded) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Column(
            children: const [
              SizedBox(height: 8),
              CircularProgressIndicator(),
              SizedBox(height: 12),
              Text("Carregando opções de pagamento...",
                  style: TextStyle(color: Colors.grey)),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text("O que deseja pagar?",
            style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 18,
                color: AppColors.primaryPurple)),
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
        if (aceitaDinheiro)
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

  Widget _buildBirthdayBanner() {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFFD700), Color(0xFFFFA500)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(15),
        boxShadow: [
          BoxShadow(
            color: Colors.orange.withValues(alpha: 0.3),
            blurRadius: 8,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: Row(
        children: [
          const Icon(Icons.cake, color: Colors.white, size: 30),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Parabéns! É seu mês!",
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                Text(
                  "Você ganhou ${_birthdayDiscountPercent.round()}% de desconto pagando com PIX.",
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    "⚠️ Necessário apresentar documento com foto no dia do atendimento. Caso contrário, será cobrado o valor integral.",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
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
          color: isSelected
              ? AppColors.primaryPurple.withValues(alpha: 0.08)
              : Colors.white,
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
                  color:
                      isSelected ? AppColors.primaryPurple : Colors.grey[400]!,
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
                  Text(title,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 15)),
                  Text(subtitle,
                      style: const TextStyle(fontSize: 12, color: Colors.grey)),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: badgeColor.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    badge,
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: badgeColor),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _currencyFormat.format(amount),
                  style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: AppColors.primaryPurple),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStep2MetodoPagamento() {
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

    // Guard: if neither PIX nor card is available, show informative message
    if (!aceitaPix && !aceitaCartao) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.orange[50],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.orange[200]!),
        ),
        child: Row(
          children: [
            Icon(Icons.info_outline, color: Colors.orange[700]),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Esta loja aceita apenas pagamento pessoalmente. Retorne e selecione "Pagar Pessoalmente".',
                style: TextStyle(fontSize: 13),
              ),
            ),
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text("Escolha a forma de pagamento",
            style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 18,
                color: AppColors.primaryPurple)),
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
            Icon(icon,
                size: 32,
                color: isSelected ? Colors.white : AppColors.primaryPurple),
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

  Widget _buildStep3Confirmacao() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text("Confirmação final",
            style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 18,
                color: AppColors.primaryPurple)),
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
                child: const Text("Voltar",
                    style: TextStyle(color: AppColors.primaryPurple)),
              ),
            ),
          if (_currentStep > 0) const SizedBox(width: 12),
          Expanded(
            child: ElevatedButton(
              onPressed: _isLoading ? null : _handleNextStep,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryPurple,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: _isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2))
                  : Text(
                      _currentStep == 2 ? "REVISAR" : "PRÓXIMO",
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.bold),
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
      decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(16)),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text("Total a Pagar",
              style: TextStyle(fontSize: 14, color: Colors.grey)),
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

  Widget _summaryItem(IconData icon, String title, String value,
      {String? subtitle}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 15),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(8)),
            child: Icon(icon, size: 20, color: Colors.grey[700]),
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(fontSize: 12, color: Colors.grey)),
                Text(value,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w600)),
                if (subtitle != null)
                  Text(subtitle,
                      style: TextStyle(fontSize: 13, color: Colors.grey[600])),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _generatePix(double amount, String desc) async {
    if (shopAccessToken == null) {
      _showError(
          'Esta loja não configurou os meios de pagamento online ainda.');
      return;
    }
    bool pixShown = false; // Tracks if QR Code page was successfully opened
    // show full-screen loading
    if (mounted) {
      Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) =>
                  const AppLoadingPage(message: 'Gerando QR Code...'),
              fullscreenDialog: true));
    }
    try {
      final user = FirebaseAuth.instance.currentUser!;
      final result = await MercadoPagoService.gerarPix(
        shopId: widget.shopId,
        amount: amount,
        emailCliente: user.email ?? "cliente@app.com",
        description: desc,
      );
      // O MercadoPagoService.gerarPix já retorna Map<String, dynamic>.from(result.data)
      final qrCode64 = result['point_of_interaction']?['transaction_data']
          ?['qr_code_base64'];
      final copyPaste =
          result['point_of_interaction']?['transaction_data']?['qr_code'];
      final paymentId = result['id']?.toString() ?? '';

      if (qrCode64 == null || copyPaste == null || paymentId.isEmpty) {
        throw Exception("Dados do PIX incompletos na resposta do servidor.");
      }

      if (mounted) {
        _startPixMonitoring(paymentId, amount);
        // close loading page
        Navigator.pop(context);
        // Mark as shown BEFORE pushing so the finally block won't close it
        pixShown = true;
        _showPixModal(qrCode64, copyPaste, paymentId, amount);
      }
    } catch (e) {
      _showError("Erro ao gerar PIX: $e");
    } finally {
      if (mounted) {
        if (!pixShown) {
          // Only pop the loading page if PIX screen was NOT shown
          // (i.e., an error occurred before we could show the QR code)
          try {
            Navigator.pop(context);
          } catch (_) {}
        }
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
          shopId: widget.shopId,
          paymentId: paymentId,
        );
        if (status == 'approved') {
          timer.cancel();
          if (mounted) {
            Navigator.pop(context);
            Navigator.pop(context);
            _saveBooking(
                metodo: "Pix",
                status: "confirmado",
                valorPago: valorPago,
                paymentId: paymentId);
          }
        }
      } catch (e) {
        debugPrint('Erro ao verificar status PIX: $e');
      }
    });
  }

  void _showPixModal(
      String qr64, String copyPaste, String paymentId, double valorPago) {
    // Abre tela full-screen dedicada para o QR code
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (c) => PixPaymentPage(
          qrBase64: qr64,
          copyPaste: copyPaste,
          paymentId: paymentId,
          amount: valorPago,
          onManualCheck: () async {
            // Verifica o status do PIX na hora que o usuário clica no botão
            try {
              final status = await MercadoPagoService.verificarStatusPix(
                shopId: widget.shopId,
                paymentId: paymentId,
              );
              if (status == 'approved') {
                return true;
              }
              return false;
            } catch (e) {
              debugPrint('Erro na verificação manual PIX: $e');
              return false;
            }
          },
          onPaid: () {
            // Cancelar o polling automático se o manual confirmou
            _timerPolling?.cancel();
            // Ao confirmar que pagou, fecha a tela e salva o agendamento
            Navigator.pop(c);
            Navigator.pop(context);
            _saveBooking(
                metodo: "Pix",
                status: "confirmado",
                valorPago: valorPago,
                paymentId: paymentId);
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
    if (mounted) {
      Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) =>
                  const AppLoadingPage(message: 'Finalizando agendamento...'),
              fullscreenDialog: true));
    }
    setState(() => _isLoading = true);
    // Extract context-dependent values before any async gap
    final horarioStr = widget.time.format(context);
    try {
      final user = FirebaseAuth.instance.currentUser!;
      final bookingDate = DateTime(
        widget.date.year,
        widget.date.month,
        widget.date.day,
        widget.time.hour,
        widget.time.minute,
      );

      final int duration =
          int.tryParse(widget.serviceData['tempo_min']?.toString() ?? '30') ??
              30;

      // Validação de Double-Booking via Cloud Function no Backend
      try {
        final functions = FirebaseFunctions.instance;
        final result = await functions.httpsCallable('checkAvailability').call({
          'professionalId': widget.professionalDoc.id,
          'startTime': bookingDate.toIso8601String(),
          'duration': duration,
        });

        if (result.data['available'] != true) {
          if (mounted) {
            // Fecha o loading de "Finalizando agendamento..."
            Navigator.pop(context);
            await showDialog(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('Horário Indisponível'),
                content: const Text(
                    'Infelizmente este horário foi preenchido por outra pessoa enquanto você finalizava. Por favor, escolha outro horário.'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('OK'),
                  ),
                ],
              ),
            );
          }
          setState(() => _isLoading = false);
          return;
        }
      } catch (e) {
        debugPrint('Erro na validação de disponibilidade (backend): $e');
        // Em caso de erro na função, procedemos com a validação local já existente abaixo
      }

      // Validação: permitir agendamentos múltiplos (configuração da loja)
      final permitirMultiplos =
          (widget.shopConfig['permitir_multiplos'] ?? true) as bool;
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
            } else if (ts is DateTime) {
              dt = ts;
            }
          } catch (_) {
            dt = null;
          }
          if (sId != widget.shopId) {
            return false;
          }
          if (!['agendado', 'confirmado', 'pendente', 'pendente_verificacao']
              .contains(status)) {
            return false;
          }
          if (dt == null) {
            return false;
          }
          return dt.isAfter(now) || dt.isAtSameMomentAs(now);
        }).toList();
        if (conflicting.isNotEmpty) {
          // show nicer modal instead of snackbar
          if (mounted) await _showConflictDialog();
          setState(() => _isLoading = false);
          return;
        }
      }

      final profData = widget.professionalDoc.data() as Map<String, dynamic>;
      final DateTime endDate = bookingDate.add(Duration(minutes: duration));

      await FirebaseFirestore.instance.collection('appointments').add({
        'shopId': widget.shopId,
        'clientId': user.uid,
        'client_nome': user.displayName ?? user.email ?? 'Cliente',
        'servico_nome': widget.serviceNameOverride ?? widget.serviceDoc['nome'],
        'profissionalId': widget.professionalDoc.id,
        'profissional_nome': profData['nome'] ?? 'Profissional',
        'profissional_foto': profData['foto_url'],
        'profissional_cargo': profData['cargo'] ?? '',
        'servicoId': widget.serviceDoc.id,
        'valor_total': valorTotal,
        'valor_pago': valorPago,
        'restante_a_pagar': (valorTotal - valorPago),
        'duracao_min': duration,
        'data_agendamento': Timestamp.fromDate(bookingDate),
        'data_fim': Timestamp.fromDate(endDate),
        'horario': horarioStr,
        'status': status,
        'metodo_pagamento': metodo,
        'payment_id': paymentId,
        'birthday_discount_applied': (_selectedMethod == 'pix' &&
            _isBirthdayMonth &&
            _birthdayDiscountEnabled &&
            _selectedPaymentType != 'local'),
        'coupon_applied': _couponApplied,
        'coupon_code': _appliedCouponCode,
        'coupon_discount_percent': _couponDiscountPercent,
        'criado_em': FieldValue.serverTimestamp(),
        'valor_sinal':
            (metodo.contains('Sinal') || _selectedPaymentType == 'sinal')
                ? valorPago
                : 0,
      });

      // Se usou cupom, marca como usado para o cliente
      if (_couponApplied && _appliedCouponId != null) {
        await CouponService.markCouponAsUsed(
          shopId: widget.shopId,
          couponId: _appliedCouponId!,
          userId: user.uid,
          appointmentId:
              "", // Será preenchido pelo backend se necessário ou deixamos vazio já que o doc é o ID do usuário
        );
      }

      if (mounted) {
        final svcName = widget.serviceNameOverride ??
            widget.serviceDoc['nome'] ??
            'Serviço';
        final profName = widget.professionalDoc['nome'] ?? 'Profissional';
        final dateStr = DateFormat('dd/MM/yyyy').format(widget.date);
        final timeStr = horarioStr;
        final paidFlag = (valorPago > 0);
        // Close the loading page first, then navigate
        try {
          Navigator.pop(context);
        } catch (_) {}
        if (widget.fromSubdomain) {
          // Veio de subdomínio: volta para ClientHomePage com aba Agendamentos
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(
                builder: (_) => const ClientHomePage(initialTabIndex: 2)),
            (_) => false,
          );
        } else {
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
        }
      }
    } catch (e) {
      // close loading if present then show error
      try {
        if (mounted) Navigator.pop(context);
      } catch (_) {}
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
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.event_busy, size: 48, color: Colors.orange),
                const SizedBox(height: 12),
                const Text('Agendamento ativo',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                const Text(
                  'Você já possui um agendamento ativo nesta loja. Aguarde a conclusão antes de agendar novamente.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                        child: OutlinedButton(
                            onPressed: () => Navigator.pop(ctx),
                            child: const Text('Fechar'))),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primaryPurple),
                        onPressed: () {
                          Navigator.pop(ctx);
                          // open My Appointments (if logged)
                          try {
                            Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (_) =>
                                        const MyAppointmentsPage()));
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

  void _showMissingPhoneDialog() {
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.contact_phone, color: Colors.orange),
            SizedBox(width: 10),
            Text("Telefone Obrigatório"),
          ],
        ),
        content: const Text(
            "Para realizar um agendamento, você precisa ter um telefone cadastrado em seu perfil.\n\nPor favor, atualize seus dados antes de continuar."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("CANCELAR", style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pop(context, 'edit_profile');
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryPurple,
              foregroundColor: Colors.white,
            ),
            child: const Text("EDITAR PERFIL"),
          ),
        ],
      ),
    );
  }
}

class _SavedCardsSheet extends StatefulWidget {
  final String shopId;
  final double valor;
  final VoidCallback onAddNewCard;
  final Function(Map<String, dynamic> cardData, String cvv, int installments)
      onCardSelected;

  const _SavedCardsSheet({
    required this.shopId,
    required this.valor,
    required this.onAddNewCard,
    required this.onCardSelected,
  });

  @override
  State<_SavedCardsSheet> createState() => _SavedCardsSheetState();
}

class _SavedCardsSheetState extends State<_SavedCardsSheet> {
  String? _selectedCardId;
  final _cvvController = TextEditingController();
  final int _installments = 1;

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const SizedBox.shrink();

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 20,
        right: 20,
        top: 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text("Meus Cartões",
              style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: AppColors.primaryPurple)),
          const SizedBox(height: 15),
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('users')
                .doc(user.uid)
                .collection('saved_cards')
                .where('shopId', isEqualTo: widget.shopId)
                .orderBy('createdAt', descending: true)
                .snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Center(
                    child: Padding(
                        padding: EdgeInsets.all(20),
                        child: CircularProgressIndicator()));
              }
              final docs = snapshot.data!.docs;
              if (docs.isEmpty) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  widget.onAddNewCard();
                });
                return const SizedBox.shrink();
              }
              return ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: docs.length,
                itemBuilder: (context, index) {
                  final data = docs[index].data() as Map<String, dynamic>;
                  final isSelected = _selectedCardId == docs[index].id;
                  return InkWell(
                    onTap: () =>
                        setState(() => _selectedCardId = docs[index].id),
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        border: Border.all(
                            color: isSelected
                                ? AppColors.primaryPurple
                                : Colors.grey.shade300,
                            width: isSelected ? 2 : 1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              if (data['thumbnail'] != null &&
                                  data['thumbnail'].isNotEmpty)
                                Image.network(data['thumbnail'],
                                    width: 40,
                                    height: 25,
                                    errorBuilder: (_, __, ___) =>
                                        const Icon(Icons.credit_card)),
                              const SizedBox(width: 10),
                              Expanded(
                                  child: Text(
                                      "•••• ${data['lastFourDigits']} - ${data['paymentMethodName'] ?? 'Cartão'}",
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold))),
                              if (isSelected)
                                const Icon(Icons.check_circle,
                                    color: AppColors.primaryPurple),
                            ],
                          ),
                          if (isSelected) ...[
                            const SizedBox(height: 15),
                            Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: _cvvController,
                                    keyboardType: TextInputType.number,
                                    maxLength: 4,
                                    obscureText: true,
                                    decoration: const InputDecoration(
                                      labelText: "CVV",
                                      counterText: "",
                                      border: OutlineInputBorder(),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 15),
                                Expanded(
                                  child: ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                        backgroundColor:
                                            AppColors.primaryPurple,
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 15)),
                                    onPressed: () {
                                      if (_cvvController.text.length < 3) {
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(const SnackBar(
                                                content:
                                                    Text('CVV inválido.')));
                                        return;
                                      }
                                      widget.onCardSelected(data,
                                          _cvvController.text, _installments);
                                    },
                                    child: const Text("Usar Cartão",
                                        style: TextStyle(color: Colors.white)),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            icon: const Icon(Icons.add),
            label: const Text("Pagar com um novo cartão"),
            onPressed: widget.onAddNewCard,
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}
