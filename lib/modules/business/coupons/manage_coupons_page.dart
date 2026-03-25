import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/services/coupon_share_service.dart';
import '../../../core/services/plan_features_service.dart';
import '../../../core/constants/plan_features.dart';
import '../../../widgets/upgrade_modal.dart';
import '../../../core/services/shop_data_cache_service.dart';

class CouponTicketClipper extends CustomClipper<Path> {
  const CouponTicketClipper();

  @override
  Path getClip(Size size) {
    final Path path = Path();
    const double cutoutRadius = 12.0;
    const double leftSectionWidth = 100.0;

    path.lineTo(leftSectionWidth - cutoutRadius, 0);
    path.arcToPoint(
      const Offset(leftSectionWidth + cutoutRadius, 0),
      radius: const Radius.circular(cutoutRadius),
      clockwise: false,
    );
    path.lineTo(size.width - 16, 0);
    path.quadraticBezierTo(size.width, 0, size.width, 16);
    path.lineTo(size.width, size.height - 16);
    path.quadraticBezierTo(size.width, size.height, size.width - 16, size.height);
    path.lineTo(leftSectionWidth + cutoutRadius, size.height);
    path.arcToPoint(
      Offset(leftSectionWidth - cutoutRadius, size.height),
      radius: const Radius.circular(cutoutRadius),
      clockwise: false,
    );
    path.lineTo(16, size.height);
    path.quadraticBezierTo(0, size.height, 0, size.height - 16);
    path.lineTo(0, 16);
    path.quadraticBezierTo(0, 0, 16, 0);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(CustomClipper<Path> oldClipper) => false;
}

class ManageCouponsPage extends StatefulWidget {
  final String shopId;

  const ManageCouponsPage({super.key, required this.shopId});

  @override
  State<ManageCouponsPage> createState() => _ManageCouponsPageState();
}

class _ManageCouponsPageState extends State<ManageCouponsPage> {
  final GlobalKey _shareKey = GlobalKey();
  String _shopName = "Minha Loja";
  String? _logoUrl;
  String? _slug;
  bool _isGeneratingImage = false;
  late PlanFeatures _currentFeatures = planFeaturesConfig[PlanKey.free]!;
  List<Map<String, dynamic>> _services = [];

  Map<String, dynamic>? _couponToShare;

  @override
  void initState() {
    super.initState();
    _loadShopData();
    _loadServices();
  }

  Future<void> _loadServices() async {
    final data = await Supabase.instance.client
        .from('services')
        .select('id, name')
        .eq('shop_id', widget.shopId)
        .eq('is_active', true)
        .order('name');
    
    if (mounted) {
      setState(() {
        _services = List<Map<String, dynamic>>.from(data);
      });
    }
  }

  String _resolveServiceNames(List<String> serviceIds) {
    final names = serviceIds.map((id) {
      final match = _services.where((s) => s['id'].toString() == id);
      return match.isNotEmpty ? match.first['name'] ?? '' : '';
    }).where((n) => n.isNotEmpty).toList();
    if (names.isEmpty) return 'Serviços específicos';
    return names.join(', ');
  }

  Future<void> _loadShopData() async {
    final data = await Supabase.instance.client
        .from('shops')
        .select()
        .eq('id', widget.shopId)
        .maybeSingle();

    if (data != null) {
      if (mounted) {
        setState(() {
          _shopName = data['name'] ?? "Minha Loja"; // Corrigido de 'nome'
          final String? logo = data['logo_url']; // Corrigido de 'logoUrl'
          final String? image = data['image_url']; // Corrigido de 'foto'
          _logoUrl = (logo != null && logo.isNotEmpty) ? logo : image;
          _slug = data['slug'];
        });
      }
    }
  }

  Future<void> _shareCoupon(Map<String, dynamic> couponData) async {
    setState(() {
      _couponToShare = couponData;
      _isGeneratingImage = true;
    });

    if (_logoUrl != null && _logoUrl!.isNotEmpty && mounted) {
      precacheImage(CachedNetworkImageProvider(_logoUrl!), context);
    }

    await Future.delayed(const Duration(milliseconds: 500));

    if (mounted) {
      await CouponShareService.shareCoupon(
        context: context,
        key: _shareKey,
        code: couponData['code'] ?? 'CUPOM',
      );
    }

    if (mounted) {
      setState(() {
        _isGeneratingImage = false;
        _couponToShare = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<PlanFeatures>(
      stream: PlanFeaturesService.streamFeaturesByShopId(widget.shopId),
      builder: (context, planSnapshot) {
        if (planSnapshot.hasData) {
          _currentFeatures = planSnapshot.data!;
        }

        return Scaffold(
          backgroundColor: const Color(0xFFF5F7FA),
          appBar: AppBar(
            title: const Text('Meus Cupons'),
            backgroundColor: AppColors.primaryPurple,
            foregroundColor: Colors.white,
          ),
          body: Stack(
            children: [
              StreamBuilder<List<Map<String, dynamic>>>(
                stream: Supabase.instance.client
                    .from('coupons')
                    .stream(primaryKey: ['id'])
                    .eq('shop_id', widget.shopId),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
                    return const Center(
                      child: Padding(
                        padding: EdgeInsets.all(32.0),
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    );
                  }

                  if (snapshot.hasError) {
                    debugPrint('Erro no stream de cupons: ${snapshot.error}');
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24.0),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.error_outline, color: Colors.orange, size: 48),
                            const SizedBox(height: 16),
                            Text('Erro ao carregar cupons: ${snapshot.error}',
                                textAlign: TextAlign.center,
                                style: const TextStyle(color: Colors.grey)),
                            const SizedBox(height: 16),
                            ElevatedButton(
                              onPressed: () => setState(() {}),
                              child: const Text('TENTAR NOVAMENTE'),
                            )
                          ],
                        ),
                      ),
                    );
                  }

                  final coupons = List<Map<String, dynamic>>.from(snapshot.data ?? []);
                  
                  coupons.sort((a, b) {
                    final aTime = DateTime.tryParse(a['created_at']?.toString() ?? '') ?? DateTime(2000);
                    final bTime = DateTime.tryParse(b['created_at']?.toString() ?? '') ?? DateTime(2000);
                    return bTime.compareTo(aTime);
                  });

                  if (coupons.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.confirmation_number_outlined,
                               size: 80, color: Colors.grey[300]),
                          const SizedBox(height: 16),
                          const Text('Nenhum cupom criado ainda.',
                               style: TextStyle(color: Colors.grey)),
                          const SizedBox(height: 24),
                          ElevatedButton.icon(
                            onPressed: () {
                              if (!_currentFeatures.coupons) {
                                _showUpgradeDialog();
                                return;
                              }
                              _showCouponDialog();
                            },
                            icon: const Icon(Icons.add),
                            label: const Text('CRIAR MEU PRIMEIRO CUPOM'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primaryPurple,
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    );
                  }

                  return ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: coupons.length,
                    itemBuilder: (context, index) {
                      final data = coupons[index];
                      return _buildCouponCard(data['id'], data);
                    },
                  );
                },
              ),

              if (_couponToShare != null)
                Positioned(
                  left: -1000,
                  child: RepaintBoundary(
                    key: _shareKey,
                    child: CouponShareService.buildShareableCoupon(
                      shopName: _shopName,
                      code: _couponToShare!['code'] ?? '',
                      discount: (_couponToShare!['discount_percent'] as num?)?.toInt() ?? 0, // Corrigido cast para int
                      logoUrl: _logoUrl,
                      description: _couponToShare!['description'],
                      subdomain: _slug,
                      validUntil: _couponToShare!['valid_until'] != null
                          ? DateFormat('dd/MM/yyyy').format(
                              DateTime.parse(_couponToShare!['valid_until'].toString()))
                          : null,
                    ),
                  ),
                ),

              if (_isGeneratingImage)
                Container(
                  color: Colors.black26,
                  child: const Center(
                    child: Card(
                      child: Padding(
                        padding:
                            EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircularProgressIndicator(strokeWidth: 2),
                            SizedBox(width: 16),
                            Text("Gerando imagem..."),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          floatingActionButton: FloatingActionButton(
            onPressed: () {
              if (!_currentFeatures.coupons) {
                _showUpgradeDialog();
                return;
              }
              _showCouponDialog();
            },
            backgroundColor: AppColors.primaryPurple,
            child: const Icon(Icons.add, color: Colors.white),
          ),
        );
      },
    );
  }

  Widget _buildCouponCard(String id, Map<String, dynamic> data) {
    final bool isActive = data['is_active'] ?? true;
    final DateTime? validUntil =
        data['valid_until'] != null ? DateTime.parse(data['valid_until'].toString()) : null;
    final bool isExpired = validUntil != null && validUntil.isBefore(DateTime.now());
    final bool isCouponEnabled = isActive && !isExpired;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipPath(
        clipper: const CouponTicketClipper(),
        child: Container(
          height: 150, // Aumentado para acomodar logo e nome
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              Container(
                width: 100,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: isCouponEnabled
                        ? [AppColors.primaryPurple, AppColors.primaryPurple.withValues(alpha: 0.8)]
                        : [Colors.grey[400]!, Colors.grey[500]!],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '${data['discount_percent']}%',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Text(
                      'OFF',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ],
                ),
              ),

              Container(
                width: 1,
                color: Colors.grey[200],
                margin: const EdgeInsets.symmetric(vertical: 20),
              ),

              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Logo e Nome da Loja
                      Row(
                        children: [
                          if (_logoUrl != null && _logoUrl!.isNotEmpty)
                            CircleAvatar(
                              radius: 10,
                              backgroundColor: Colors.grey[100],
                              backgroundImage: CachedNetworkImageProvider(_logoUrl!),
                            )
                          else
                            const Icon(Icons.store, size: 14, color: Colors.grey),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _shopName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Colors.grey[600],
                              ),
                            ),
                          ),
                          _buildStatusBadge(isActive, isExpired),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        data['code'] ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                          color: isCouponEnabled ? Colors.black87 : Colors.grey,
                          letterSpacing: 1.1,
                        ),
                      ),
                      if (data['description'] != null && data['description'].toString().isNotEmpty)
                        Text(
                          data['description'] ?? '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                        ),
                      if (data['service_ids'] != null && (data['service_ids'] as List).isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Row(
                            children: [
                              Icon(Icons.sell_outlined, size: 12, color: Colors.orange[400]),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  _resolveServiceNames(List<String>.from(data['service_ids'])),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontSize: 10, color: Colors.orange[700], fontWeight: FontWeight.w500),
                                ),
                              ),
                            ],
                          ),
                        ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Icon(Icons.history, size: 14, color: Colors.grey[400]),
                          const SizedBox(width: 4),
                          Builder(builder: (context) {
                            final int usageCount = data['usage_count'] ?? 0;
                            final int maxUsages = int.tryParse(data['max_usage']?.toString() ?? '0') ?? 0;
                            return Text(
                              'Usos: $usageCount${maxUsages > 0 ? " / $maxUsages" : ""}',
                              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                            );
                          }),
                          const Spacer(),
                          if (validUntil != null) ...[
                            Icon(Icons.event_available,
                                size: 14, color: isExpired ? Colors.red[300] : Colors.grey[400]),
                            const SizedBox(width: 4),
                            Text(
                              DateFormat('dd/MM/yy').format(validUntil),
                              style: TextStyle(
                                fontSize: 12,
                                color: isExpired ? Colors.red[300] : Colors.grey[600],
                                fontWeight: isExpired ? FontWeight.bold : FontWeight.normal,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              Container(
                decoration: BoxDecoration(
                  color: Colors.grey[50],
                  border: Border(left: BorderSide(color: Colors.grey[100]!)),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.share_outlined, size: 22),
                      color: Colors.blue[400],
                      tooltip: 'Compartilhar',
                      onPressed: () => _shareCoupon(data),
                    ),
                    IconButton(
                      icon: const Icon(Icons.edit_outlined, size: 22),
                      color: Colors.grey[600],
                      onPressed: () => _showCouponDialog(id: id, initialData: data),
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

  Widget _buildStatusBadge(bool isActive, bool isExpired) {
    String text = "Ativo";
    Color color = Colors.green;
    if (!isActive) {
      text = "Inativo";
      color = Colors.grey;
    } else if (isExpired) {
      text = "Expirado";
      color = Colors.red;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Text(
        text,
        style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold),
      ),
    );
  }

  void _showCouponDialog({String? id, Map<String, dynamic>? initialData}) {
    final codeCtrl = TextEditingController(text: initialData?['code'] ?? '');
    final descCtrl =
        TextEditingController(text: initialData?['description'] ?? '');
    DateTime? selectedDate =
        initialData?['valid_until'] != null ? DateTime.parse(initialData!['valid_until'].toString()) : null;
    int? selectedMonth = initialData?['valid_month'];
    final limitCtrl = TextEditingController(
        text: initialData?['max_usage']?.toString() ?? '');
    double discountValue = (initialData?['discount_percent'] as num?)?.toDouble() ?? 10.0;
    bool isActive = initialData?['is_active'] ?? true;
    List<String> selectedServiceIds = initialData?['service_ids'] != null 
        ? List<String>.from(initialData!['service_ids']) 
        : [];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
          builder: (context, setDialogState) => SafeArea(
          bottom: false,
          child: Container(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom,
            ),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(28, 28, 28, 0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      id == null ? 'Criar Novo Cupom' : 'Editar Cupom',
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primaryPurple,
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    )
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Expanded(
                      child: Text(
                        "Configure os detalhes e a validade do seu cupom.",
                        style: TextStyle(color: Colors.grey, fontSize: 13),
                      ),
                    ),
                    Row(
                      children: [
                        Text(
                          isActive ? "Ativo" : "Inativo",
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: isActive ? Colors.green : Colors.red,
                          ),
                        ),
                        Switch(
                          value: isActive,
                          activeTrackColor: AppColors.primaryPurple.withValues(alpha: 0.5),
                          activeThumbColor: AppColors.primaryPurple,
                          onChanged: (val) =>
                              setDialogState(() => isActive = val),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 25),

                const Text(
                  "CÓDIGO DO CUPOM",
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: codeCtrl,
                  textCapitalization: TextCapitalization.characters,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                  decoration: InputDecoration(
                    hintText: 'EX: VERAO20',
                    filled: true,
                    fillColor: Colors.grey[50],
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey[200]!),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey[200]!),
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                const Text(
                  "SERVIÇOS APLICÁVEIS (Opcional)",
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey,
                  ),
                ),
                const SizedBox(height: 8),
                if (_services.isEmpty)
                  const Text("Nenhum serviço cadastrado.", style: TextStyle(fontSize: 12, color: Colors.grey))
                else
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: _services.map((service) {
                      final sId = service['id'].toString();
                      final isSelected = selectedServiceIds.contains(sId);
                      return FilterChip(
                        label: Text(service['name'] ?? ''),
                        selected: isSelected,
                        onSelected: (selected) {
                          setDialogState(() {
                            if (selected) {
                              selectedServiceIds.add(sId);
                            } else {
                              selectedServiceIds.remove(sId);
                            }
                          });
                        },
                        selectedColor: AppColors.primaryPurple.withValues(alpha: 0.2),
                        checkmarkColor: AppColors.primaryPurple,
                        labelStyle: TextStyle(
                          fontSize: 12,
                          color: isSelected ? AppColors.primaryPurple : Colors.black87,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        ),
                      );
                    }).toList(),
                  ),
                const SizedBox(height: 20),

                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      "PERCENTUAL DE DESCONTO (%)",
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.primaryPurple.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        "${discountValue.toInt()}%",
                        style: const TextStyle(
                          color: AppColors.primaryPurple,
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    activeTrackColor: AppColors.primaryPurple,
                    inactiveTrackColor: AppColors.primaryPurple.withValues(alpha: 0.1),
                    thumbColor: AppColors.primaryPurple,
                    overlayColor: AppColors.primaryPurple.withValues(alpha: 0.2),
                    valueIndicatorColor: AppColors.primaryPurple,
                    valueIndicatorTextStyle: const TextStyle(color: Colors.white),
                  ),
                  child: Slider(
                    value: discountValue,
                    min: 0,
                    max: 100,
                    divisions: 100,
                    label: "${discountValue.toInt()}%",
                    onChanged: (val) {
                      setDialogState(() {
                        discountValue = val;
                      });
                    },
                  ),
                ),
                const SizedBox(height: 20),

                const Text(
                  "LIMITE POR QUANTIDADE (USOS)",
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: limitCtrl,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    hintText: 'Ex: 10 (Vazio = ilimitado)',
                    filled: true,
                    fillColor: Colors.grey[50],
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey[200]!),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey[200]!),
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                const Text(
                  "DESCRIÇÃO DO CUPOM",
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: descCtrl,
                  decoration: InputDecoration(
                    hintText: 'Ex: Desconto para novos clientes',
                    filled: true,
                    fillColor: Colors.grey[50],
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey[200]!),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey[200]!),
                    ),
                  ),
                  maxLines: 2,
                ),

                const SizedBox(height: 20),

                const Text(
                  "VALIDADE",
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey,
                  ),
                ),
                const SizedBox(height: 8),
                InkWell(
                  onTap: () async {
                    final date = await showDatePicker(
                      context: context,
                      initialDate: selectedDate ??
                          DateTime.now().add(const Duration(days: 30)),
                      firstDate: DateTime.now(),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                      builder: (context, child) {
                        return Theme(
                          data: Theme.of(context).copyWith(
                            colorScheme: const ColorScheme.light(
                              primary: AppColors.primaryPurple,
                            ),
                          ),
                          child: child!,
                        );
                      },
                    );
                    if (date != null) {
                      setDialogState(() => selectedDate = date);
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.grey[50],
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey[200]!),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          selectedDate == null
                              ? 'Sem validade (Sempre ativo)'
                              : DateFormat('dd/MM/yyyy').format(selectedDate!),
                          style: TextStyle(
                            fontSize: 16,
                            color: selectedDate == null
                                ? Colors.grey[600]
                                : Colors.black,
                            fontWeight: selectedDate == null
                                ? FontWeight.normal
                                : FontWeight.bold,
                          ),
                        ),
                        const Icon(Icons.calendar_today,
                            size: 20, color: AppColors.primaryPurple),
                      ],
                    ),
                  ),
                ),
                if (selectedDate != null)
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () =>
                          setDialogState(() => selectedDate = null),
                      child: const Text('Remover validade',
                          style: TextStyle(color: Colors.red, fontSize: 12)),
                    ),
                  ),

                const SizedBox(height: 20),

                const Text(
                  "VALIDADE POR MÊS (OPCIONAL)",
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.grey[50],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey[200]!),
                  ),
                  child: DropdownButton<int?>(
                    value: selectedMonth,
                    isExpanded: true,
                    underline: Container(),
                    hint: const Text('Válido em qualquer mês'),
                    items: [
                      const DropdownMenuItem(
                          value: null, child: Text('Qualquer mês')),
                      ...List.generate(12, (i) => i + 1).map((m) {
                        return DropdownMenuItem(
                            value: m,
                            child: Text(DateFormat('MMMM', 'pt_BR')
                                .format(DateTime(2022, m))));
                      }),
                    ],
                    onChanged: (val) => setDialogState(() => selectedMonth = val),
                  ),
                ),

                const SizedBox(height: 30),
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: () async {
                      if (codeCtrl.text.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('O código do cupom é obrigatório')),
                        );
                        return;
                      }

                      try {
                        debugPrint('Tentando salvar cupom - shopId: ${widget.shopId}, id: $id');
                        final data = {
                          'code': codeCtrl.text.trim().toUpperCase(),
                          'description': descCtrl.text.trim(),
                          'discount_percent': discountValue,
                          'is_active': isActive,
                          'valid_until': selectedDate != null
                              ? selectedDate!.toIso8601String()
                              : null,
                          'valid_month': selectedMonth,
                          'max_usage': int.tryParse(limitCtrl.text) ?? 0,
                          'updated_at': DateTime.now().toIso8601String(),
                          'service_ids': selectedServiceIds.isEmpty ? null : selectedServiceIds,
                        };
                        debugPrint('Dados do cupom: $data');
 
                        if (id == null) {
                          data['shop_id'] = widget.shopId;
                          data['created_at'] = DateTime.now().toIso8601String();
                          data['usage_count'] = 0;
                          
                          final response = await Supabase.instance.client
                              .from('coupons')
                              .insert(data)
                              .select();
                          
                          if (response.isNotEmpty) {
                            debugPrint('Cupom criado com ID: ${response.first["id"]}');
                          } else {
                            debugPrint('Cupom inserido (sem retorno - verifique RLS)');
                          }
                        } else {
                          await Supabase.instance.client
                              .from('coupons')
                              .update(data)
                              .eq('id', id);
                          debugPrint('Cupom $id atualizado');
                        }

                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(id == null
                                  ? 'Cupom criado com sucesso!'
                                  : 'Alterações salvas com sucesso!'),
                              backgroundColor: Colors.green,
                              duration: const Duration(seconds: 2),
                            ),
                          );
                          ShopDataCacheService().invalidate(widget.shopId, 'coupons');
                          Future.delayed(const Duration(milliseconds: 300), () {
                            if (context.mounted) Navigator.pop(context);
                          });
                        }
                      } catch (e, stack) {
                        debugPrint('Erro ao salvar cupom: $e');
                        debugPrint('Stack: $stack');
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Erro ao salvar: $e'),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryPurple,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: Text(
                      id == null ? 'CRIAR CUPOM' : 'SALVAR ALTERAÇÕES',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                  ),
                ),
                if (id != null) ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        _confirmDelete(id);
                      },
                      icon: const Icon(Icons.delete_outline, color: Colors.red),
                      label: const Text(
                        'EXCLUIR CUPOM',
                        style: TextStyle(
                            color: Colors.red, fontWeight: FontWeight.bold),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(
                            color: Colors.red.withValues(alpha: 0.3)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                SizedBox(height: MediaQuery.of(context).padding.bottom + 20),
              ],
            ),
          ),
        ),
      ),
    ),
    );
  }

  void _confirmDelete(String id) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Excluir Cupom?'),
        content: const Text('Esta ação não pode ser desfeita.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CANCELAR'),
          ),
          ElevatedButton(
            onPressed: () async {
              await Supabase.instance.client
                  .from('coupons')
                  .delete()
                  .eq('id', id);
              ShopDataCacheService().invalidate(widget.shopId, 'coupons');
              if (context.mounted) Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text('EXCLUIR'),
          ),
        ],
      ),
    );
  }

  void _showUpgradeDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const UpgradeModal(
        featureName: "Gestão de Cupons",
        requiredPlan: "Plus",
      ),
    );
  }
}
