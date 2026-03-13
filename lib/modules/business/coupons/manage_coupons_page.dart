import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/services/coupon_share_service.dart';
import '../../../core/services/plan_features_service.dart';
import '../../../core/constants/plan_features.dart';
import '../../../widgets/upgrade_modal.dart';

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

  Map<String, dynamic>? _couponToShare;

  @override
  void initState() {
    super.initState();
    _loadShopData();
  }

  Future<void> _loadShopData() async {
    final doc = await FirebaseFirestore.instance
        .collection('shops')
        .doc(widget.shopId)
        .get();
    if (doc.exists) {
      setState(() {
        final data = doc.data();
        _shopName = data?['nome'] ?? "Minha Loja";
        final String? logo = data?['logoUrl'];
        final String? foto = data?['foto'];
        _logoUrl = (logo != null && logo.isNotEmpty) ? logo : foto;
        _slug = data?['slug'];
      });
    }
  }

  Future<void> _shareCoupon(Map<String, dynamic> couponData) async {
    setState(() {
      _couponToShare = couponData;
      _isGeneratingImage = true;
    });

    // Precache o logo para garantir que ele esteja pronto para a captura
    if (_logoUrl != null && _logoUrl!.isNotEmpty && mounted) {
      precacheImage(CachedNetworkImageProvider(_logoUrl!), context);
    }

    // Pequeno delay para o RepaintBoundary atualizar com os novos dados
    // Aumentado para 500ms para dar mais tempo ao motor de renderização
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
              StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('shops')
                    .doc(widget.shopId)
                    .collection('coupons')
                    .orderBy('createdAt', descending: true)
                    .snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (snapshot.hasError) {
                    return const Center(child: Text('Erro ao carregar cupons.'));
                  }

                  final coupons = snapshot.data?.docs ?? [];

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
                      final coupon = coupons[index];
                      final data = coupon.data() as Map<String, dynamic>;
                      return _buildCouponCard(coupon.id, data);
                    },
                  );
                },
              ),

              // Widget "Invisível" para captura de imagem
              if (_couponToShare != null)
                Positioned(
                  left: -1000, // Fora da tela
                  child: RepaintBoundary(
                    key: _shareKey,
                    child: CouponShareService.buildShareableCoupon(
                      shopName: _shopName,
                      code: _couponToShare!['code'] ?? '',
                      discount: _couponToShare!['discountPercent'] ?? 0,
                      logoUrl: _logoUrl,
                      description: _couponToShare!['descricao'],
                      subdomain: _slug,
                      validUntil: _couponToShare!['validUntil'] != null
                          ? DateFormat('dd/MM/yyyy').format(
                              (_couponToShare!['validUntil'] as Timestamp)
                                  .toDate())
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
    final bool isActive = data['isActive'] ?? true;
    final DateTime? validUntil = (data['validUntil'] as Timestamp?)?.toDate();
    final bool isExpired =
        validUntil != null && validUntil.isBefore(DateTime.now());

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey[200]!),
      ),
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          padding: _logoUrl != null ? EdgeInsets.zero : const EdgeInsets.all(10),
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: (isActive && !isExpired)
                ? AppColors.primaryPurple.withValues(alpha: 0.1)
                : Colors.grey[100],
            shape: BoxShape.circle,
            image: _logoUrl != null
                ? DecorationImage(
                    image: CachedNetworkImageProvider(_logoUrl!),
                    fit: BoxFit.cover,
                  )
                : null,
          ),
          child: _logoUrl == null
              ? Icon(
                  Icons.local_offer,
                  color: (isActive && !isExpired)
                      ? AppColors.primaryPurple
                      : Colors.grey,
                )
              : null,
        ),
        title: Row(
          children: [
            Text(
              data['code'] ?? '',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.green[50],
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '${data['discountPercent']}% OFF',
                style: TextStyle(
                    color: Colors.green[700],
                    fontSize: 12,
                    fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text('Usos: ${data['usageCount'] ?? 0}',
                style: const TextStyle(fontSize: 12)),
            if (validUntil != null)
              Text(
                'Válido até: ${DateFormat('dd/MM/yyyy').format(validUntil)}',
                style: TextStyle(
                  fontSize: 12,
                  color: isExpired ? Colors.red : Colors.grey[600],
                  fontWeight: isExpired ? FontWeight.bold : FontWeight.normal,
                ),
              ),
          ],
        ),
        onTap: () => _showCouponDialog(id: id, initialData: data),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.share_outlined,
                  color: AppColors.primaryPurple),
              onPressed: () => _shareCoupon(data),
            ),
          ],
        ),
      ),
    );
  }

  void _showCouponDialog({String? id, Map<String, dynamic>? initialData}) {
    final codeCtrl = TextEditingController(text: initialData?['code'] ?? '');
    final descCtrl =
        TextEditingController(text: initialData?['descricao'] ?? '');
    DateTime? selectedDate =
        (initialData?['validUntil'] as Timestamp?)?.toDate();
    int? selectedMonth = initialData?['validMonth'];
    double discountValue = (initialData?['discountPercent'] as num?)?.toDouble() ?? 10.0;
    bool isActive = initialData?['isActive'] ?? true;

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

                // CÓDIGO DO CUPOM
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
                  textCapitalization: TextCapitalization.characters,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 18),
                ),

                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      "CENTUAL DE DESCONTO (%)",
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

                // DESCRIÇÃO
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

                // VALIDADE
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

                // VALIDADE POR MÊS
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
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.grey[50],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey[200]!),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<int>(
                      value: selectedMonth,
                      hint: const Text("Selecione um mês (opcional)",
                          style: TextStyle(fontSize: 15)),
                      isExpanded: true,
                      items: [
                        const DropdownMenuItem<int>(
                          value: null,
                          child: Text("Qualquer mês"),
                        ),
                        ...List.generate(12, (index) {
                          final monthNum = index + 1;
                          final monthName = DateFormat('MMMM', 'pt_BR')
                              .format(DateTime(2024, monthNum));
                          return DropdownMenuItem<int>(
                            value: monthNum,
                            child: Text(monthName[0].toUpperCase() +
                                monthName.substring(1)),
                          );
                        }),
                      ],
                      onChanged: (val) =>
                          setDialogState(() => selectedMonth = val),
                    ),
                  ),
                ),
                const SizedBox(height: 30),
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: () async {
                      if (codeCtrl.text.isEmpty) {
                        return;
                      }

                      final data = {
                        'code': codeCtrl.text.trim().toUpperCase(),
                        'descricao': descCtrl.text.trim(),
                        'discountPercent': discountValue.toInt(),
                        'isActive': isActive,
                        'validUntil': selectedDate != null
                            ? Timestamp.fromDate(selectedDate!)
                            : null,
                        'validMonth': selectedMonth,
                        'updatedAt': FieldValue.serverTimestamp(),
                      };

                      if (id == null) {
                        data['createdAt'] = FieldValue.serverTimestamp();
                        data['usageCount'] = 0;
                        await FirebaseFirestore.instance
                            .collection('shops')
                            .doc(widget.shopId)
                            .collection('coupons')
                            .add(data);
                      } else {
                        await FirebaseFirestore.instance
                            .collection('shops')
                            .doc(widget.shopId)
                            .collection('coupons')
                            .doc(id)
                            .update(data);
                      }

                      if (context.mounted) Navigator.pop(context);
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
                // Padding extra para garantir que não fique atrás da barra do Android
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
              await FirebaseFirestore.instance
                  .collection('shops')
                  .doc(widget.shopId)
                  .collection('coupons')
                  .doc(id)
                  .delete();
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
