import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/theme/app_colors.dart';
import '../schedule/booking_page.dart';
import '../login/login_page.dart';
import '../../core/services/profile_check_service.dart';
import 'client_register_page.dart';
import 'package:url_launcher/url_launcher.dart';

class ClientServiceDetailPage extends StatefulWidget {
  final Map<String, dynamic> serviceDoc;
  final bool isReschedule;
  final String? rescheduleAppointmentId;
  final bool fromSubdomain;

  const ClientServiceDetailPage({
    super.key,
    required this.serviceDoc,
    this.isReschedule = false,
    this.rescheduleAppointmentId,
    this.fromSubdomain = false,
  });

  Map<String, dynamic> get serviceData => serviceDoc;
  String get serviceId => serviceDoc['id'] ?? '';

  @override
  State<ClientServiceDetailPage> createState() =>
      _ClientServiceDetailPageState();
}

class _ClientServiceDetailPageState extends State<ClientServiceDetailPage> {
  int _currentImageIndex = 0;
  late final PageController _pageController;
  Map<String, dynamic>? _selectedVariation;
  bool _isNavigating = false;

  Map<String, dynamic>? _shopDoc;
  bool _isLoadingShop = true;
  bool _isOnlineBookingActive = true;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: _currentImageIndex);
    _loadShopConfig();
  }

  Future<void> _loadShopConfig() async {
    try {
      final shopId = widget.serviceData['shopId'] ?? widget.serviceData['shop_id'];
      if (shopId != null) {
        final doc = await Supabase.instance.client
            .from('shops')
            .select()
            .eq('id', shopId)
            .maybeSingle();
            
        if (doc != null) {
          _shopDoc = doc;
          final config = doc['config'] as Map<String, dynamic>?;
          _isOnlineBookingActive = config?['agendamento_online_ativo'] ?? true;
        }
      }
    } catch (e) {
      debugPrint("Erro ao carregar loja: $e");
    } finally {
      if (mounted) setState(() => _isLoadingShop = false);
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _goToBooking() async {
    if (!_isOnlineBookingActive && _shopDoc != null) {
      _agendarViaWhatsApp();
      return;
    }

    setState(() => _isNavigating = true);

    Map<String, dynamic>? shopDoc = _shopDoc;
    try {
      if (shopDoc == null) {
        final shopId = widget.serviceData['shopId'] ?? widget.serviceData['shop_id'];
        if (shopId != null) {
          shopDoc = await Supabase.instance.client
              .from('shops')
              .select()
              .eq('id', shopId)
              .maybeSingle();
              
          if (shopDoc == null) throw "Loja não encontrada.";
          _shopDoc = shopDoc;
        } else {
          throw "ID da loja não encontrado.";
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isNavigating = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Erro: $e"), backgroundColor: Colors.red),
        );
      }
      return;
    }

    // 1. Verificar se o usuário está logado
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      if (mounted) setState(() => _isNavigating = false);

      final serviceName = widget.serviceData['name'] ?? 'o serviço';
      final shopName = shopDoc['name'] ?? 'nossa loja';

      if (mounted) {
        final success = await Navigator.push<bool>(
          context,
          MaterialPageRoute(
            builder: (context) => LoginPage(
              returnOnSuccess: true,
              contextMessage:
                  "Para agendar $serviceName na $shopName, faça login ou crie sua conta.",
            ),
          ),
        );

        if (success == true && mounted) {
          _goToBooking();
        }
      }
      return;
    }

    // 1.5 Verificar se o perfil está completo
    final complete =
        await ProfileCheckService.isClientProfileComplete(user.id);
    if (!complete && mounted) {
      final go = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Perfil incompleto'),
          content: const Text(
            'Seu perfil ainda não foi todo preenchido. Para agendar, complete seus dados (nome, endereço). Deseja completar agora?',
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Depois')),
            ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Completar')),
          ],
        ),
      );
      if (go == true && mounted) {
        final regOk = await Navigator.push<bool>(
          context,
          MaterialPageRoute(
            builder: (context) => ClientRegisterPage(
              user: user,
              isBusinessAdding: false,
              returnOnSuccess: true,
            ),
          ),
        );
        if (regOk == true && mounted) {
          _goToBooking();
        }
      }
      return;
    }

    // 2. Validação de variação
    final variations = widget.serviceData['variations'] as List?;
    if (variations != null &&
        variations.isNotEmpty &&
        _selectedVariation == null) {
      if (!mounted) {
        setState(() => _isNavigating = false);
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text("Por favor, escolha uma opção (Variação) acima."),
            backgroundColor: Colors.orange),
      );
      setState(() => _isNavigating = false);
      return;
    }

    try {
      if (!mounted) return;

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => BookingPage(
            shop: shopDoc!,
            serviceDoc: widget.serviceDoc,
            selectedVariation: _selectedVariation,
            isReschedule: widget.isReschedule,
            appointmentId: widget.rescheduleAppointmentId,
            fromSubdomain: widget.fromSubdomain,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Erro: $e"), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _isNavigating = false);
    }
  }

  void _agendarViaWhatsApp() async {
    if (_shopDoc == null) return;
    final shopData = _shopDoc!;
    final phone = shopData['telefone'] ?? shopData['whatsapp'];
    if (phone == null || phone.toString().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text("Loja não possui número de WhatsApp cadastrado.")),
      );
      return;
    }

    String cleanPhone = phone.toString().replaceAll(RegExp(r'\D'), '');
    if (!cleanPhone.startsWith('55')) {
      cleanPhone = '55$cleanPhone';
    }

    final String serviceName = widget.serviceData['nome'] ?? 'Serviço';
    final String shopName = shopData['nome'] ?? 'loja';
    final String message =
        "Olá, vim pelo App MarkaAI e gostaria de agendar o serviço $serviceName na $shopName.";

    final Uri url = Uri.parse(
        "https://wa.me/$cleanPhone?text=${Uri.encodeComponent(message)}");

    try {
      if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
        throw 'Cannot launch url';
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text("Erro ao abrir o WhatsApp. Tente novamente.")),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final List photos = widget.serviceData['fotos_urls'] ?? [];
    final bool hasPhotos = photos.isNotEmpty;
    final variations = widget.serviceData['variations'] as List?;
    final bool hasVariations = variations != null && variations.isNotEmpty;

    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          CustomScrollView(
            slivers: [
              SliverAppBar(
                expandedHeight: 400,
                pinned: true,
                backgroundColor: AppColors.primaryPurple,
                foregroundColor: Colors.white,
                leading: IconButton(
                  icon: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.3),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.arrow_back,
                        color: Colors.white, size: 20),
                  ),
                  onPressed: () => Navigator.pop(context),
                ),
                flexibleSpace: FlexibleSpaceBar(
                  background: Stack(
                    fit: StackFit.expand,
                    children: [
                      hasPhotos
                          ? PageView.builder(
                              controller: _pageController,
                              onPageChanged: (index) {
                                setState(() => _currentImageIndex = index);
                              },
                              itemCount: photos.length,
                              itemBuilder: (context, index) {
                                final img = photos[index];
                                return CachedNetworkImage(
                                  imageUrl: img,
                                  fit: BoxFit.cover,
                                  placeholder: (context, url) => Container(
                                    color: Colors.grey[200],
                                    child: const Center(
                                      child: CircularProgressIndicator(
                                        color: AppColors.primaryPurple,
                                      ),
                                    ),
                                  ),
                                  errorWidget: (context, url, error) =>
                                      Container(
                                    color: Colors.grey[300],
                                    child: const Icon(Icons.broken_image,
                                        size: 80),
                                  ),
                                );
                              },
                            )
                          : Container(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    AppColors.primaryPurple,
                                    AppColors.primaryPurple
                                        .withValues(alpha: 0.7),
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                              ),
                              child: const Icon(
                                Icons.spa,
                                size: 120,
                                color: Colors.white,
                              ),
                            ),

                      if (hasPhotos && photos.length > 1)
                        Positioned(
                          bottom: 16,
                          left: 0,
                          right: 0,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: List.generate(
                              photos.length,
                              (index) => Container(
                                margin:
                                    const EdgeInsets.symmetric(horizontal: 4),
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: _currentImageIndex == index
                                      ? Colors.white
                                      : Colors.white.withValues(alpha: 0.4),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),

              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 0),
                        child: Text(
                          widget.serviceData['name'] ?? '',
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Colors.black,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),

                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            child: Container(
                              height: 60,
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: AppColors.primaryPurple
                                    .withOpacity(0.05),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: AppColors.primaryPurple
                                      .withOpacity(0.1),
                                ),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(Icons.payments_outlined,
                                      color: AppColors.primaryPurple, size: 20),
                                  const SizedBox(width: 8),
                                  Text(
                                    "R\$ ${widget.serviceData['price'] ?? '0'}",
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.primaryPurple,
                                      fontSize: 16,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Container(
                              height: 60,
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.grey[50],
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.grey.shade200),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(Icons.timer_outlined,
                                      color: Colors.grey, size: 20),
                                  const SizedBox(width: 8),
                                  Text(
                                    "${widget.serviceData['duration_min'] ?? '30'} min",
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.black87,
                                      fontSize: 16,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),

                      if (widget.serviceData['description'] != null &&
                          widget.serviceData['description']
                              .toString()
                              .isNotEmpty) ...[
                        const SizedBox(height: 24),
                        const Text(
                          "Descrição",
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          widget.serviceData['description'],
                          style: TextStyle(
                            fontSize: 15,
                            color: Colors.grey[700],
                            height: 1.5,
                          ),
                        ),
                      ],

                      if (hasVariations) ...[
                        const SizedBox(height: 24),
                        const Text(
                          "Escolha uma opção",
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: variations.map<Widget>((v) {
                            final isSelected = _selectedVariation == v;
                            return ChoiceChip(
                              label: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    "${v['name']}",
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      color: isSelected
                                          ? Colors.white
                                          : Colors.black87,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    "R\$ ${v['price']}",
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: isSelected
                                          ? Colors.white
                                          : Colors.green[700],
                                    ),
                                  ),
                                ],
                              ),
                              selected: isSelected,
                              selectedColor: AppColors.primaryPurple,
                              backgroundColor: Colors.white,
                              side: BorderSide(
                                color: isSelected
                                    ? AppColors.primaryPurple
                                    : Colors.grey.shade300,
                                width: isSelected ? 2 : 1,
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                              onSelected: (val) => setState(() {
                                _selectedVariation = val ? v : null;
                              }),
                            );
                          }).toList(),
                        ),
                      ],

                      const SizedBox(height: 100),
                    ],
                  ),
                ),
              ),
            ],
          ),

          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 10,
                    offset: const Offset(0, -4),
                  ),
                ],
              ),
              child: SafeArea(
                child: SizedBox(
                  height: 56,
                  child: ElevatedButton(
                    onPressed:
                        _isLoadingShop || _isNavigating ? null : _goToBooking,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _isOnlineBookingActive
                          ? AppColors.primaryPurple
                          : Colors.green[600],
                      disabledBackgroundColor: Colors.grey[300],
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 0,
                    ),
                    child: _isLoadingShop || _isNavigating
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2.5,
                            ),
                          )
                        : Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              if (!_isOnlineBookingActive) ...[
                                const Icon(Icons.chat,
                                    color: Colors.white, size: 20),
                                const SizedBox(width: 8),
                              ],
                              Text(
                                _isOnlineBookingActive
                                    ? "AGENDAR ESSE SERVIÇO"
                                    : "AGENDAR PELO WHATSAPP",
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
