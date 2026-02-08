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
  State<CheckoutTransparentePage> createState() => _CheckoutTransparentePageState();
}

class _CheckoutTransparentePageState extends State<CheckoutTransparentePage> {
  WebViewController? _controller;
  bool _isLoading = true;
  bool _didInject = false;
  Widget? _webViewWidget;

  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      // Para Web, prepare public key e dados do cliente antes de construir o iframe
      _prepareWebInitialData();
    } else {
      // Android/iOS: fallback caso o HTML não envie 'loaded' (canal pode demorar)
      Future.delayed(const Duration(milliseconds: 2500), () async {
        if (!mounted || !_isLoading || _didInject) return;
        await _injectAllAndHideLoading();
      });
    }
  }

  Map<String, String>? _webClientData;
  bool _webReady = false;

  Future<void> _prepareWebInitialData() async {
    try {
      final key = await _getPublicKey();
      String email = '';
      String nome = '';
      String cpf = '';
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
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
    final key = await _getPublicKey();
    _injectVariables(key);
    await _injectClientData();
    _controller?.runJavaScript(
      "if (typeof window.setPublicKey === 'function') window.setPublicKey(\"$key\");"
      "if (typeof window.updateCheckoutValues === 'function') window.updateCheckoutValues();"
      "if (typeof window.setCollectOnly === 'function') window.setCollectOnly(${widget.collectOnly});"
      "if (typeof window.applyClientPrefill === 'function') window.applyClientPrefill();",
    );
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _injectClientData() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      final d = doc.data();
      if (d == null) return;
      final email = (user.email ?? d['email'] ?? '').toString().replaceAll('"', '\\"');
      final nome = (d['nome'] ?? user.displayName ?? '').toString().replaceAll('"', '\\"');
      final cpf = (d['cpf'] ?? d['documento'] ?? '').toString().replaceAll('"', '\\"');
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
      final doc = await FirebaseFirestore.instance.collection('shops').doc(widget.shopId).get();
      final mp = doc.data()?['mercadopago'] as Map<String, dynamic>?;
      return mp?['public_key'] ?? 'APP_USR-456aad35-79ef-4f9a-a090-f71c7b1a5765';
    } catch (e) {
      return 'APP_USR-456aad35-79ef-4f9a-a090-f71c7b1a5765';
    }
  }

  void _injectVariables(String publicKey) {
    if (kIsWeb) return; // Na web a injeção via controller é diferente, trataremos no HTML
    _controller?.runJavaScript('''
      window.publicKey = "$publicKey";
      window.amount = ${widget.valor};
      window.orderId = "${widget.orderId}";
    ''');
  }

  void _handleRawMessage(String message) async {
    try {
      final data = jsonDecode(message) as Map<String, dynamic>;
      if (data['action'] == 'card_data_confirmed') {
        if (widget.collectOnly && mounted) {
          Navigator.of(context).pop({
            'cardToken': data['cardToken'],
            'installments': data['installments'],
            'email': data['email'],
            'saveCard': data['saveCard'] ?? false,
            'paymentMethodId': data['paymentMethodId'],
            'issuerId': data['issuerId'],
          });
        }
        return;
      }
      if (data['action'] == 'process_payment') {
        if (widget.collectOnly) return;
        await _processarPagamento(
          cardToken: data['cardToken'],
          installments: data['installments'],
          email: data['email'],
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
            'valor': widget.valor,
            'shopId': widget.shopId,
            'orderId': widget.orderId,
            'descricao': "Reserva: ${widget.serviceDoc['nome'] ?? 'Serviço'}",
            'idToken': idToken,
            if (paymentMethodId != null) 'paymentMethodId': paymentMethodId,
            if (issuerId != null) 'issuerId': issuerId,
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
      _showError('Erro ao processar pagamento');
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

  Future<void> _salvarAgendamento(String paymentId) async {
    final user = FirebaseAuth.instance.currentUser!;
    final bookingDate = DateTime(widget.date.year, widget.date.month, widget.date.day, widget.time.hour, widget.time.minute);

    await FirebaseFirestore.instance.collection('appointments').add({
      'shopId': widget.shopId,
      'clientId': user.uid,
      'client_nome': user.displayName ?? '',
      'servico_nome': widget.serviceDoc['nome'] ?? 'Serviço',
      'profissionalId': widget.professionalDoc.id,
      'valor_total': widget.valor,
      'valor_pago': widget.valor,
      'data_agendamento': Timestamp.fromDate(bookingDate),
      'horario': widget.time.format(context),
      'status': 'confirmado',
      'metodo_pagamento': 'Cartão de Crédito',
      'payment_id': paymentId,
      'criado_em': FieldValue.serverTimestamp(),
    });

    if (mounted) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const BookingSuccessPage(
          serviceName: "Serviço", professionalName: "Profissional", date: "Data", time: "Hora", isPaid: true,
        )),
        (r) => r.isFirst,
      );
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message), backgroundColor: Colors.red));
  }

  Map<String, String> _buildInitialData() {
    // Para mobile retornamos minimal; para web usamos o preparado em _prepareWebInitialData
    if (kIsWeb) {
      return _webClientData ?? {
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
          if (!kIsWeb || _webReady)
            _webViewWidget ??= buildWebView(
              assetPath: 'assets/html/checkout_transparente.html',
              onMessage: _handleRawMessage,
              onControllerCreated: (controller) => _controller = controller,
              initialData: _buildInitialData(),
            ),
          if (_isLoading) const Center(child: CircularProgressIndicator()),
        ],
      ),
    );
  }
}