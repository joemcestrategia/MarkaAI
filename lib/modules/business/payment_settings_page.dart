import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_colors.dart';
import '../../core/services/session_service.dart';

class PaymentSettingsPage extends StatefulWidget {
  final VoidCallback onClose;
  const PaymentSettingsPage({super.key, required this.onClose});

  @override
  State<PaymentSettingsPage> createState() => _PaymentSettingsPageState();
}

class _PaymentSettingsPageState extends State<PaymentSettingsPage>
    with SingleTickerProviderStateMixin {
  bool _isLoading = true;
  bool _isConnecting = false;
  bool _isConnected = false;
  bool _canEdit = false; // somente dono pode editar conexão
  String? _connectedAt;
  bool _showHelpView = false;
  String? _shopId;
  late AnimationController _animationController;
  final TextEditingController _publicKeyCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    _initSetup();
    _setupRealtimeListener();
  }

  @override
  void dispose() {
    _animationController.dispose();
    _publicKeyCtrl.dispose();
    super.dispose();
  }

  Future<void> _initSetup() async {
    await _checkAuthAndShop();
    await _loadConnectionStatus();
    if (mounted) _animationController.forward();
  }

  // 🔄 LISTENER EM TEMPO REAL - Atualiza quando há mudanças no Firestore
  void _setupRealtimeListener() {
    Future.delayed(const Duration(seconds: 1), () {
      if (_shopId == null || !mounted) return;

      FirebaseFirestore.instance
          .collection('shops')
          .doc(_shopId)
          .snapshots()
          .listen(
        (docSnapshot) {
          if (!mounted) return;

          final data = docSnapshot.data() ?? {};
          final accessToken = data['mercadopago']?['access_token']?.toString() ??
              data['mp_access_token']?.toString() ??
              '';
          final connectedFlag = data['mercadopago']?['connected'];
          final isConnected = connectedFlag is bool ? connectedFlag : accessToken.isNotEmpty;
          final publicKey = data['mercadopago']?['public_key']?.toString() ??
              data['mp_public_key']?.toString() ??
              '';

          // Se o status mudou, atualiza a UI
          if (isConnected != _isConnected) {
            debugPrint("🔄 [REALTIME] Status de pagamento atualizado!");
            
            setState(() {
              _isConnected = isConnected;
              if (_isConnected) {
                final timestamp = data['mercadopago']?['updated_at'] as Timestamp?;
                if (timestamp != null) {
                  _connectedAt =
                      DateFormat('dd/MM/yyyy HH:mm').format(timestamp.toDate());
                } else {
                  _connectedAt = "Data desconhecida";
                }
                
                // Mostra notificação de sucesso
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('✅ Conectado com sucesso ao Mercado Pago!'),
                    backgroundColor: Colors.green,
                    duration: Duration(seconds: 3),
                  ),
                );
              }
            });
            if (publicKey.isNotEmpty && _publicKeyCtrl.text != publicKey) {
              _publicKeyCtrl.text = publicKey;
            }
          }
        },
        onError: (error) {
          debugPrint("❌ Erro no listener realtime: $error");
        },
      );
    });
  }

  Future<void> _checkAuthAndShop() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      String? id = await SessionService.getShopId();

      if ((id == null || id.isEmpty) && user != null) {
        debugPrint("🔍 [Pagamentos] Buscando ID no servidor...");
        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();
        if (userDoc.exists) {
          id = userDoc.data()?['shopId'];
          if (id != null) await SessionService.saveShopId(id);
        }
      }

      if (mounted) {
        setState(() {
          _shopId = id;
        });
      }

      if (user == null || _shopId == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Erro de sessão. Faça login novamente.'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      // Additional guard: ensure the current user is the owner of the shop (only owners can configure Mercado Pago)
      try {
        final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
        final udata = userDoc.exists ? userDoc.data() as Map<String, dynamic> : <String, dynamic>{};
        final userShopId = udata['shopId'];
        final userRole = (udata['tipo'] ?? udata['role'] ?? '').toString();
        // Se não for dono, permite visualizar (sem editar)
        if (userShopId != _shopId || !(userRole == 'dono' || userRole == 'business')) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Visualização apenas: apenas o dono pode alterar a conexão do Mercado Pago.'), backgroundColor: Colors.orange));
            _canEdit = false;
          }
        } else {
          _canEdit = true;
        }
      } catch (e) {
        // If any error occurs, fail silently and allow the page to continue (safety)
        debugPrint('Erro ao verificar ownership: $e');
      }
    } catch (e) {
      debugPrint("Erro ao verificar auth: $e");
    }
  }

  Future<void> _loadConnectionStatus() async {
    if (_shopId == null) return;
    setState(() => _isLoading = true);

    try {
      final docRef =
          FirebaseFirestore.instance.collection('shops').doc(_shopId);
      final doc = await docRef.get();

      if (doc.metadata.isFromCache) {
        // Cache read
      } else {
        debugPrint("💸 [SERVER] Baixando status de pagamento atualizado.");
      }

      if (!doc.exists) return;

      final data = doc.data() ?? {};
      final accessToken = data['mercadopago']?['access_token']?.toString() ??
          data['mp_access_token']?.toString() ??
          '';
      final connectedFlag = data['mercadopago']?['connected'];
      final isConnected = connectedFlag is bool ? connectedFlag : accessToken.isNotEmpty;
      final publicKey = data['mercadopago']?['public_key']?.toString() ??
          data['mp_public_key']?.toString() ??
          '';

      if (mounted) {
        setState(() {
          _isConnected = isConnected;
          if (_isConnected) {
            final timestamp = data['mercadopago']?['updated_at'] as Timestamp?;
            if (timestamp != null) {
              _connectedAt =
                  DateFormat('dd/MM/yyyy HH:mm').format(timestamp.toDate());
            } else {
              _connectedAt = "Data desconhecida";
            }
          }
        });
        if (publicKey.isNotEmpty && _publicKeyCtrl.text != publicKey) {
          _publicKeyCtrl.text = publicKey;
        }
      }
    } catch (e) {
      debugPrint('Erro ao ler status: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _connectWithMercadoPago() async {
    if (_shopId == null) return;
    setState(() => _isConnecting = true);

    const clientId = '8404269586602737';
    const redirectUri =
        'https://us-central1-wismart-118c3.cloudfunctions.net/mercadopagoCallback';
    final state = 'shop-$_shopId-${DateTime.now().millisecondsSinceEpoch}';

    final authUrl = Uri.parse(
      'https://auth.mercadopago.com.br/authorization'
      '?client_id=$clientId'
      '&response_type=code'
      '&platform_id=mp'
      '&redirect_uri=${Uri.encodeComponent(redirectUri)}'
      '&state=${Uri.encodeComponent(state)}',
    );

    try {
      if (!await launchUrl(authUrl, mode: LaunchMode.externalApplication)) {
        throw 'Não foi possível abrir o navegador';
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Erro ao abrir link: $e'),
              backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isConnecting = false);
    }
  }

  Future<void> _disconnectMercadoPago() async {
    if (_shopId == null) return;

    bool? confirm = await showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(Icons.link_off, color: Colors.red[700], size: 30),
              ),
              const SizedBox(height: 20),
              const Text(
                "Desconectar Pagamentos?",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                "Se você desconectar, seus clientes não poderão mais pagar via App.\n\nTem certeza?",
                style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 28),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(color: Colors.grey[300]!),
                        ),
                      ),
                      child: const Text("Cancelar",
                          style: TextStyle(color: Colors.black87)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red[600],
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                      ),
                      child: const Text("Desconectar",
                          style: TextStyle(fontWeight: FontWeight.w600)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    if (confirm != true) return;

    setState(() => _isConnecting = true);

    try {
      debugPrint("✂️ [WRITE] Removendo credenciais do Mercado Pago...");
      await FirebaseFirestore.instance
          .collection('shops')
          .doc(_shopId)
          .update({
        'mercadopago.access_token': FieldValue.delete(),
        'mercadopago.refresh_token': FieldValue.delete(),
        'mercadopago.user_id': FieldValue.delete(),
        'mercadopago.public_key': FieldValue.delete(),
        'mercadopago.connected': false,
        'mercadopago.updated_at': FieldValue.serverTimestamp(),
        'mp_access_token': FieldValue.delete(),
        'mp_public_key': FieldValue.delete(),
        'mp_refresh_token': FieldValue.delete(),
        'mp_user_id': FieldValue.delete(),
        'mp_expiration_date': FieldValue.delete(),
        'payment_configured': false,
      });

      if (mounted) {
        setState(() {
          _isConnected = false;
          _connectedAt = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text("Desconectado com sucesso."),
              backgroundColor: Colors.grey),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Erro ao desconectar: $e'),
              backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isConnecting = false);
    }
  }


  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 600;

    return Material(
      color: Colors.white,
      child: SafeArea(
        child: Column(
          children: [
            // --- HEADER REFINADO ---
            Container(
              height: 64,
              padding: EdgeInsets.symmetric(
                horizontal: isMobile ? 16 : 24,
                vertical: 8,
              ),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: Colors.grey[200]!,
                    width: 1,
                  ),
                ),
                color: Colors.white,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _showHelpView ? 'Ajuda: Conexão' : 'Pagamentos',
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.5,
                          ),
                        ),
                        if (!_showHelpView)
                          Text(
                            'Conecte sua conta Mercado Pago',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                      ],
                    ),
                  ),
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (!isMobile)
                          Tooltip(
                            message: _showHelpView ? 'Voltar' : 'Ajuda',
                            child: IconButton(
                              icon: Icon(
                                _showHelpView
                                    ? Icons.keyboard_arrow_left
                                    : Icons.help_outline,
                                color: AppColors.primaryPurple,
                              ),
                              onPressed: () =>
                                  setState(() => _showHelpView = !_showHelpView),
                            ),
                          ),
                        Tooltip(
                          message: 'Fechar',
                          child: IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: widget.onClose,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (isMobile)
                    IconButton(
                      icon: Icon(
                        _showHelpView
                            ? Icons.keyboard_arrow_left
                            : Icons.help_outline,
                        color: AppColors.primaryPurple,
                      ),
                      onPressed: () =>
                          setState(() => _showHelpView = !_showHelpView),
                    ),
                ],
              ),
            ),

            // --- CONTEÚDO COM ANIMAÇÃO ---
            Expanded(
              child: _isLoading
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CircularProgressIndicator(
                            color: AppColors.primaryPurple,
                            strokeWidth: 2.5,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Carregando...',
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    )
                  : AnimatedSwitcher(
                      duration: const Duration(milliseconds: 400),
                      transitionBuilder: (child, animation) {
                        return FadeTransition(opacity: animation, child: child);
                      },
                      child: _showHelpView
                          ? _buildHelpContent()
                          : _buildMainContent(),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMainContent() {
    final isMobile = MediaQuery.of(context).size.width < 600;

    return SingleChildScrollView(
      padding: EdgeInsets.all(isMobile ? 20 : 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_isConnected) _buildConnectedState() else _buildDisconnectedState(),
          const SizedBox(height: 48),
          _buildSecurityNote(),
        ],
      ),
    );
  }

  // ✅ ESTADO: CONECTADO (MELHORADO)
  Widget _buildConnectedState() {
    return Column(
      children: [
        // Cartão de Status Premium
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.green[50]!,
                Colors.green[100]!.withValues(alpha: 0.3),
              ],
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.green[300]!, width: 1.5),
            boxShadow: [
              BoxShadow(
                color: Colors.green[200]!.withValues(alpha: 0.3),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: Colors.green[600],
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Center(
                        child: Icon(Icons.check_rounded,
                            color: Colors.white, size: 28),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Mercado Pago Ativo',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.3,
                            ),
                          ),
                          if (_connectedAt != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Text(
                                'Desde $_connectedAt',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.grey[700],
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Container(
                  height: 1,
                  color: Colors.green[300],
                ),
                const SizedBox(height: 16),
                Text(
                  'Seus clientes já podem realizar pagamentos via PIX ou Cartão de Crédito diretamente pelo app. O dinheiro é transferido automaticamente para sua conta Mercado Pago.',
                  style: TextStyle(
                    color: Colors.grey[800],
                    height: 1.6,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 36),

        // Public Key (preenchida automaticamente ao conectar)
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.blueGrey[50],
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.blueGrey[100]!),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Public Key do Mercado Pago',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              const Text(
                'Preenchida automaticamente ao conectar. Necessária para parcelas e tokenização.',
                style: TextStyle(fontSize: 12, color: Colors.black54),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _publicKeyCtrl,
                readOnly: true,
                decoration: InputDecoration(
                  hintText: 'Não informada (reconecte a conta)',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  isDense: true,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // Botão de Desconectar com Hover
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.red[300]!.withValues(alpha: 0.1),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: SizedBox(
            width: double.infinity,
            height: 56,
            child: Material(
              color: Colors.transparent,
                child: OutlinedButton.icon(
                onPressed: (!_canEdit || _isConnecting) ? null : _disconnectMercadoPago,
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red[700],
                  side: BorderSide(
                    color: Colors.red[300]!,
                    width: 1.5,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  backgroundColor: Colors.red[50]?.withValues(alpha: 0.3),
                  disabledForegroundColor: Colors.grey[400],
                ),
                icon: _isConnecting
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          color: Colors.red[700],
                          strokeWidth: 2.5,
                        ),
                      )
                    : Icon(Icons.link_off, color: Colors.red[700]),
                label: Text(
                  _isConnecting ? "DESCONECTANDO..." : "DESCONECTAR CONTA",
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    letterSpacing: 0.3,
                    color: _isConnecting
                        ? Colors.grey[600]
                        : Colors.red[700],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // 🔌 ESTADO: DESCONECTADO (PREMIUM)
  Widget _buildDisconnectedState() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.blue[50]!,
                Colors.indigo[50]!.withValues(alpha: 0.4),
              ],
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: Colors.blue[200]!,
              width: 1.5,
            ),
            boxShadow: [
                BoxShadow(
                      color: Colors.blue[200]!.withValues(alpha: 0.2),
                      blurRadius: 16,
                      offset: const Offset(0, 8),
                    ),
            ],
          ),
          child: Column(
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                      BoxShadow(
                      color: Colors.blue[300]!.withValues(alpha: 0.15),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Image.network(
                  "https://logospng.org/download/mercado-pago/logo-mercado-pago-icone-1024.png",
                  errorBuilder: (c, e, s) => Icon(
                    Icons.account_balance_wallet,
                    size: 44,
                    color: Colors.blue[600],
                  ),
                ),
              ),
              const SizedBox(height: 28),
              const Text(
                'Receba Pagamentos Online',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.3,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                'Conecte sua conta Mercado Pago para receber PIX e Cartão de Crédito dos seus clientes de forma segura e automática.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.grey[700],
                  fontSize: 14,
                  height: 1.6,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 36),

        // Botão de Conexão com Estilo Premium
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF009EE3).withValues(alpha: 0.25),
                blurRadius: 16,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: SizedBox(
            width: double.infinity,
            height: 58,
            child: Material(
              color: Colors.transparent,
              child: ElevatedButton.icon(
                onPressed: (!_canEdit || _isConnecting) ? null : _connectWithMercadoPago,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF009EE3),
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: Colors.grey[400],
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  elevation: 0,
                  shadowColor: Colors.transparent,
                ),
                icon: _isConnecting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2.5,
                        ),
                      )
                    : const Icon(Icons.link, size: 20),
                label: Text(
                  _isConnecting
                      ? 'CONECTANDO...'
                      : 'CONECTAR AGORA',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // 📖 CONTEÚDO DE AJUDA (MELHORADO)
  Widget _buildHelpContent() {
    final isMobile = MediaQuery.of(context).size.width < 600;

    return SingleChildScrollView(
      padding: EdgeInsets.all(isMobile ? 20 : 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Como conectar sua conta',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 28),
          for (int i = 1; i <= 5; i++)
            _buildStepCard(
              i,
              _getStepText(i),
              _getStepIcon(i),
            ),
          const SizedBox(height: 32),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.blue[50],
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.blue[200]!, width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: Colors.blue[200]!.withValues(alpha: 0.15),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.blue[600],
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.verified_user,
                      color: Colors.white, size: 20),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    "Utilizamos o protocolo oficial de segurança OAuth. Seus dados nunca passam pelos nossos servidores.",
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.blue[900],
                      height: 1.5,
                      fontWeight: FontWeight.w500,
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

  Widget _buildStepCard(int number, String text, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.grey[50],
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.grey[200]!, width: 1),
          boxShadow: [
            BoxShadow(
              color: Colors.grey[200]!.withValues(alpha: 0.4),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.primaryPurple,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Center(
                  child: Text(
                    '$number',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(icon, size: 18, color: AppColors.primaryPurple),
                        const SizedBox(width: 8),
                        Text(
                          'Passo $number',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      text,
                      style: const TextStyle(
                        fontSize: 14,
                        height: 1.5,
                        fontWeight: FontWeight.w500,
                        color: Colors.black87,
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

  String _getStepText(int step) {
    switch (step) {
      case 1:
        return 'Clique no botão azul "Conectar Agora".';
      case 2:
        return 'Você será levado ao site seguro do Mercado Pago.';
      case 3:
        return 'Faça login na conta onde deseja receber o dinheiro.';
      case 4:
        return 'Autorize o "MarkaAI" a processar pagamentos.';
      case 5:
        return 'Pronto! Você voltará para cá e verá o status verde.';
      default:
        return '';
    }
  }

  IconData _getStepIcon(int step) {
    switch (step) {
      case 1:
        return Icons.touch_app;
      case 2:
        return Icons.language;
      case 3:
        return Icons.login;
      case 4:
        return Icons.verified_user;
      case 5:
        return Icons.check_circle;
      default:
        return Icons.info;
    }
  }

  Widget _buildSecurityNote() {
    return Center(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.lock, size: 14, color: Colors.grey[500]),
          const SizedBox(width: 8),
          Text(
            'Conexão criptografada ponta a ponta',
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[600],
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}