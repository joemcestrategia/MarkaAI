import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;

import '../../core/theme/app_colors.dart';
import '../schedule/booking_success_page.dart';
import '../../widgets/universal_webview/universal_webview.dart';
import '../business/subscription_service.dart';

class CheckoutTransparentePage extends StatefulWidget {
  final String shopId;
  final double valor;
  final String orderId;
  final DocumentSnapshot serviceDoc;
  final DocumentSnapshot professionalDoc;
  final DateTime date;
  final TimeOfDay time;

  /// Se true, só coleta dados do cartão e volta para revisão; a cobrança é feita depois ao concluir.
  final bool collectOnly;

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
  });

  @override
  State<CheckoutTransparentePage> createState() =>
      _CheckoutTransparentePageState();
}

class _CheckoutTransparentePageState extends State<CheckoutTransparentePage> {
  WebViewController? _controller;
  bool _isLoading = true;
  bool _didInject = false;
  Widget? _webViewWidget;

  bool _planRestricted = false;

  @override
  void initState() {
    super.initState();
    _checkPlanRestriction();
  }

  Future<void> _checkPlanRestriction() async {
    // Usa getShopPlan(shopId) — não canUseOnlinePayment() — pois o usuário
    // logado aqui é o CLIENTE, não o dono da loja.
    final shopPlan = await SubscriptionService.getShopPlan(widget.shopId);
    final canPay = SubscriptionService.planSupportsOnlinePayment(shopPlan);
    if (!canPay) {
      if (mounted) setState(() => _planRestricted = true);
      return;
    }

    if (kIsWeb) {
      _prepareWebInitialData();
    } else {
      _loadShopPaymentConfigLocal().whenComplete(() {
        Future.delayed(const Duration(milliseconds: 2500), () async {
          if (!mounted || !_isLoading || _didInject) return;
          await _injectAllAndHideLoading();
        });
      });
    }
  }

  Future<void> _loadShopPaymentConfigLocal() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('shops')
          .doc(widget.shopId)
          .get();
      final data = doc.data() ?? {};
      final paymentOpts = (data['payment_options'] is Map)
          ? Map<String, dynamic>.from(data['payment_options'])
          : <String, dynamic>{};
      final config = (data['config'] is Map)
          ? Map<String, dynamic>.from(data['config'])
          : <String, dynamic>{};
      dynamic readRoot(String key) => data.containsKey(key) ? data[key] : null;
      double parseDouble(dynamic v, [double fallback = 0.0]) {
        if (v is num) return v.toDouble();
        if (v is String) {
          return double.tryParse(v.replaceAll(',', '.')) ?? fallback;
        }
        return fallback;
      }

      int parseInt(dynamic v, [int fallback = 1]) {
        if (v is int) return v;
        if (v is num) return v.toInt();
        if (v is String) return int.tryParse(v) ?? fallback;
        return fallback;
      }

      final creditoFromPaymentOpts = (paymentOpts['credito_config'] is Map)
          ? Map<String, dynamic>.from(paymentOpts['credito_config'])
          : <String, dynamic>{};
      final creditoFromConfig = (config['credito_config'] is Map)
          ? Map<String, dynamic>.from(config['credito_config'])
          : <String, dynamic>{};

      final mergedCredito = <String, dynamic>{};
      mergedCredito['repasse_ao_cliente'] =
          creditoFromPaymentOpts['repasse_ao_cliente'] ??
              creditoFromConfig['repasse_ao_cliente'] ??
              readRoot('repasse_ao_cliente') ??
              false;
      mergedCredito['aceitar_parcelas'] =
          creditoFromPaymentOpts['aceitar_parcelas'] ??
              creditoFromConfig['aceitar_parcelas'] ??
              config['aceitar_parcelas'] ??
              readRoot('aceitar_parcelas') ??
              false;
      mergedCredito['porcentagem_a_vista'] = parseDouble(
          creditoFromPaymentOpts['porcentagem_a_vista'] ??
              creditoFromConfig['porcentagem_a_vista'] ??
              config['porcentagem_a_vista'] ??
              readRoot('porcentagem_a_vista') ??
              0.0,
          0.0);
      mergedCredito['max_parcelas'] = parseInt(
          creditoFromPaymentOpts['max_parcelas'] ??
              creditoFromConfig['max_parcelas'] ??
              config['max_parcelas'] ??
              readRoot('max_parcelas') ??
              1,
          1);

      // sanitize
      mergedCredito['max_parcelas'] =
          (mergedCredito['max_parcelas'] as int).clamp(1, 12);
      mergedCredito['porcentagem_a_vista'] =
          (mergedCredito['porcentagem_a_vista'] as double).clamp(0.0, 20.0);

      _shopPaymentConfig = {
        'pix': paymentOpts['pix'] ??
            config['pagamento_pix'] ??
            readRoot('pagamento_pix') ??
            false, // default off: loja nova precisa habilitar explicitamente
        'credito': paymentOpts['credito'] ??
            config['pagamento_cartao'] ??
            readRoot('pagamento_cartao') ??
            false, // default off
        'presencial': paymentOpts['presencial'] ??
            config['pagamento_dinheiro'] ??
            readRoot('pagamento_dinheiro') ??
            true, // presencial sempre habilitado por padrão
        'credito_config': mergedCredito,
      };
      // Calcula parcelas para injeção no WebView (fallback local; MP API retorna os valores reais)
      try {
        final double amount = double.tryParse(widget.valor.toString()) ?? 0.0;
        final int maxP = (mergedCredito['max_parcelas'] is int)
            ? mergedCredito['max_parcelas'] as int
            : 1;
        final bool aceitaP = mergedCredito['aceitar_parcelas'] ?? false;
        final bool repassa =
            ((mergedCredito['porcentagem_a_vista'] as num?) ?? 0) > 0;
        final double pctVista = (mergedCredito['porcentagem_a_vista'] is double)
            ? mergedCredito['porcentagem_a_vista'] as double
            : (double.tryParse(
                    mergedCredito['porcentagem_a_vista']?.toString() ?? '') ??
                0.0);
        final int maxToUse = aceitaP ? maxP.clamp(1, 12) : 1;
        final List<Map<String, dynamic>> comps = [];
        for (int p = 1; p <= maxToUse; p++) {
          final double pct = (p == 1) ? pctVista : 0.0;
          final double total =
              repassa ? (amount + (amount * (pct / 100.0))) : amount;
          final double per = (total / p);
          comps.add({
            'installments': p,
            'total': double.parse(total.toStringAsFixed(2)),
            'per_installment': double.parse(per.toStringAsFixed(2)),
            'percent': pct
          });
        }
        _shopPaymentConfig['computed_installments'] = comps;
      } catch (_) {}
    } catch (e) {
      _shopPaymentConfig = {};
    }
  }

  Map<String, String>? _webClientData;
  bool _webReady = false;
  // payment config from shop (to drive installments UI)
  Map<String, dynamic> _shopPaymentConfig = {};
  // Endpoint do backend / Cloud Function já implantada
  // Atualizado para a função existente no projeto (us-central1)
  final String _installmentsEndpoint =
      'https://us-central1-wismart-118c3.cloudfunctions.net/getInstallments';

  Future<void> _prepareWebInitialData() async {
    try {
      final key = await _getPublicKey();
      String email = '';
      String nome = '';
      String cpf = '';
      // load shop payment options with fallbacks (payment_options -> config -> root)
      try {
        final doc = await FirebaseFirestore.instance
            .collection('shops')
            .doc(widget.shopId)
            .get();
        final data = doc.data() ?? {};
        final paymentOpts = (data['payment_options'] is Map)
            ? Map<String, dynamic>.from(data['payment_options'])
            : <String, dynamic>{};
        final config = (data['config'] is Map)
            ? Map<String, dynamic>.from(data['config'])
            : <String, dynamic>{};
        // helper to read legacy root-level fields
        dynamic readRoot(String key) =>
            data.containsKey(key) ? data[key] : null;

        // credito config may be present in several places; prefer payment_options.credito_config -> config -> root fields
        final creditoFromPaymentOpts = (paymentOpts['credito_config'] is Map)
            ? Map<String, dynamic>.from(paymentOpts['credito_config'])
            : <String, dynamic>{};
        final creditoFromConfig = (config['credito_config'] is Map)
            ? Map<String, dynamic>.from(config['credito_config'])
            : <String, dynamic>{};

        double parseDouble(dynamic v, [double fallback = 0.0]) {
          if (v is num) return v.toDouble();
          if (v is String) {
            return double.tryParse(v.replaceAll(',', '.')) ?? fallback;
          }
          return fallback;
        }

        int parseInt(dynamic v, [int fallback = 1]) {
          if (v is int) return v;
          if (v is num) return v.toInt();
          if (v is String) return int.tryParse(v) ?? fallback;
          return fallback;
        }

        final mergedCredito = <String, dynamic>{};
        mergedCredito['repasse_ao_cliente'] =
            creditoFromPaymentOpts['repasse_ao_cliente'] ??
                creditoFromConfig['repasse_ao_cliente'] ??
                readRoot('repasse_ao_cliente') ??
                readRoot('config_repasse_taxa') ??
                false;
        mergedCredito['aceitar_parcelas'] =
            creditoFromPaymentOpts['aceitar_parcelas'] ??
                creditoFromConfig['aceitar_parcelas'] ??
                config['aceitar_parcelas'] ??
                readRoot('aceitar_parcelas') ??
                false;
        // prefer unified tax_percent if present
        mergedCredito['porcentagem_a_vista'] = parseDouble(
            creditoFromPaymentOpts['tax_percent'] ??
                creditoFromConfig['tax_percent'] ??
                config['tax_percent'] ??
                creditoFromPaymentOpts['porcentagem_a_vista'] ??
                creditoFromConfig['porcentagem_a_vista'] ??
                config['porcentagem_a_vista'] ??
                readRoot('porcentagem_a_vista') ??
                readRoot('tax_percent') ??
                0.0,
            0.0);
        mergedCredito['max_parcelas'] = parseInt(
            creditoFromPaymentOpts['max_parcelas'] ??
                creditoFromConfig['max_parcelas'] ??
                config['max_parcelas'] ??
                readRoot('max_parcelas') ??
                readRoot('max_parcelas'),
            1);

        // sanitize limits
        if (mergedCredito['max_parcelas'] is int) {
          mergedCredito['max_parcelas'] =
              (mergedCredito['max_parcelas'] as int).clamp(1, 12);
        } else {
          mergedCredito['max_parcelas'] = 1;
        }
        mergedCredito['porcentagem_a_vista'] =
            (mergedCredito['porcentagem_a_vista'] as double).clamp(0.0, 20.0);
        // parcelado percentage removed; Mercado Pago API will provide parcel fees when BIN is available

        _shopPaymentConfig = {
          'pix': paymentOpts['pix'] ??
              config['pagamento_pix'] ??
              readRoot('pagamento_pix') ??
              false, // default off: loja nova precisa habilitar explicitamente
          'credito': paymentOpts['credito'] ??
              config['pagamento_cartao'] ??
              readRoot('pagamento_cartao') ??
              false, // default off
          'presencial': paymentOpts['presencial'] ??
              config['pagamento_dinheiro'] ??
              readRoot('pagamento_dinheiro') ??
              true, // presencial sempre habilitado por padrão
          'credito_config': mergedCredito,
        };
      } catch (_) {
        _shopPaymentConfig = {};
      }
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();
        final d = doc.data();
        email = (user.email ?? d?['email'] ?? '').toString();
        nome = (d?['nome'] ?? user.displayName ?? '').toString();
        cpf = (d?['cpf'] ?? d?['documento'] ?? '').toString();
      }
      setState(() {
        _webClientData = {
          'publicKey': key, // CRÍTICO: passar public_key na URL para Web
          'amount': widget.valor.toString(),
          'orderId': widget.orderId,
          'clientEmail': email,
          'clientName': nome,
          'clientCpf': cpf,
          'paymentConfig': jsonEncode(_shopPaymentConfig),
          if (widget.collectOnly) 'collectOnly': '1',
        };
        _webReady = true;
        _isLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _webReady = true);
    }
  }

  Future<void> _injectAllAndHideLoading() async {
    if (_didInject) return;
    _didInject = true;
    // Clear WebView cache and cookies to avoid stale JS state on Android between reloads.
    try {
      await _controller?.clearCache();
    } catch (_) {}
    try {
      // Attempt to clear cookies/localStorage inside the WebView context as fallback
      await _controller?.runJavaScript(
          "try{ document.cookie.split(';').forEach(function(c){ document.cookie = c.replace(/=.*/, '=;expires=' + new Date().toUTCString() + ';path=/'); }); localStorage.clear(); sessionStorage.clear(); }catch(e){}");
    } catch (_) {}
    final key = await _getPublicKey();
    _injectVariables(key);
    await _injectClientData();
    // Inject variables and override carregarParcelas to ensure mobile WebView uses shop config
    final overrideCarregar = r'''
      try {
        // override only if page didn't already define or to ensure behavior
        window.__marka_override_carregar = function() {
          try {
            const installmentsSelect = document.getElementById('installments');
            const infoDiv = document.getElementById('parcelamentInfo');
            const lista = document.getElementById('parcelasLista');
            const amount = (window.amount != null) ? Number(window.amount) : (window.VALOR != null ? Number(window.VALOR) : 0);
            if (!installmentsSelect) return;
            installmentsSelect.innerHTML = '<option value=\"\">Selecione...</option>';
            if (!amount || amount <= 0) {
              const opt = document.createElement('option'); opt.value = 1; opt.textContent = '1x (valor indisponível)'; installmentsSelect.appendChild(opt);
              if(infoDiv) infoDiv.classList.remove('show');
              return;
            }
            let shopCfg = null;
            try {
              if (window.paymentConfig) shopCfg = JSON.parse(window.paymentConfig);
              else if (window.shopPaymentConfig) shopCfg = (typeof window.shopPaymentConfig === 'string') ? JSON.parse(window.shopPaymentConfig || '{}') : window.shopPaymentConfig;
            } catch (e) { shopCfg = null; }
            if (shopCfg) {
              const cfg = shopCfg.credito_config || shopCfg.config || shopCfg || {};
              try { const msgType = { action: 'debug_shopcfg', cfg: cfg, shopCfg: shopCfg, amount: amount }; if (typeof postMessageToFlutter === 'function') postMessageToFlutter(msgType); else if (typeof window.postMessageToApp === 'function') window.postMessageToApp(msgType); else if (typeof FlutterChannel !== 'undefined') FlutterChannel.postMessage(JSON.stringify(msgType)); else if (window.parent) window.parent.postMessage(JSON.stringify(msgType), '*'); } catch(e){}
              const maxParc = (cfg.max_parcelas != null) ? parseInt(cfg.max_parcelas) : (shopCfg.max_parcelas || cfg.max_parcelas || 1);
              const aceitaParcelas = (cfg.aceitar_parcelas === true) || (shopCfg.aceitar_parcelas === true) || (cfg.aceitar === true);
              // tolerant numeric parsing
              function toNum(v){
                try {
                  if (v == null) return 0;
                  if (typeof v === 'number') return v;
                  if (typeof v === 'string') {
                    const cleaned = v.replace(',', '.').replace(/[^0-9.\\-]/g,'');
                    const n = parseFloat(cleaned);
                    return isNaN(n) ? 0 : n;
                  }
                  return 0;
                } catch(e){ return 0; }
              }
              const percVista = toNum(cfg.porcentagem_a_vista || shopCfg.porcentagem_a_vista || cfg.porcentagem_a_vista || 0);
              const percParcelado = 0; // removed local parcel percentage; MP API will provide accurate parcel fees when BIN is provided
              const repassa = ((cfg.repasse_ao_cliente === true) || (String(cfg.repasse_ao_cliente || shopCfg.repasse_ao_cliente || cfg.repassa || '').toLowerCase() === 'true'));
              const max = aceitaParcelas ? Math.min(maxParc, 12) : 1;
              if (lista) lista.innerHTML = '';

              // helper to update displayed total and pay button
              function updateDisplayedTotal(total) {
                try {
                  const formatter = new Intl.NumberFormat('pt-BR', { style: 'currency', currency: 'BRL' });
                  const el = document.getElementById('valorTotal');
                  if (el) el.textContent = formatter.format(total);
                  const btn = document.getElementById('payButton');
                  if (btn) btn.textContent = COLLECT_ONLY ? 'Confirmar e ir para revisão' : ('Pagar ' + formatter.format(total));
                } catch (e) {}
              }

              for (let p=1;p<=max;p++){
                const perc = (p===1)?percVista:percParcelado;
                const total = repassa ? (amount + (amount*(perc/100))) : amount;
                const installment_amount = total / p;
                const opt = document.createElement('option'); opt.value = p; opt.textContent = `${p}x de R$ ${installment_amount.toFixed(2).replace('.',',')} (total R$ ${total.toFixed(2).replace('.',',')})`;
                installmentsSelect.appendChild(opt);
                if (lista) {
                  const item = document.createElement('div'); item.className='parcela-item'; item.innerHTML = `<span>${p}x</span><span class="parcela-preco">R$ ${total.toFixed(2).replace('.',',')}</span>`; lista.appendChild(item);
                }
              }
              // set default displayed total for 1x and attach change listener
              try {
                const total1 = repassa ? (amount + (amount*(percVista/100))) : amount;
                updateDisplayedTotal(total1);
                installmentsSelect.value = '1';
                installmentsSelect.addEventListener('change', function() {
                  try {
                    const p = parseInt(this.value) || 1;
                    const perc = (p === 1) ? percVista : percParcelado;
                    const total = repassa ? (amount + (amount*(perc/100))) : amount;
                    updateDisplayedTotal(total);
                    try { const msgTot = {action:'computed_totals', installments: p, total: total}; if (typeof postMessageToFlutter === 'function') postMessageToFlutter(msgTot); else if (typeof window.postMessageToApp === 'function') window.postMessageToApp(msgTot); else if (typeof FlutterChannel !== 'undefined') FlutterChannel.postMessage(JSON.stringify(msgTot)); else if (window.parent) window.parent.postMessage(JSON.stringify(msgTot), '*'); } catch(e){}
                  } catch(e) {}
                });
              } catch(e) {}
              if (infoDiv) infoDiv.classList.add('show');
            } else {
              const opt = document.createElement('option'); opt.value=1; opt.textContent = `1x de R$ ${amount.toFixed(2).replace('.',',')}`; installmentsSelect.appendChild(opt);
              if(infoDiv) infoDiv.classList.remove('show');
            }
          } catch(e) { console.warn('Override carregarParcelas erro', e); }
        };
        // wrap updateCheckoutValues to ensure parcels are rebuilt after any page update
        try {
          if (typeof window.updateCheckoutValues === 'function') {
            window.__orig_updateCheckoutValues = window.updateCheckoutValues;
          }
          window.updateCheckoutValues = function() {
            try { if (typeof window.__orig_updateCheckoutValues === 'function') window.__orig_updateCheckoutValues(); } catch(e) {}
            try { if (typeof window.carregarParcelas === 'function') window.carregarParcelas(); } catch(e) {}
          };
        } catch(e) {}
        // assign override to window.carregarParcelas so page will call it
        window.carregarParcelas = window.__marka_override_carregar;
      } catch(e){ console.warn('failed to inject override carregarParcelas', e); }
    ''';

    _controller?.runJavaScript(
        "if (typeof window.setPublicKey === 'function') window.setPublicKey(\"$key\");"
        "if (typeof window.updateCheckoutValues === 'function') window.updateCheckoutValues();"
        "if (typeof window.setCollectOnly === 'function') window.setCollectOnly(${widget.collectOnly});"
        "if (typeof window.applyClientPrefill === 'function') window.applyClientPrefill();");
    // inject override function
    _controller?.runJavaScript(overrideCarregar);
    // reset last requested BIN and ensure parcels are rebuilt using injected shopPaymentConfig
    _controller?.runJavaScript(
        "try{ window.__lastRequestedBin = null; if (typeof window.carregarParcelas === 'function') window.carregarParcelas(); }catch(e){}");
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _injectClientData() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      final d = doc.data();
      if (d == null) return;
      final email =
          (user.email ?? d['email'] ?? '').toString().replaceAll('"', '\\"');
      final nome = (d['nome'] ?? user.displayName ?? '')
          .toString()
          .replaceAll('"', '\\"');
      final cpf =
          (d['cpf'] ?? d['documento'] ?? '').toString().replaceAll('"', '\\"');
      _controller?.runJavaScript('''
        window.clientEmail = "$email";
        window.clientName = "$nome";
        window.clientCpf = "$cpf";
      ''');
    } catch (_) {}
  }

  // --- LÓGICA DE NEGÓCIO MANTIDA ---

  Future<String> _getPublicKey() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('shops')
          .doc(widget.shopId)
          .get();
      final mp = doc.data()?['mercadopago'] as Map<String, dynamic>?;
      final key = mp?['public_key'] as String?;
      if (key == null || key.isEmpty) {
        throw Exception(
            'Loja sem Mercado Pago configurado. Acesse Configurações → Pagamentos para conectar sua conta.');
      }
      return key;
    } catch (e) {
      rethrow;
    }
  }

  void _injectVariables(String publicKey) {
    if (kIsWeb) {
      return; // Na web a injeção via controller é diferente, trataremos no HTML
    }
    final paymentConfigJson =
        jsonEncode(_shopPaymentConfig).replaceAll("'", "\\'");
    // Inject as a JSON string and parse inside the page to avoid quoting issues
    final escaped = paymentConfigJson
        .replaceAll(r'\', r'\\')
        .replaceAll("'", r"\'")
        .replaceAll('\n', r'\\n');
    _controller?.runJavaScript('''
      window.publicKey = "$publicKey";
      window.amount = ${widget.valor};
      window.orderId = "${widget.orderId}";
      window.shopId = "${widget.shopId}";
      try {
        window.shopPaymentConfig = JSON.parse('$escaped');
      } catch(e) {
        try { window.shopPaymentConfig = $paymentConfigJson; } catch(e2) { window.shopPaymentConfig = {}; }
      }
    ''');
  }

  void _handleRawMessage(String message) async {
    debugPrint('📩 WebView -> Flutter raw: $message');
    try {
      // Limpeza segura para payloads vindos do html.window.postMessageWeb
      String cleanMessage = message;
      if (cleanMessage.startsWith('"{') && cleanMessage.endsWith('}"')) {
        cleanMessage =
            jsonDecode(cleanMessage).toString(); // remove 1 layer of stringify
      }
      final data = jsonDecode(cleanMessage) as Map<String, dynamic>;
      debugPrint(
          '📩 WebView parsed action: ${data['action'] ?? '(no action)'}');
      // Suporte para requisição de parcelas via WebView (HTML envia bin)
      if (data['action'] == 'request_installments') {
        final bin = (data['bin'] ?? '').toString();
        final amount =
            double.tryParse((data['amount'] ?? widget.valor).toString()) ??
                widget.valor;
        try {
          debugPrint(
              '🔔 request_installments received: bin=$bin amount=$amount endpoint=$_installmentsEndpoint');
          if (_installmentsEndpoint.contains('your-backend.example.com')) {
            debugPrint(
                '⚠️ _installmentsEndpoint is placeholder. Update _installmentsEndpoint to your deployed function URL.');
          }
          final resp = await http.post(
            Uri.parse(_installmentsEndpoint),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(
                {'amount': amount, 'bin': bin, 'shopId': widget.shopId}),
          );
          debugPrint(
              '→ installments endpoint response status: ${resp.statusCode}');
          final respBody = resp.body;
          debugPrint('→ installments endpoint response body: $respBody');
          if (resp.statusCode == 200) {
            final body = jsonDecode(resp.body);
            final dynamic mpData = body['data'] ?? body;
            final jsonStr = jsonEncode(mpData);
            // Injeta diretamente na WebView chamando a função JS definida no HTML
            _controller?.runJavaScript(
                'try{ if (typeof populateInstallments === "function") populateInstallments($jsonStr); }catch(e){}');
          } else {
            // fallback: call local carregarParcelas(bin) in the webview (will try MP public endpoint)
            _controller?.runJavaScript(
                "try{ if (typeof carregarParcelas === 'function') carregarParcelas('$bin'); }catch(e){}");
          }
        } catch (e) {
          debugPrint('Erro ao obter parcelas do backend: $e');
          _controller?.runJavaScript(
              "try{ if (typeof carregarParcelas === 'function') carregarParcelas('$bin'); }catch(e){}");
        }
        return;
      }
      if (data['action'] == 'clear_installments') {
        // limpa/select exibe fallback 1x
        _controller?.runJavaScript(
            "try{ if (typeof populateInstallments === 'function') populateInstallments([]); }catch(e){}");
        return;
      }
      if (data['action'] == 'card_data_confirmed') {
        if (widget.collectOnly && mounted) {
          // If client requested saveCard, persist token server-side (save minimal info in Firestore)
          final saveCard = data['saveCard'] ?? false;
          if (saveCard == true) {
            try {
              final user = FirebaseAuth.instance.currentUser;
              if (user != null) {
                await FirebaseFirestore.instance
                    .collection('users')
                    .doc(user.uid)
                    .collection('saved_cards')
                    .add({
                  'cardToken': data['cardToken'],
                  'paymentMethodId': data['paymentMethodId'],
                  'issuerId': data['issuerId'],
                  'maskedNumber': data['maskedNumber'] ?? '',
                  'brand': data['brand'] ?? '',
                  'created_at': FieldValue.serverTimestamp(),
                });
              }
            } catch (_) {}
          }
          if (!mounted) return;
          Navigator.of(context).pop({
            'cardToken': data['cardToken'],
            'installments': data['installments'],
            'email': data['email'],
            'saveCard': saveCard,
            'paymentMethodId': data['paymentMethodId'],
            'issuerId': data['issuerId'],
          });
        }
        return;
      }
      if (data['action'] == 'process_payment') {
        debugPrint(
            '🔔 process_payment received from WebView: installments=${data['installments']} paymentMethodId=${data['paymentMethodId']} issuerId=${data['issuerId']}');
        if (widget.collectOnly) return;
        await _processarPagamento(
          cardToken: data['cardToken'],
          saveToken: data['saveToken'],
          saveCard: data['saveCard'] ?? false,
          installments: data['installments'],
          email: data['email'],
          cpf: data['cpf'] ?? '',
          paymentMethodId: data['paymentMethodId'],
          issuerId: data['issuerId'],
        );
      } else if (data['action'] == 'error') {
        _showError(data['message'] ?? 'Erro desconhecido');
      } else if (data['action'] == 'loaded') {
        await _injectAllAndHideLoading();
      }
    } catch (e) {
      debugPrint("Erro ao processar msg: $e");
    }
  }

  Future<void> _processarPagamento({
    required String cardToken,
    String? saveToken,
    bool saveCard = false,
    required int installments,
    required String email,
    String cpf = '',
    String? paymentMethodId,
    dynamic issuerId,
  }) async {
    setState(() => _isLoading = true);
    try {
      // Debug: log outgoing payment payload
      final payloadDebug = {
        'cardToken': cardToken,
        'saveToken': saveToken,
        'saveCard': saveCard,
        'installments': installments,
        'email': email,
        'valor': widget.valor,
        'shopId': widget.shopId,
        'orderId': widget.orderId,
        'paymentMethodId': paymentMethodId,
        'issuerId': issuerId,
      };
      debugPrint('🔔 _processarPagamento payload: ${jsonEncode(payloadDebug)}');
      final idToken = await _getPaymentIdToken();
      if (idToken == null) return;

      final response = await http.post(
        Uri.parse(
            'https://us-central1-wismart-118c3.cloudfunctions.net/criarPagamento'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'data': {
            'cardToken': cardToken,
            'saveToken': saveToken,
            'saveCard': saveCard,
            'email': email,
            'installments': installments,
            'valor': widget.valor,
            'shopId': widget.shopId,
            'orderId': widget.orderId,
            'descricao': "Reserva: ${widget.serviceDoc['nome'] ?? 'Serviço'}",
            'idToken': idToken,
            // CORREÇÃO 1: CPF incluído para payer.identification no Mercado Pago
            if (cpf.isNotEmpty) 'cpf': cpf,
            if (paymentMethodId != null) 'paymentMethodId': paymentMethodId,
            if (issuerId != null) 'issuerId': issuerId,
          }
        }),
      );
      debugPrint('→ criarPagamento response status: ${response.statusCode}');
      debugPrint('→ criarPagamento response body: ${response.body}');

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result['success'] == true) {
          await _salvarAgendamento(result['paymentId'].toString(), cpf: cpf);
        } else {
          _showError(result['error'] ?? 'Pagamento recusado');
        }
      } else {
        final error = jsonDecode(response.body);
        _showError(error['error']?.toString() ?? 'Erro no pagamento');
      }
    } catch (e) {
      _showError('Erro ao processar pagamento');
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

  Future<void> _salvarAgendamento(String paymentId, {String cpf = ''}) async {
    final user = FirebaseAuth.instance.currentUser!;
    final bookingDate = DateTime(widget.date.year, widget.date.month,
        widget.date.day, widget.time.hour, widget.time.minute);

    // CORREÇÃO BUG 5: Usar formatação manual segura em vez de widget.time.format(context)
    // para evitar erros ao chamar em contexto assíncrono
    final timeStr =
        '${widget.time.hour.toString().padLeft(2, '0')}:${widget.time.minute.toString().padLeft(2, '0')}';

    final serviceName = widget.serviceDoc['nome']?.toString() ?? 'Serviço';
    final profData =
        widget.professionalDoc.data() as Map<String, dynamic>? ?? {};
    final professionalName = profData['nome']?.toString() ?? 'Profissional';

    // CORREÇÃO BUG 2: formatar data para exibição
    final dateStr =
        '${widget.date.day.toString().padLeft(2, '0')}/${widget.date.month.toString().padLeft(2, '0')}/${widget.date.year}';

    await FirebaseFirestore.instance.collection('appointments').add({
      'shopId': widget.shopId,
      'clientId': user.uid,
      'client_nome': user.displayName ?? '',
      'servico_nome': serviceName,
      'profissionalId': widget.professionalDoc.id,
      'profissional_nome': professionalName,
      'valor_total': widget.valor,
      'valor_pago': widget.valor,
      'data_agendamento': Timestamp.fromDate(bookingDate),
      'horario': timeStr,
      'status': 'confirmado',
      'metodo_pagamento': 'Cartão de Crédito',
      'payment_id': paymentId,
      // CORREÇÃO BUG 3: salvar CPF do cliente no agendamento
      if (cpf.isNotEmpty) 'cpf_cliente': cpf,
      'criado_em': FieldValue.serverTimestamp(),
    });

    if (mounted) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(
            builder: (_) => BookingSuccessPage(
                  // CORREÇÃO BUG 2: dados reais em vez de hardcoded
                  serviceName: serviceName,
                  professionalName: professionalName,
                  date: dateStr,
                  time: timeStr,
                  isPaid: true,
                )),
        (r) => r.isFirst,
      );
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: Colors.red));
  }

  Map<String, String> _buildInitialData() {
    // Para mobile retornamos minimal; para web usamos o preparado em _prepareWebInitialData
    if (kIsWeb) {
      return _webClientData ??
          {
            'amount': widget.valor.toString(),
            'orderId': widget.orderId,
            if (widget.collectOnly) 'collectOnly': '1',
          };
    }
    return {
      'amount': widget.valor.toString(),
      'orderId': widget.orderId,
      if (widget.collectOnly) 'collectOnly': '1',
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Pagamento Seguro"),
        backgroundColor: AppColors.primaryPurple,
        foregroundColor: Colors.white,
      ),
      body: Stack(
        children: [
          // Se for Web e ainda não estamos prontos (busca de public_key / cliente), mostramos loader
          if (kIsWeb && !_webReady)
            const Center(child: CircularProgressIndicator()),
          // USANDO O NOSSO COMPONENTE UNIVERSAL
          if (_planRestricted)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.lock_outline,
                        size: 64, color: Colors.grey),
                    const SizedBox(height: 16),
                    const Text(
                      "Recurso Indisponível",
                      style:
                          TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      "Seu plano atual não permite pagamentos online. Faça um upgrade para desbloquear.",
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey),
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton(
                      onPressed: () => Navigator.pop(context),
                      style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primaryPurple),
                      child: const Text("Voltar",
                          style: TextStyle(color: Colors.white)),
                    )
                  ],
                ),
              ),
            )
          else if (!kIsWeb || _webReady)
            _webViewWidget ??= buildWebView(
              assetPath: 'assets/html/checkout_transparente.html',
              onMessage: _handleRawMessage,
              onControllerCreated: (controller) => _controller = controller,
              initialData: _buildInitialData(),
            ),
          if (_isLoading && !_planRestricted)
            const Center(child: CircularProgressIndicator()),
        ],
      ),
    );
  }
}
