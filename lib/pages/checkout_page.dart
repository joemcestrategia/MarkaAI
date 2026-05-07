import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import '../../core/theme/app_colors.dart';
import '../../core/services/mercado_pago_service.dart';
import '../modules/business/subscription_service.dart';
import '../modules/schedule/checkout_transparente_page.dart';
import '../modules/schedule/booking_success_page.dart';
import 'pix_payment_page.dart';
import '../core/widgets/birthday_celebration_modal.dart';
import '../core/services/client_verification_service.dart';
import '../core/services/coupon_service.dart';
import '../core/services/plan_features_service.dart';
import '../core/constants/plan_features.dart';
import '../core/widgets/loading_page.dart';
import '../modules/clients/my_appointments_page.dart';
import '../modules/clients/client_home_page.dart';
import '../core/widgets/intentional_friction_modal.dart';
import '../core/widgets/coupon_invalid_modal.dart';

class CheckoutPage extends StatefulWidget {
  final String shopId;
  final Map<String, dynamic> shopData;
  final Map<String, dynamic> shopConfig;
  final Map<String, dynamic> serviceDoc;
  final Map<String, dynamic> professionalDoc;
  final DateTime date;
  final TimeOfDay time;
  final String? serviceNameOverride;
  final double? servicePriceOverride;
  final bool fromSubdomain;
  final String? rescheduleId; // Novo parâmetro para evitar duplicação

  Map<String, dynamic> get serviceData => serviceDoc;

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
    this.selectedVariation,
    this.clientStatus,
    this.rescheduleId,
  });

  final Map<String, dynamic>? selectedVariation;
 
  final Map<String, bool>? clientStatus;

  @override
  State<CheckoutPage> createState() => _CheckoutPageState();
}

class _CheckoutPageState extends State<CheckoutPage> with TickerProviderStateMixin {
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
  String? _shopPublicKey;

  // Novos campos para VIP e Aniversário
  bool _isBirthdayMonth = false;
  bool _isProblematic = false;
  bool _isNewClient = false;
  Map<String, dynamic>? _shopClientData;
  String? _userPhone;
  String? _userEmail;
  String? _userName;
  String? _userPhotoUrl;
  double _birthdayDiscountPercent = 0.0;
  bool _birthdayDiscountEnabled = false;
  bool _isVip = false;
  bool _trustedOnlyPayLocal = false;
  bool _birthdayGiftAccepted = false;
  double _cardTaxPercent = 0.0;
  String? _userCpf;
 
  // Cupons
  final _couponController = TextEditingController();
  bool _couponApplied = false;
  double _couponDiscountPercent = 0.0;
  String? _appliedCouponId;
  String? _appliedCouponCode;
  Map<String, dynamic>? _appliedCoupon;

  String? _preSavedAppointmentId;
  bool _isConfirmingPayment = false;

  Timer? _timerPolling;
  
  // Controladores de Animação
  late AnimationController _couponAnimationController;
  late Animation<double> _couponScaleAnimation;
  double _animatedPrice = 0.0;

  @override
  void initState() {
    super.initState();
    debugPrint(
        '🚀 CheckoutPage: initState | shopId: ${widget.shopId} | serviceId: ${widget.serviceDoc['id']}');
        
    _couponAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _couponScaleAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.05), weight: 50),
      TweenSequenceItem(tween: Tween(begin: 1.05, end: 1.0), weight: 50),
    ]).animate(CurvedAnimation(parent: _couponAnimationController, curve: Curves.easeInOut));

    _initializeCheckout();
  }

  @override
  void dispose() {
    _timerPolling?.cancel();
    _couponController.dispose();
    _couponAnimationController.dispose();
    super.dispose();
  }

  Future<void> _initializeCheckout() async {
    await _loadShopPaymentConfig();
    _calculateFinancials();
    _recalculateTotals();
  }

  Future<void> _loadShopPaymentConfig() async {
    try {
      final doc = await Supabase.instance.client
          .from('shops')
          .select()
          .eq('id', widget.shopId)
          .maybeSingle();
          
      if (doc == null) return;

      final data = doc as Map<String, dynamic>;
      final mpData = data['mercadopago'] as Map<String, dynamic>? ?? {};
      final config = data['config'] as Map<String, dynamic>? ?? widget.shopConfig;

      final percentualFromDb = config['percentual_sinal'];
      int percentualFinal = 30;
      if (percentualFromDb != null) {
        percentualFinal = (percentualFromDb as num).toInt();
      }

      String? token = mpData['access_token']?.toString() ??
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
      
      // 🆕 Pega as features completas do plano da loja
      final PlanFeatures shopFeatures = PlanFeaturesService.getFeaturesForShop(data);
      final double cardTax = double.tryParse(
              (config['tax_percent'] ?? config['porcentagem_a_vista'] ?? "0.0")
                  .toString()) ??
          0.0;
      debugPrint('💳 [Checkout] Taxa de cartão carregada: $cardTax%');

      // Pre-calcula as flags da loja antes de disparar o VIP check
      // isValidToken: MP must be connected for online methods to be available
      final bool baseAceitaPix =
          planAllowsOnline && isValidToken && (config['pagamento_pix'] ?? false);
      final bool baseAceitaCartao =
          planAllowsOnline && isValidToken && (config['pagamento_cartao'] ?? false);
      bool baseAceitaDinheiro = config['pagamento_dinheiro'] ?? true;
      final bool baseExigeSinal = config['exigir_sinal'] ?? false;
      final bool trustedOnly = config['trusted_only_pay_in_person'] ?? false;

      // Carrega status do cliente (VIP/Aniversário) se logado antes de dar o setState final
      final user = Supabase.instance.client.auth.currentUser;
      bool isBirthday = false;
      bool isProblematic = false;
      bool isVip = false;
      // _isVip is set by _checkVipStatus
      // _userPhone is set by _loadAuthStatus

      if (user != null) {
        final status = widget.clientStatus ?? await ClientVerificationService.getClientStatus(
            user.id, widget.shopId);
        isProblematic = status['isProblematic'] ?? false;
        isVip = status['isVip'] ?? false;

        // Carrega dados do cliente na loja para validação de cupons
        try {
          final shopClientResult = await Supabase.instance.client
              .from('shop_clients')
              .select('classification, manual_tags')
              .eq('user_id', user.id)
              .eq('shop_id', widget.shopId)
              .maybeSingle();
          _shopClientData = shopClientResult;
        } catch (_) {}
        
        // 🆕 Verifica aniversário focado no mês do agendamento (regra de negócio confirmada)
        if (shopFeatures.birthdayDiscount) {
          isBirthday = await ClientVerificationService.isBirthdayMonth(user.id,
              targetMonth: widget.date.month);
        }

        if (isBirthday && birthdayEnabled) {
          final hasUsed =
              await ClientVerificationService.hasUsedBirthdayDiscountInYear(
                  user.id, widget.shopId);
          if (hasUsed) isBirthday = false;
        }

        // Verifica se é novo cliente para validação de cupons
        // VIP e problemáticos nunca são novos clientes, independente do shop_clients
        _isNewClient = (isVip || isProblematic)
            ? false
            : await CouponService.checkIsNewClient(
                clientId: user.id,
                shopId: widget.shopId,
                currentClassification:
                    _shopClientData?['classification']?.toString(),
              );

        // Busca telefone do perfil para validação
        final userDoc = await Supabase.instance.client
            .from('users')
            .select()
            .eq('id', user.id)
            .maybeSingle();

        if (userDoc != null) {
          _userPhone = userDoc['phone']?.toString();
          if (_userPhone != null && _userPhone!.trim().isEmpty) _userPhone = null;
          _userCpf = userDoc['cpf']?.toString();
          if (_userCpf != null && _userCpf!.trim().isEmpty) _userCpf = null;
          _userPhotoUrl = userDoc['photo_url']?.toString();
          if (_userPhotoUrl != null && _userPhotoUrl!.trim().isEmpty) _userPhotoUrl = null;
          final dbName = userDoc['name']?.toString();
          if (dbName != null && dbName.trim().isNotEmpty) _userName = dbName.trim();
        }
        // Foto do Google vinda dos metadados de auth (prioridade)
        final authPhoto = user.userMetadata?['avatar_url']?.toString() ?? user.userMetadata?['picture']?.toString();
        if (authPhoto != null && authPhoto.isNotEmpty) _userPhotoUrl = authPhoto;
        _userEmail = user.email;
      }

      if (mounted) {
        debugPrint(
            '👤 Status Cliente: Problemático=$isProblematic, Niver=$isBirthday, VIP=$isVip');
        debugPrint('🚫 Restrições: Aceita Dinheiro Final=$baseAceitaDinheiro');

        setState(() {
          shopAccessToken = token;
          _shopPublicKey = mpData['public_key']?.toString() ?? data['mp_public_key']?.toString();
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
          _isVip = isVip;
          _userPhone = _userPhone;
          _userCpf = _userCpf;
          _trustedOnlyPayLocal = trustedOnly;
          // _isNewClient e _shopClientData já foram atribuídos diretamente
          _cardTaxPercent = cardTax;

          // Automação do Desconto de Aniversário
          if (_isBirthdayMonth && _birthdayDiscountEnabled) {
            _birthdayGiftAccepted = true;
            debugPrint('🎂 [Checkout] Desconto de aniversário aplicado automaticamente.');
          }

          // Lógica VIP: Se a loja restringe local apenas para VIPs
          if (_trustedOnlyPayLocal) {
            // Se for VIP, habilitamos (mesmo que baseAceitaDinheiro seja false)
            // Se NÃO for VIP, desabilitamos.
            aceitaDinheiro = _isVip;
          } else {
            // Caso padrão (sem restrição VIP): usa o switch master
            aceitaDinheiro = baseAceitaDinheiro;
          }

          // Seleção inicial inteligente: Prioriza online para forçar atrito se escolher local
          if (exigeSinal && (aceitaPix || aceitaCartao)) {
            _selectedPaymentType = 'sinal';
          } else if (aceitaPix || aceitaCartao) {
            _selectedPaymentType = 'total';
          } else if (aceitaDinheiro) {
            _selectedPaymentType = 'local';
          } else {
            // Fallback
            _selectedPaymentType = 'total';
          }

          _paymentConfigLoaded = true;
        });

        // Se for aniversário e tiver desconto, mostra a modal bonita
        debugPrint('🎂 [REGRAS DE ANIVERSÁRIO]');
        debugPrint('   - Mês de Nascimento do Cliente: (Verifique log [BirthdayCheck] acima)');
        debugPrint('   - Mês Escolhido para Agendamento: ${widget.date.month}');
        debugPrint('   - Loja Habilitou Desconto? $birthdayEnabled');
        debugPrint('   - Cliente já usou este ano? (Verifique log abaixo)');
        debugPrint('   - RESULTADO FINAL: isBirthday=$isBirthday');
        
        if (isBirthday && birthdayEnabled) {
          final hasUsed =
              await ClientVerificationService.hasUsedBirthdayDiscountInYear(
                  user!.id, widget.shopId);
          debugPrint('   - hasUsedBirthdayDiscountInYear: $hasUsed');
          if (!hasUsed) {
            debugPrint('   - Triggering _showBirthdayModal()');
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _showBirthdayModal();
            });
          } else {
            debugPrint('   - Modal NOT triggered: Discount already used this year.');
          }
        } else {
          debugPrint('   - Modal NOT triggered: isBirthday=$isBirthday, birthdayEnabled=$birthdayEnabled');
        }
      }
    } catch (e) {
      debugPrint('❌ Erro config: $e');
      if (mounted) setState(() => _paymentConfigLoaded = true);
    }
  }

  void _calculateFinancials() {
    valorTotal = widget.servicePriceOverride ??
        double.tryParse(widget.serviceDoc['price'].toString()) ??
        0.0;
    valorSinal = valorTotal * (percentualSinalInt / 100.0);
    valorFinalComJuros = valorTotal;
  }

  void _recalculateTotals() {
    setState(() {
      double base = (_selectedPaymentType == 'sinal') ? valorSinal : valorTotal;
      double totalDiscountPercent = 0.0;

      // Aplica desconto de aniversário se estiver no mês e o presente foi aceito
      if (_isBirthdayMonth &&
          _birthdayDiscountEnabled &&
          _birthdayGiftAccepted) {
        totalDiscountPercent += _birthdayDiscountPercent;
      }

      // Aplica desconto de cupom se estiver aplicado (qualquer método de pagamento)
      if (_couponApplied) {
        totalDiscountPercent += _couponDiscountPercent;
      }

      // Para pagamentos online, limita a 99% para não gerar valor R$0,00
      // (gateways rejeitam transações com valor zero)
      final bool isOnlinePayment = _selectedPaymentType != 'local';
      final double maxDiscount = isOnlinePayment ? 99.0 : 100.0;
      if (totalDiscountPercent > maxDiscount) totalDiscountPercent = maxDiscount;

      base = base * (1 - (totalDiscountPercent / 100.0));

      // Aplica taxa de cartão se for cartão de crédito e não for pagamento local
      if (_selectedMethod == 'card' && _selectedPaymentType != 'local') {
        base = base * (1 + (_cardTaxPercent / 100.0));
      }

      // Segurança: nunca permite valor negativo
      if (base < 0) base = 0;

      debugPrint('💰 [Recalculate] Método: $_selectedMethod, Taxa: $_cardTaxPercent%, Base: $base');
      valorFinalComJuros = base;
      debugPrint('✅ [Recalculate] Valor Final: $valorFinalComJuros');
    });
  }

  Future<void> _applyCoupon() async {
    final code = _couponController.text.trim();
    if (code.isEmpty) return;

    // Segurança: impede aplicação dupla de cupom
    if (_couponApplied) return;

    // 🆕 Verifica se o plano permite cupons antes de validar
    final shopFeatures = PlanFeaturesService.getFeaturesForShop(widget.shopData);
    if (!shopFeatures.coupons) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Esta loja não possui o módulo de cupons ativo."),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    setState(() => _isLoading = true);
    // Combina classificação real com tags sintéticas baseadas em status booleano.
    // Garante que VIP/_isProblematic funcionem mesmo quando shop_clients não é
    // legível via RLS para o cliente (ex: acesso bloqueado por política).
    final String? effectiveClassification =
        _shopClientData?['classification']?.toString() ??
            (_isVip
                ? 'VIP'
                : (_isProblematic ? 'Problemático' : null));
    final List<String> effectiveTags = [
      ...List<String>.from(_shopClientData?['manual_tags'] ?? []),
      if (_isVip && effectiveClassification != 'VIP') 'VIP',
      if (_isProblematic && effectiveClassification != 'Problemático') 'Problemático',
    ];

    final result = await CouponService.validateCoupon(
      shopId: widget.shopId,
      code: code,
      userId: user.id,
      serviceId: widget.serviceDoc['id'],
      clientClassification: effectiveClassification,
      clientManualTags: effectiveTags,
      isNewClient: _isNewClient,
      isVipClient: _isVip,
      selectedPaymentMethod:
          _selectedPaymentType == 'local' ? 'local' : _selectedMethod,
    );
    setState(() => _isLoading = false);

    if (result.isValid) {
      setState(() {
        _couponApplied = true;
        _couponDiscountPercent = result.discountPercent ?? 0.0;
        _appliedCouponId = result.couponId;
        _appliedCouponCode = code.toUpperCase();
        _appliedCoupon = result.couponData;
      });
      _recalculateTotals();
      
      // Dispara animação de sucesso
      _couponAnimationController.forward(from: 0.0);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Cupom '$_appliedCouponCode' aplicado com sucesso!"),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    } else {
      if (mounted) {
        showCouponInvalidModal(
          context: context,
          message: result.message,
          couponCode: code.isNotEmpty ? code : null,
          directErrorType: result.errorType,
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
      _appliedCoupon = null;
      _couponController.clear();
    });
    _recalculateTotals();
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text("Cupom removido.")));
  }

  Future<void> _showCouponInvalidModal(CouponErrorType errorType) async {
    if (!mounted) return;
    await showCouponInvalidModal(
      context: context,
      directErrorType: errorType,
      couponCode: _appliedCouponCode,
    );
  }

  Future<void> _revalidateCouponForPaymentMethod() async {
    if (_appliedCoupon == null) return;
    final validMethods =
        List<String>.from(_appliedCoupon!['valid_payment_methods'] ?? []);
    if (validMethods.isEmpty) return;
    final effectiveMethod =
        _selectedPaymentType == 'local' ? 'local' : _selectedMethod;
    if (effectiveMethod == 'local' || !validMethods.contains(effectiveMethod)) {
      _removeCoupon();
      _showCouponInvalidModal(CouponErrorType.onlinePaymentOnly);
    }
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
 
    // 3. Bloqueia sem CPF (se a loja exigir)
    final bool requireCpf = (widget.shopConfig['require_cpf'] == true);
    if (requireCpf && (_userCpf == null || _userCpf!.trim().isEmpty)) {
      _showMissingCpfDialog();
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
          double valorParaCobrar = valorFinalComJuros;

          setState(() => _isLoading = true);
          final user = Supabase.instance.client.auth.currentUser;
          if (user == null) {
            setState(() => _isLoading = false);
            return;
          }

          try {
            final savedCardsSnap = await Supabase.instance.client
                .from('saved_cards')
                .select()
                .eq('user_id', user.id)
                .eq('shop_id', widget.shopId);

            setState(() => _isLoading = false);

            if (!mounted) return;
            if (savedCardsSnap.isNotEmpty) {
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
                  _showConfirmationModal();
                }
              } else if (sheetResult is Map<String, dynamic>) {
                setState(() {
                  _storedCardData = sheetResult;
                  _currentStep = 2;
                });
                _showConfirmationModal();
              }
            } else {
              final result = await _pushCheckoutTransparente(valorParaCobrar);
              if (result != null && mounted) {
                setState(() {
                  _storedCardData = result;
                  _currentStep = 2;
                });
                _showConfirmationModal();
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
                              widget.serviceDoc['name']),
                      _summaryItem(Icons.person, "Profissional",
                          widget.professionalDoc['name'] ?? ''),
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
                            if (_storedCardData != null) {
                              final inst = (_storedCardData!['installments'] as num?)?.toInt() ?? 1;
                              final v = ((_storedCardData!['valor'] ?? valorFinalComJuros) as num).toDouble();
                              final perInst = v / inst;
                              detalhePagamento = "${inst}x de R\$ ${perInst.toStringAsFixed(2).replaceAll('.', ',')}";
                            } else {
                              detalhePagamento = "Processamento seguro via Mercado Pago";
                            }
                          }
                        }
                        return _summaryItem(Icons.payment, "Forma de Pagamento",
                            tituloPagamento,
                            subtitle: detalhePagamento);
                      }),
                      const Divider(height: 30),

                      // CAMPO DE CUPOM (SOMENTE SE O PLANO PERMITIR, FOR PIX, TOTAL OU LOCAL)
                      if ((_selectedMethod == 'pix' || _selectedPaymentType == 'local' || _selectedPaymentType == 'total') &&
                          PlanFeaturesService.getFeaturesForShop(widget.shopData).coupons) ...[
                        const Text("Tem um cupom?",
                            style: TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 13)),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: SizedBox(
                                height: 45,
                                child: ScaleTransition(
                                    scale: _couponScaleAnimation,
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
                                            ? Colors.green.withValues(alpha: 0.05)
                                            : Colors.white,
                                        filled: true,
                                        suffixIcon: _couponApplied 
                                          ? const Icon(Icons.check_circle, color: Colors.green, size: 20) 
                                          : null,
                                      ),
                                      textCapitalization:
                                          TextCapitalization.characters,
                                    ),
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
                      String textoBotao = _selectedPaymentType == 'local'
                          ? "FINALIZAR AGENDAMENTO"
                          : "FINALIZAR E PAGAR AGORA";

                      return Column(
                        children: [
                          if (_birthdayGiftAccepted &&
                              _isBirthdayMonth &&
                              _birthdayDiscountEnabled &&
                              _selectedPaymentType != 'local')
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8.0),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(Icons.cake,
                                      color: AppColors.primaryPurple, size: 16),
                                  const SizedBox(width: 8),
                                  Text(
                                    "Desconto de Aniversário Aplicado (-${_birthdayDiscountPercent.round()}%)",
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.primaryPurple,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          if (_couponApplied)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8.0),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(Icons.local_offer,
                                      color: Colors.green, size: 16),
                                  const SizedBox(width: 8),
                                  Text(
                                    "Cupom '$_appliedCouponCode' Aplicado (-${_couponDiscountPercent.round()}%)",
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.green,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          if (_selectedMethod == 'card' &&
                              _selectedPaymentType != 'local' &&
                              _cardTaxPercent > 0)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8.0),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.credit_card,
                                      color: Colors.orange[700], size: 16),
                                  const SizedBox(width: 8),
                                  Text(
                                    "Inclui ${_cardTaxPercent.toStringAsFixed(1)}% de taxa do cartão",
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.orange[700],
                                    ),
                                  ),
                                ],
                              ),
                            ),
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
                                  TweenAnimationBuilder<double>(
                                    duration: const Duration(milliseconds: 500),
                                    curve: Curves.easeOut,
                                    tween: Tween<double>(begin: _animatedPrice, end: valorFinalComJuros),
                                    onEnd: () => _animatedPrice = valorFinalComJuros,
                                    builder: (context, value, child) {
                                      return Text(_currencyFormat.format(value),
                                          style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 20,
                                              color: AppColors.primaryPurple));
                                    },
                                  ),
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

    // Segurança: bloqueia pagamento online com valor abaixo do mínimo do gateway
    if (_selectedPaymentType != 'local' && valorFinalComJuros < 1.0) {
      _showError('O valor mínimo para pagamento online é R\$ 1,00. '
          'Remova o cupom ou escolha pagar pessoalmente.');
      return;
    }

    if (_selectedPaymentType == 'local') {
      debugPrint('→ Pagamento LOCAL');
      _saveBooking(metodo: "No Local", status: "agendado", valorPago: 0);
    } else if (_selectedMethod == 'pix') {
      debugPrint('→ Pagamento PIX');
      double valor = valorFinalComJuros;
      String desc = (_selectedPaymentType == 'sinal') ? "Sinal" : "Total";
      
      // Pre-salva o agendamento com 'pendente_pix' antes de gerar o QR Code.
      // Garante que o horário fica reservado e o webhook confirma mesmo se o app fechar.
      final preSavedId = await _saveBooking(
        metodo: (_selectedPaymentType == 'sinal') ? "Pix (Sinal)" : "Pix",
        status: "pendente_pix",
        valorPago: 0,
        isPreSave: true,
      );
      if (preSavedId == null) return; // pre-save falhou (ex: horário indisponível)
      _preSavedAppointmentId = preSavedId;
      _generatePix(valor, desc, externalRef: preSavedId);
    } else {
      debugPrint('→ Pagamento CARTÃO → cobrando com dados já coletados');
      double valorParaCobrar = valorFinalComJuros;
      if (_storedCardData != null) {
        if (_storedCardData!['useSavedCard'] == true) {
          final fUser = Supabase.instance.client.auth.currentUser;
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
            cpf: _storedCardData!['cpf'] as String?,
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

  bool _isCvvError(String? msg, String? statusDetail) {
    final m = msg?.toLowerCase() ?? '';
    final s = statusDetail?.toLowerCase() ?? '';
    return s.contains('security_code') ||
        s == 'cc_rejected_bad_filled_security_code' ||
        m.contains('security_code') ||
        m.contains('cvv') ||
        m.contains('cvc');
  }

  void _showCvvRetryDialog({
    required String errorMsg,
    required bool isSavedCard,
    VoidCallback? onEditCard,
    Future<void> Function(String cvv)? onRetryCvv,
  }) {
    final cvvController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.credit_card_off_outlined, color: Colors.orange),
            SizedBox(width: 8),
            Expanded(child: Text('Código de segurança inválido', style: TextStyle(fontSize: 16))),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isSavedCard
                  ? 'O código de segurança (CVV/CVC) do cartão foi recusado. Alguns cartões têm código dinâmico que muda periodicamente. Digite o código atual:'
                  : 'O código de segurança (CVV/CVC) foi recusado. Volte e verifique os dados do cartão.',
              style: TextStyle(fontSize: 13, color: Colors.grey[700]),
            ),
            if (isSavedCard) ...[  
              const SizedBox(height: 16),
              TextField(
                controller: cvvController,
                keyboardType: TextInputType.number,
                maxLength: 4,
                obscureText: true,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Novo CVV / CVC',
                  counterText: '',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.lock_outline),
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          if (isSavedCard)
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryPurple,
                  foregroundColor: Colors.white),
              onPressed: () async {
                if (cvvController.text.length < 3) return;
                Navigator.pop(ctx);
                await onRetryCvv?.call(cvvController.text);
              },
              child: const Text('Tentar com este CVV'),
            )
          else
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryPurple,
                  foregroundColor: Colors.white),
              onPressed: () {
                Navigator.pop(ctx);
                onEditCard?.call();
              },
              child: const Text('Editar cartão'),
            ),
        ],
      ),
    );
  }

  Future<void> _processarPagamentoComCartaoArmazenado({
    required double valor,
    required String cardToken,
    required int installments,
    required String email,
    String? paymentMethodId,
    dynamic issuerId,
    String? cpf,
  }) async {
    setState(() => _isLoading = true);
    try {
      try { await Supabase.instance.client.auth.refreshSession(); } catch (_) {}
      final result = await MercadoPagoService.criarPagamentoCartao(
        shopId: widget.shopId,
        cardToken: cardToken,
        amount: valor,
        installments: installments,
        email: email,
        description: "Reserva: ${widget.serviceDoc['name'] ?? 'Serviço'}",
        cpf: cpf,
        paymentMethodId: paymentMethodId,
        issuerId: issuerId,
      );

      if (result['success'] == true && result['paymentId'] != null) {
        // Salvar cartão no vault do MP se o cliente solicitou
        if (_storedCardData?['saveCard'] == true) {
          try {
            final user = Supabase.instance.client.auth.currentUser;
            await MercadoPagoService.salvarCartao(
              shopId: widget.shopId,
              cardToken: cardToken,
              userEmail: user?.email ?? email,
              paymentMethodId: paymentMethodId,
              lastFour: _storedCardData?['lastFour']?.toString(),
            );
            debugPrint('✅ Cartão salvo no vault com sucesso.');
          } catch (e) {
            debugPrint('⚠️ Cartão não foi salvo (não crítico): $e');
          }
        }
        await _saveBooking(
          metodo: "Cartão de Crédito",
          status: "confirmado",
          valorPago: valor,
          paymentId: result['paymentId'].toString(),
        );
      } else {
        final errMsg = result['error']?.toString() ?? 'Pagamento recusado';
        final statusDetail = result['status_detail']?.toString();
        if (_isCvvError(errMsg, statusDetail)) {
          _showCvvRetryDialog(
            errorMsg: errMsg,
            isSavedCard: false,
            onEditCard: () => setState(() { _storedCardData = null; _currentStep = 1; }),
          );
        } else {
          _showError(errMsg);
        }
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
      if (_shopPublicKey == null) {
        _showError('Esta loja não configurou os meios de pagamento online ainda.');
        return;
      }

      // Gera novo token usando cardId + CVV (sem precisar do número completo)
      final newToken = await MercadoPagoService.getTokenFromSavedCard(
        publicKey: _shopPublicKey!,
        cardId: cardId,
        securityCode: securityCode,
      );

      final result = await MercadoPagoService.criarPagamentoCartao(
        shopId: widget.shopId,
        cardToken: newToken,
        amount: valor,
        installments: installments,
        email: email,
        description: "Reserva: ${widget.serviceDoc['name'] ?? 'Serviço'}",
        paymentMethodId: paymentMethodId,
      );

      if (result['success'] == true && result['paymentId'] != null) {
        await _saveBooking(
          metodo: "Cartão Salvo",
          status: "confirmado",
          valorPago: valor,
          paymentId: result['paymentId'].toString(),
        );
      } else {
        final errMsg = result['error']?.toString() ?? 'Pagamento recusado.';
        final statusDetail = result['status_detail']?.toString();
        if (_isCvvError(errMsg, statusDetail)) {
          _showCvvRetryDialog(
            errorMsg: errMsg,
            isSavedCard: true,
            onRetryCvv: (newCvv) => _processarPagamentoCartaoSalvo(
              valor: valor,
              cardId: cardId,
              customerId: customerId,
              securityCode: newCvv,
              installments: installments,
              email: email,
              paymentMethodId: paymentMethodId,
            ),
          );
        } else {
          _showError(errMsg);
        }
      }
    } catch (e) {
      final errStr = e.toString();
      if (_isCvvError(errStr, null)) {
        _showCvvRetryDialog(
          errorMsg: errStr,
          isSavedCard: true,
          onRetryCvv: (newCvv) => _processarPagamentoCartaoSalvo(
            valor: valor,
            cardId: cardId,
            customerId: customerId,
            securityCode: newCvv,
            installments: installments,
            email: email,
            paymentMethodId: paymentMethodId,
          ),
        );
      } else {
        _showError('Erro ao processar cartão salvo: $e');
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showBirthdayModal() {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: '',
      transitionDuration: const Duration(milliseconds: 400),
      pageBuilder: (context, anim1, anim2) {
        return BirthdayCelebrationModal(
          discountPercent: _birthdayDiscountPercent,
          shopName: widget.shopData['name'] ?? 'O Studio',
          onAccept: () {
            Navigator.pop(context);
            setState(() {
              _birthdayGiftAccepted = true;
              _recalculateTotals();
            });
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text("Presente ativado! O desconto foi aplicado ao seu valor total."),
                backgroundColor: Colors.green,
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    double valorExibido = valorFinalComJuros;

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
                  const AlwaysStoppedAnimation<Color>(AppColors.primaryPurple),
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

    double discountFactor = 1.0;
    if (_isBirthdayMonth && _birthdayDiscountEnabled && _birthdayGiftAccepted) {
      discountFactor -= (_birthdayDiscountPercent / 100.0);
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
            amount: valorSinal * discountFactor,
            badge: "SINAL",
            badgeColor: Colors.orange,
          ),
        const SizedBox(height: 12),
        if (aceitaPix || aceitaCartao)
          _buildPaymentTypeCard(
            value: 'total',
            title: "✅ Pagar Valor Total",
            subtitle: "Valor completo agora",
            amount: valorTotal * discountFactor,
            badge: "COMPLETO",
            badgeColor: Colors.green,
          ),
        const SizedBox(height: 12),
        if (aceitaDinheiro)
          _buildPaymentTypeCard(
            value: 'local',
            title: "🏪 Pagar Pessoalmente",
            subtitle: "Dinheiro ou cartão na hora",
            amount: valorTotal * discountFactor,
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
        color: AppColors.primaryPurple,
        borderRadius: BorderRadius.circular(15),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryPurple.withValues(alpha: 0.2),
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
                  "Você ganhou ${_birthdayDiscountPercent.round()}% de desconto especial de aniversário.",
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
    bool disabled = false,
  }) {
    bool isSelected = value == _selectedPaymentType;
    return GestureDetector(
      onTap: disabled
          ? null
          : () async {
              if (value == 'local' && _selectedPaymentType != 'local') {
                final confirmed = await showDialog<bool>(
                  context: context,
                  barrierDismissible: false,
                  builder: (context) => IntentionalFrictionModal(
                    title: "Pagar no Local",
                    content: const Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                              text:
                                  "Ao escolher pagar no local, você se compromete a "),
                          TextSpan(
                              text: "comparecer no horário",
                              style: TextStyle(fontWeight: FontWeight.bold)),
                          TextSpan(
                              text:
                                  " para não prejudicar a agenda do profissional.\n\n"),
                          TextSpan(
                              text: "O não comparecimento sem aviso prévio",
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.errorRed)),
                          TextSpan(
                              text: " poderá limitar seus agendamentos futuros."),
                        ],
                      ),
                      textAlign: TextAlign.center,
                    ),
                    expectedPhrase: "CONCORDO",
                    onConfirm: () => Navigator.pop(context, true),
                    onCancel: () => Navigator.pop(context, false),
                  ),
                );

                if (confirmed != true) return;
              }

              setState(() {
                _selectedPaymentType = value;
                _recalculateTotals();
              });
              if (_appliedCoupon != null) {
                _revalidateCouponForPaymentMethod();
              }
            },
      child: Opacity(
        opacity: disabled ? 0.6 : 1.0,
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
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
                    color: isSelected
                        ? AppColors.primaryPurple
                        : Colors.grey[400]!,
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
                    Text(
                        disabled
                            ? "Opção exclusiva para clientes VIP"
                            : subtitle,
                        style: TextStyle(
                            fontSize: 12,
                            color: disabled ? Colors.orange[800] : Colors.grey)),
                  ],
                ),
              ),
              if (value == 'local' && _trustedOnlyPayLocal && !_isVip)
                const Padding(
                  padding: EdgeInsets.only(right: 8),
                  child: Icon(Icons.stars, color: Colors.orange, size: 16),
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
                  TweenAnimationBuilder<double>(
                    duration: const Duration(milliseconds: 500),
                    curve: Curves.easeOut,
                    tween: Tween<double>(begin: _animatedPrice, end: amount),
                    builder: (context, value, child) {
                      return Text(
                        _currencyFormat.format(value),
                        style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: AppColors.primaryPurple),
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
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
                    "Você pagará ${_currencyFormat.format(valorFinalComJuros)} no local do atendimento.",
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
                  description: _cardTaxPercent > 0
                      ? '+${_cardTaxPercent.toStringAsFixed(1)}% taxa'
                      : 'Com parcelas',
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
        if (_appliedCoupon != null) {
          _revalidateCouponForPaymentMethod();
        }
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
    // Determine the base price without birthday discount for the strike-through
    double baseSemAniversario =
        (_selectedPaymentType == 'sinal') ? valorSinal : valorTotal;

    // We only show the "magic" if the gift was accepted and we are NOT in local payment
    // We only show the "magic" if the gift was accepted
    bool isActuallyDiscounted = (_birthdayGiftAccepted || _couponApplied) && v < baseSemAniversario;

    double precoAntigo = baseSemAniversario;
    bool mostrarRiscado = isActuallyDiscounted;

    // Se for cartão, o preço base sobe. Queremos mostrar:
    // R$ 100,00 (riscado) -> R$ 105,00 (se for apenas taxa)
    // R$ 100,00 (riscado) -> R$ 90,00 (se houver desconto maior que a taxa)
    if (_selectedMethod == 'card' && (_selectedPaymentType == 'total' || _selectedPaymentType == 'sinal')) {
      mostrarRiscado = true; // Sempre mostra o antigo no cartão para evidenciar a variação
      if (!isActuallyDiscounted) {
        precoAntigo = baseSemAniversario;
      } else {
        // Se houver desconto + taxa, o antigo é o base original sem nada
        precoAntigo = baseSemAniversario;
      }
    }

    return Container(
      padding: const EdgeInsets.all(20),
      // ... resto do estilo ...
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            spreadRadius: 0,
          )
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text("Total a Pagar",
              style: TextStyle(fontSize: 14, color: Colors.grey)),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (mostrarRiscado)
                Text(
                  _currencyFormat.format(precoAntigo),
                  style: const TextStyle(
                    fontSize: 14,
                    color: Colors.grey,
                    decoration: TextDecoration.lineThrough,
                  ),
                ),
              TweenAnimationBuilder<double>(
                key: ValueKey("price_${_selectedPaymentType}_${_selectedMethod}_$v"),
                tween: Tween(begin: isActuallyDiscounted ? baseSemAniversario : v, end: v),
                duration: const Duration(milliseconds: 1200),
                curve: Curves.elasticOut,
                builder: (context, value, child) {
                  return Text(
                    _currencyFormat.format(value),
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      color: isActuallyDiscounted
                          ? Colors.green.shade700
                          : AppColors.primaryPurple,
                    ),
                  );
                },
              ),
            ],
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

  Future<void> _generatePix(double amount, String desc, {String? externalRef}) async {
    if (shopAccessToken == null) {
      _showError(
          'Esta loja não configurou os meios de pagamento online ainda.');
      return;
    }
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
      try {
        await Supabase.instance.client.auth.refreshSession();
      } catch (_) {}
      final user = Supabase.instance.client.auth.currentUser!;
      final result = await MercadoPagoService.gerarPix(
        shopId: widget.shopId,
        amount: amount,
        emailCliente: user.email ?? "cliente@app.com",
        description: desc,
        externalReference: externalRef,
      );
      
      final qrCode64 = result['point_of_interaction']?['transaction_data']?['qr_code_base64'];
      final copyPaste = result['point_of_interaction']?['transaction_data']?['qr_code'];
      final paymentId = result['id']?.toString() ?? '';

      if (qrCode64 == null || copyPaste == null || paymentId.isEmpty) {
        throw Exception("Dados do PIX incompletos na resposta do servidor.");
      }

      if (_preSavedAppointmentId != null) {
        try {
          await Supabase.instance.client
              .from('appointments')
              .update({'payment_id': paymentId}).eq('id', _preSavedAppointmentId!);
        } catch (e) {
          debugPrint('Falha ao salvar paymentId no agendamento preventivo: $e');
        }
      }

      if (mounted) {
        _startPixMonitoring(paymentId, amount);
        // close loading page safely
        if (Navigator.canPop(context)) Navigator.pop(context);
        _showPixModal(qrCode64, copyPaste, paymentId, amount);
      }
    } catch (e) {
      if (mounted && Navigator.canPop(context)) Navigator.pop(context);
      _showError("Erro ao gerar PIX: $e");
    } finally {
      if (mounted) {
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
          if (mounted && !_isConfirmingPayment) {
            _isConfirmingPayment = true;
            // Fecha a PixPaymentPage (modal de QR Code) se ainda estiver aberta
            if (Navigator.canPop(context)) Navigator.pop(context);
            await _saveBooking(
                metodo: "Pix",
                status: "confirmado",
                valorPago: valorPago,
                paymentId: paymentId,
                appointmentId: _preSavedAppointmentId);
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
          onPaid: () async {
            if (_isConfirmingPayment) return;
            _isConfirmingPayment = true;
            // Cancelar o polling automático se o manual confirmou
            _timerPolling?.cancel();
            // Fecha a PixPaymentPage e salva o agendamento
            Navigator.pop(c);
            await _saveBooking(
                metodo: "Pix",
                status: "confirmado",
                valorPago: valorPago,
                paymentId: paymentId,
                appointmentId: _preSavedAppointmentId);
          },
        ),
      ),
    );
  }

  Future<String?> _saveBooking({
    required String metodo,
    required String status,
    required double valorPago,
    String? paymentId,
    String? appointmentId,
    bool isPreSave = false,
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
      final user = Supabase.instance.client.auth.currentUser!;
      final bookingDate = DateTime(
        widget.date.year,
        widget.date.month,
        widget.date.day,
        widget.time.hour,
        widget.time.minute,
      );

      final int duration =
          int.tryParse(widget.serviceDoc['duration_min']?.toString() ?? '30') ??
              30;

      // Validação de Double-Booking via Cloud Function no Backend.
      // Pulada ao confirmar um pre-save (slot já foi validado na etapa de geração do PIX).
      if (widget.rescheduleId != null || appointmentId == null) {
        try {
          final result = await Supabase.instance.client.functions.invoke('checkAvailability', body: {
            'professional_id': widget.professionalDoc['id'],
            'shop_id': widget.shopId,
            'start_time': bookingDate.toIso8601String(),
            'duration': duration,
          });

          if (result.data['available'] != true) {
            if (mounted) {
              // Fecha o loading de "Finalizando agendamento..." se ele estiver aberto
              if (Navigator.canPop(context)) Navigator.pop(context);
              
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
            return null;
          }
        } catch (e) {
          debugPrint('Erro na validação de disponibilidade (backend): $e');
          // Em caso de erro na função, procedemos com a validação local já existente abaixo
        }
      }

      // Validação: permitir agendamentos múltiplos (configuração da loja)
      final permitirMultiplos =
          (widget.shopConfig['permitir_multiplos'] ?? true) as bool;
      if (!permitirMultiplos) {
        final now = DateTime.now();
        // Para evitar necessidade de índice, buscamos agendamentos do cliente e filtramos localmente.
        final clientAppts = await Supabase.instance.client
            .from('appointments')
            .select()
            .eq('client_id', user.id);
        final currentApptId = _preSavedAppointmentId ?? appointmentId;
        final conflicting = clientAppts.where((data) {
          // Pular o próprio agendamento que está sendo confirmado (update)
          if (currentApptId != null && data['id']?.toString() == currentApptId) {
            return false;
          }
          final sId = data['shop_id']?.toString() ?? '';
          final status = (data['status'] ?? '').toString();
          final ts = data['scheduled_at'];
          DateTime? dt;
          try {
            if (ts is String) {
              dt = DateTime.parse(ts);
            } else if (ts is DateTime) {
              dt = ts;
            }
          } catch (_) {
            dt = null;
          }
          if (sId != widget.shopId) {
            return false;
          }
          if (!['agendado', 'confirmado', 'pendente', 'pendente_verificacao', 'pendente_pix']
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
          return null;
        }
      }

      final profData = widget.professionalDoc as Map<String, dynamic>;
      final DateTime endDate = bookingDate.add(Duration(minutes: duration));

      // Calcula desconto total considerando se cada desconto está realmente ativo
      double activeDiscountPercent = 0.0;
      if (_isBirthdayMonth && _birthdayDiscountEnabled && _birthdayGiftAccepted) {
        activeDiscountPercent += _birthdayDiscountPercent;
      }
      if (_couponApplied) {
        activeDiscountPercent += _couponDiscountPercent;
      }
      // Para pagamentos online, limita a 99% (gateway rejeita R$0)
      final bool isOnline = _selectedPaymentType != 'local';
      final double maxDiscount = isOnline ? 99.0 : 100.0;
      if (activeDiscountPercent > maxDiscount) activeDiscountPercent = maxDiscount;

      final double totalDiscounted = valorTotal * (1 - (activeDiscountPercent / 100.0));
      double totalWithTax = totalDiscounted;
      
      // Se for pagamento via cartão (online), a taxa configurada pela loja é aplicada sobre o valor pago
      if (_selectedMethod == 'card' && _selectedPaymentType != 'local') {
        final double basePaid = (_selectedPaymentType == 'sinal') 
            ? (valorSinal * (1 - (activeDiscountPercent / 100.0))) 
            : totalDiscounted;
        final double currentTax = basePaid * (_cardTaxPercent / 100.0);
        totalWithTax += currentTax;
      }

      final Map<String, dynamic> bookingData = {
        'shop_id': widget.shopId,
        'client_id': user.id,
        'client_name': _userName ?? user.userMetadata?['full_name'] ?? user.userMetadata?['name'] ?? user.userMetadata?['nome'] ?? 'Cliente',
        'client_email': _userEmail ?? user.email,
        'client_phone': _userPhone,
        'client_photo': _userPhotoUrl,
        'service_name': widget.serviceNameOverride ?? widget.serviceDoc['name'],
        'professional_id': widget.professionalDoc['id'],
        'professional_name': profData['name'] ?? 'Profissional',
        'service_id': widget.serviceDoc['id'],
        'total_price': valorTotal,
        'total_value': valorTotal,
        'valor_com_desconto': totalDiscounted, // Valor após CUPOM/NIVER (usado para mostrar o risquinho)
        'total_payable': totalWithTax, // Valor final que o cliente deve pagar (incluindo taxas)
        'paid_amount': valorPago,
        'remaining_amount': (totalWithTax - valorPago).toDouble(),
        'duration_min': duration,
        'scheduled_at': bookingDate.toIso8601String(),
        'end_at': endDate.toIso8601String(),
        'status': status,
        'payment_method': metodo,
        'payment_status': valorPago > 0.01 ? 'pago' : 'pendente',
        'payment_id': paymentId,
        'discount_amount': valorTotal - totalDiscounted,
        'birthday_discount_applied': _birthdayGiftAccepted,
        'birthday_discount_percent': _birthdayGiftAccepted ? _birthdayDiscountPercent : 0,
        'coupon_applied': _couponApplied,
        'coupon_code': _appliedCouponCode,
        'coupon_discount_percent': _couponApplied ? _couponDiscountPercent : 0,
        'card_tax_percent': (_selectedMethod == 'card' && _selectedPaymentType != 'local') ? _cardTaxPercent : 0,
        'valor_sinal':
            (metodo.contains('Sinal') || _selectedPaymentType == 'sinal')
                ? valorPago
                : 0,
      };

      String finalAppointmentId;

      // REGRA DE OURO: Priorizar o rescheduleId vindo do construtor para evitar duplicação (INSERT)
      final String? effectiveRescheduleId = widget.rescheduleId ?? appointmentId;

      if (effectiveRescheduleId != null && effectiveRescheduleId.isNotEmpty) {
        // Se já existe um ID (reagendamento ou presave prévio), atualiza o doc existente
        bookingData['updated_at'] = DateTime.now().toIso8601String();
        await Supabase.instance.client
            .from('appointments')
            .update(bookingData)
            .eq('id', effectiveRescheduleId);
        finalAppointmentId = effectiveRescheduleId;
      } else {
        // Se for novo, adiciona
        bookingData['created_at'] = DateTime.now().toIso8601String();
        final response = await Supabase.instance.client
            .from('appointments')
            .insert(bookingData)
            .select('id')
            .single();
        finalAppointmentId = response['id'];
      }

      if (isPreSave) {
        // Se for pre-save, apenas retorna o ID para o fluxo de pagamento continuar
        try {
          Navigator.pop(context);
        } catch (_) {}
        return finalAppointmentId;
      }

      // Se usou cupom, marca como usado para o cliente
      if (_couponApplied && _appliedCouponId != null) {
        await CouponService.markCouponAsUsed(
          shopId: widget.shopId,
          couponId: _appliedCouponId!,
          userId: user.id,
          appointmentId: finalAppointmentId,
        );
      }

      // O registro do uso do presente de aniversário agora é feito automaticamente por um gatilho (trigger) no Supabase.

      if (mounted) {
        final svcName = widget.serviceNameOverride ??
            widget.serviceDoc['name'] ??
            'Serviço';
        final profName = widget.professionalDoc['name'] ?? 'Profissional';
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
          final shopD = widget.shopData;
          final sName = shopD['name']?.toString() ?? '';
          final addrParts = [
            shopD['address'],
            shopD['address_number'] != null ? 'nº ${shopD['address_number']}' : null,
            shopD['city'],
          ].where((e) => e != null && e.toString().isNotEmpty).join(', ');
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(
              builder: (c) => BookingSuccessPage(
                serviceName: svcName,
                professionalName: profName,
                date: dateStr,
                time: timeStr,
                isPaid: paidFlag,
                shopName: sName,
                shopAddress: addrParts,
                durationMin: duration,
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
      if (mounted) setState(() => _isLoading = false);
    }
    return null;
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
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: EdgeInsets.fromLTRB(
            24, 0, 24, MediaQuery.of(ctx).padding.bottom + 24),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.event_busy_rounded,
                  size: 38, color: Colors.orange.shade700),
            ),
            const SizedBox(height: 16),
            Text(
              'Agendamento já em aberto',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.grey[900],
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: Column(
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.info_outline,
                          size: 18, color: Colors.orange.shade700),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Esta loja não permite múltiplos agendamentos simultâneos.',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: Colors.orange.shade800,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Você já possui um agendamento ativo ou pendente nesta loja. '
                    'Para agendar novamente, aguarde a conclusão do seu atendimento '
                    'atual, ou cancele-o se não for mais comparecer.',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey[700],
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 0),
              child: Row(
                children: [
                  const Icon(Icons.lightbulb_outline,
                      size: 14, color: Colors.grey),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Dica: acesse "Meus Agendamentos" para ver ou cancelar agendamentos ativos.',
                      style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.calendar_today_outlined, size: 18),
                label: const Text('Ver Meus Agendamentos',
                    style: TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 15)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryPurple,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
                onPressed: () {
                  Navigator.pop(ctx);
                  try {
                    Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const MyAppointmentsPage()));
                  } catch (_) {}
                },
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              height: 44,
              child: TextButton(
                style: TextButton.styleFrom(
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  foregroundColor: Colors.grey[700],
                ),
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Fechar',
                    style: TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w500)),
              ),
            ),
          ],
        ),
      ),
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

  void _showMissingCpfDialog() {
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.badge, color: Colors.orange),
            SizedBox(width: 10),
            Text("CPF Obrigatório"),
          ],
        ),
        content: const Text(
            "Esta loja exige que o CPF esteja preenchido no seu perfil para realizar agendamentos.\n\nPor favor, atualize seus dados antes de continuar."),
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
  void dispose() {
    _cvvController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;
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
          FutureBuilder<List<Map<String, dynamic>>>(
            future: Supabase.instance.client
                .from('saved_cards')
                .select()
                .eq('user_id', user.id)
                .eq('shop_id', widget.shopId),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(
                    child: Padding(
                        padding: EdgeInsets.all(20),
                        child: CircularProgressIndicator()));
              }
              final docs = snapshot.data ?? [];
              if (docs.isEmpty) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  widget.onAddNewCard();
                });
                return const SizedBox.shrink();
              }
              return Column(
                children: [
                  ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: docs.length,
                    itemBuilder: (context, index) {
                      final data = docs[index];
                      final brand = data['brand'] ?? data['paymentMethodName'] ?? 'Cartão';
                      final last4 = data['last_4'] ?? data['lastFourDigits'] ?? '****';
                      final cardId = (data['id'] ?? '').toString();
                      final isSelected = _selectedCardId == cardId;

                      return GestureDetector(
                        onTap: () => setState(() => _selectedCardId = cardId),
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? AppColors.primaryPurple.withValues(alpha: 0.05)
                                : Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isSelected
                                  ? AppColors.primaryPurple
                                  : Colors.grey.shade300,
                              width: isSelected ? 2 : 1,
                            ),
                          ),
                          child: Column(
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    _getCardIcon(brand),
                                    color: isSelected
                                        ? AppColors.primaryPurple
                                        : Colors.grey.shade600,
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          brand.toUpperCase(),
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            color: isSelected
                                                ? AppColors.primaryPurple
                                                : Colors.black87,
                                          ),
                                        ),
                                        Text(
                                          "Final **** $last4",
                                          style: TextStyle(
                                            color: Colors.grey.shade600,
                                            fontSize: 13,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
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
                  ),
                ],
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

  IconData _getCardIcon(String brand) {
    brand = brand.toLowerCase();
    if (brand.contains('visa')) return Icons.credit_card;
    if (brand.contains('master')) return Icons.credit_card;
    if (brand.contains('amex')) return Icons.credit_card;
    return Icons.credit_card;
  }
}
