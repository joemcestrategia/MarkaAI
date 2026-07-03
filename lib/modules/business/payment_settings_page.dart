import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_colors.dart';
import '../../core/services/session_service.dart';
import '../../core/services/shop_data_cache_service.dart';
import 'subscription_service.dart';

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
  // Observação: configurações de taxa/parcelamento são centralizadas em BusinessSettingsPage

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
    super.dispose();
  }

  Future<void> _initSetup() async {
    await _checkAuthAndShop();
    await _loadConnectionStatus();
    if (mounted) _animationController.forward();
  }

  // 🔄 LISTENER EM TEMPO REAL - Atualiza quando há mudanças no Supabase
  void _setupRealtimeListener() {
    Future.delayed(const Duration(seconds: 1), () {
      if (_shopId == null || !mounted) return;

      Supabase.instance.client
          .from('shops')
          .stream(primaryKey: ['id'])
          .eq('id', _shopId!)
          .listen(
        (data) {
          if (!mounted || data.isEmpty) return;

          final shopData = data.first;
          final mpData = shopData['mercadopago'] as Map<String, dynamic>? ?? {};
          final accessToken = mpData['access_token']?.toString() ??
              shopData['mp_access_token']?.toString() ??
              '';
          final connectedFlag = mpData['connected'];
          final isConnected =
              connectedFlag is bool ? connectedFlag : accessToken.isNotEmpty;

          // Se o status mudou, atualiza a UI
          if (isConnected != _isConnected) {
            debugPrint("🔄 [REALTIME] Status de pagamento atualizado!");

            setState(() {
              _isConnected = isConnected;
              if (_isConnected) {
                final updatedAt = mpData['updated_at'];
                if (updatedAt != null) {
                  final date = DateTime.parse(updatedAt.toString());
                  _connectedAt = DateFormat('dd/MM/yyyy HH:mm').format(date);
                } else {
                  _connectedAt = "Data desconhecida";
                }

                // Mostra notificação de sucesso
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('⚡ Conectado com sucesso ao Mercado Pago!'),
                    backgroundColor: Colors.green,
                    duration: Duration(seconds: 3),
                  ),
                );
              }
            });
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
      final user = Supabase.instance.client.auth.currentUser;
      String? id = await SessionService.getShopId();

      if ((id == null || id.isEmpty) && user != null) {
        debugPrint("🔍 [Pagamentos] Buscando ID no servidor...");
        final userDoc = await Supabase.instance.client
            .from('users')
            .select('shop_id')
            .eq('id', user.id)
            .maybeSingle();

        if (userDoc != null) {
          id = userDoc['shop_id'];
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
        final userDoc = await Supabase.instance.client
            .from('users')
            .select('shop_id, role')
            .eq('id', user.id)
            .maybeSingle();

        if (userDoc != null) {
          final userShopId = userDoc['shop_id'];
          final userRole = (userDoc['role'] ?? '').toString();
          // Se não for dono, permite visualizar (sem editar)
          if (userShopId != _shopId ||
              !(userRole == 'dono' || userRole == 'business')) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text(
                      'Visualização apenas: apenas o dono pode alterar a conexão do Mercado Pago.'),
                  backgroundColor: Colors.orange));
              _canEdit = false;
            }
          } else {
            _canEdit = true;
          }
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
      final doc = await Supabase.instance.client
          .from('shops')
          .select()
          .eq('id', _shopId!)
          .maybeSingle();

      if (doc == null) return;

      final mpData = doc['mercadopago'] as Map<String, dynamic>? ?? {};
      final accessToken = mpData['access_token']?.toString() ??
          doc['mp_access_token']?.toString() ??
          '';
      final connectedFlag = mpData['connected'];
      final isConnected =
          connectedFlag is bool ? connectedFlag : accessToken.isNotEmpty;

      if (mounted) {
        setState(() {
          _isConnected = isConnected;
          if (_isConnected) {
            final updatedAt = mpData['updated_at'];
            if (updatedAt != null) {
              final date = DateTime.parse(updatedAt.toString());
              _connectedAt = DateFormat('dd/MM/yyyy HH:mm').format(date);
            } else {
              _connectedAt = "Data desconhecida";
            }
          }
        });
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
        'https://uhccgcojwqvkfyzrmebv.supabase.co/functions/v1/mercadopagoCallback';
    final state = 'shop-$_shopId-${DateTime.now().millisecondsSinceEpoch}';
    // Cache-buster: garante que o navegador nunca reutilize a sessão anterior
    final nonce = DateTime.now().millisecondsSinceEpoch;

    final authUrl = Uri.parse(
      'https://auth.mercadopago.com.br/authorization'
      '?client_id=$clientId'
      '&response_type=code'
      '&platform_id=mp'
      '&scope=read,write,offline_access'
      '&redirect_uri=${Uri.encodeComponent(redirectUri)}'
      '&state=${Uri.encodeComponent(state)}'
      '&_t=$nonce', // ← forçar URL única a cada tentativa (anti-cache)
    );

    try {
      if (!await launchUrl(
        authUrl,
        mode: LaunchMode.externalApplication,
      )) {
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
      await Supabase.instance.client.from('shops').update({
        'mercadopago': null,
      }).eq('id', _shopId!);

      // Invalida o cache
      ShopDataCacheService().invalidate(_shopId!, 'config');

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
    // final isMobile = MediaQuery.of(context).size.width < 600; // Not used anymore

    return Scaffold(
      backgroundColor: const Color(0xFFF2F4F8),
      appBar: AppBar(
        title: const Text('Pagamentos',
            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        centerTitle: true,
        backgroundColor: AppColors.primaryPurple,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: widget.onClose,
        ),
        actions: [
          IconButton(
            icon: Icon(
              _showHelpView ? Icons.refresh : Icons.help_outline,
              color: Colors.white,
            ),
            tooltip: _showHelpView ? 'Voltar' : 'Ajuda',
            onPressed: () => setState(() => _showHelpView = !_showHelpView),
          ),
        ],
      ),
      body: _isLoading
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
              child: _showHelpView ? _buildHelpContent() : _buildMainContent(),
            ),
    );
  }

  Widget _buildMainContent() {
    final isMobile = MediaQuery.of(context).size.width < 600;

    return Padding(
      padding: EdgeInsets.all(isMobile ? 16 : 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildStatusSection(),
          const SizedBox(height: 12),
          _buildInfoSection(),
          const SizedBox(height: 12),
          _buildDisclaimerCard(),
          const Spacer(),
          if (_isConnected) _buildDisconnectButton() else _buildConnectButton(),
          // Add extra padding for Android Nav Bar
          SizedBox(height: MediaQuery.of(context).viewPadding.bottom + 32),
        ],
      ),
    );
  }

  Widget _buildStatusSection() {
    if (_isConnected) {
      final color = Colors.blue;
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.5), width: 1.5),
        ),
        child: Column(
          children: [
            Row(
              children: [
                Icon(Icons.check_circle, color: color, size: 24),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Mercado Pago Ativo",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: color.withValues(alpha: 0.9),
                          fontSize: 16,
                        ),
                      ),
                      Text(
                        "Conta conectada.",
                        style: TextStyle(color: Colors.grey[800], fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (_connectedAt != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  children: [
                    Icon(Icons.access_time,
                        size: 12, color: color.withValues(alpha: 0.8)),
                    const SizedBox(width: 4),
                    Text(
                      "Desde $_connectedAt",
                      style: TextStyle(
                          fontSize: 12, color: color.withValues(alpha: 0.8)),
                    ),
                  ],
                ),
              ),
          ],
        ),
      );
    } else {
      return _buildInfoCard(
        icon: Icons.account_balance_wallet,
        color: Colors.grey,
        title: "Não Conectado",
        text: "Conecte sua conta para receber pagamentos.",
        isStatus: true,
      );
    }
  }

  Widget _buildInfoSection() {
    return Column(
      children: [
        _buildInfoCard(
          icon: Icons.pix,
          color: Colors.teal,
          title: "Chave PIX Necessária",
          text:
              "Verifique no seu app do Mercado Pago se você possui uma Chave PIX cadastrada para receber.",
        ),
        const SizedBox(height: 8), // Reduced spacing
        _buildInfoCard(
          icon: Icons.percent,
          color: Colors.orange,
          title: "Taxas e Prazos",
          text:
              "Consulte suas taxas e prazos de recebimento diretamente na sua conta do Mercado Pago.",
        ),
      ],
    );
  }

  Widget _buildDisclaimerCard() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, color: Colors.grey[600], size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              "A MarkaAI não é um banco e não tem controle, acesso ou responsabilidade sobre taxas, prazos e aprovações do Mercado Pago. Somos apenas uma integração facilitadora.",
              style: TextStyle(
                color: Colors.grey[700],
                fontSize: 12,
                height: 1.3,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard({
    required IconData icon,
    required Color color,
    required String title,
    required String text,
    bool isStatus = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isStatus
            ? color.withValues(alpha: 0.1)
            : color.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: isStatus
                ? color.withValues(alpha: 0.5)
                : color.withValues(alpha: 0.2),
            width: isStatus ? 1.5 : 1),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: color.withValues(alpha: 0.9),
                    fontSize: 14,
                  ),
                ),
                Text(
                  text,
                  style: TextStyle(
                    color: Colors.grey[800],
                    fontSize: 12,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDisconnectButton() {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: ElevatedButton.icon(
        onPressed: (!_canEdit || _isConnecting) ? null : _disconnectMercadoPago,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF009EE3),
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        icon: _isConnecting
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                    color: Colors.white, strokeWidth: 2.5),
              )
            : const Icon(Icons.link_off, size: 20),
        label: Text(
          _isConnecting ? "DESCONECTANDO..." : "DESCONECTAR CONTA",
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  // Botões extraídos para ficarem no final
  Widget _buildConnectButton() {
    return FutureBuilder<bool>(
      future: SubscriptionService.canUseOnlinePayment(),
      builder: (context, snapshot) {
        final canUseOnline = snapshot.data ?? false;

        if (!canUseOnline) {
          return SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _showUpgradeDialog,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                "FAZER UPGRADE PARA CONECTAR",
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          );
        }

        return SizedBox(
          width: double.infinity,
          height: 56,
          child: ElevatedButton.icon(
            onPressed:
                (!_canEdit || _isConnecting) ? null : _connectWithMercadoPago,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF009EE3),
              foregroundColor: Colors.white,
              disabledBackgroundColor: Colors.grey[300],
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              elevation: 0,
            ),
            icon: _isConnecting
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2.5,
                    ),
                  )
                : const Icon(Icons.link, size: 24),
            label: Text(
              _isConnecting ? 'CONECTANDO...' : 'CONECTAR MERCADO PAGO',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        );
      },
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

  void _showUpgradeDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Recurso Exclusivo ?"),
        content: const Text(
            "Receber pagamentos online via PIX e Cartão é exclusivo dos planos pagos.\n\nAssine agora para liberar!"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Depois"),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              // Navegar para tela de planos
              await Navigator.pushNamed(context, '/subscription_plans');
              if (mounted) setState(() {});
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryPurple,
                foregroundColor: Colors.white),
            child: const Text("Ver Planos"),
          ),
        ],
      ),
    );
  }
}
