import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/services/session_service.dart';

class ProductsPage extends StatefulWidget {
  const ProductsPage({super.key});

  @override
  State<ProductsPage> createState() => _ProductsPageState();
}

class _ProductsPageState extends State<ProductsPage> {
  final CollectionReference productsRef =
      FirebaseFirestore.instance.collection('products');
  String? _shopId;

  // Standard fields that are always available/optional
  // Expanded list of fields
  final List<String> _standardFields = [
    'Código',
    'Nome',
    'Descrição',
    'Preço',
    'Custo',
    'Quantidade',
    'Categoria',
    'Marca',
    'Tamanho',
    'Cor',
    'Peso',
    'Fornecedor',
    'Localização',
    'Validade',
    'NCM',
    'EAN/GTIN',
    'Unidade (UN, KG, L)',
  ];

  // Active selected standard fields
  List<String> _selectedStandardFields = [
    'Código',
    'Nome',
    'Preço',
    'Quantidade'
  ];

  // Custom fields defined by the shop: [{'name': 'Tamanho', 'type': 'text'}]
  List<Map<String, dynamic>> _customFields = [];

  bool _showFieldConfig = false;

  @override
  void initState() {
    super.initState();
    _loadShopContext();
  }

  Future<void> _loadShopContext() async {
    try {
      final sid = await SessionService.getShopId();
      if (sid != null && sid.isNotEmpty) {
        _shopId = sid;
        final doc =
            await FirebaseFirestore.instance.collection('shops').doc(sid).get();
        if (doc.exists) {
          final data = doc.data();
          final cfg = data?['inventory_config'] as Map<String, dynamic>?;

          if (cfg != null) {
            if (cfg['product_fields'] != null) {
              _selectedStandardFields =
                  List<String>.from(cfg['product_fields']);
            }
            if (cfg['custom_fields'] != null) {
              _customFields =
                  List<Map<String, dynamic>>.from(cfg['custom_fields']);
            }
          }
        }
      }
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint("Error loading shop context: $e");
    }
  }

  Future<void> _saveConfig() async {
    if (_shopId == null) return;
    try {
      await FirebaseFirestore.instance.collection('shops').doc(_shopId).set({
        'inventory_config': {
          'product_fields': _selectedStandardFields,
          'custom_fields': _customFields,
        }
      }, SetOptions(merge: true));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Erro ao salvar config: $e')));
      }
    }
  }

  // Helper key generator
  String _fieldKey(String label) {
    // Check if it's a custom field
    final custom =
        _customFields.firstWhere((e) => e['name'] == label, orElse: () => {});
    if (custom.isNotEmpty) {
      return 'custom_${label.toLowerCase().replaceAll(' ', '_')}';
    }

    // Standard keys
    switch (label) {
      case 'Código':
        return 'codigo';
      case 'Nome':
        return 'name';
      case 'Descrição':
        return 'descricao';
      case 'Preço':
        return 'price';
      case 'Custo':
        return 'cost';
      case 'Quantidade':
        return 'qty';
      case 'Categoria':
        return 'categoria';
      case 'Marca':
        return 'marca';
      default:
        return label.toLowerCase().replaceAll(' ', '_');
    }
  }

  void _showProductEditor([DocumentSnapshot? doc]) {
    final map = (doc?.data() as Map<String, dynamic>?) ?? <String, dynamic>{};
    final controllers = <String, TextEditingController>{};

    // Initialize controllers for standard active fields
    for (final f in _selectedStandardFields) {
      final key = _fieldKey(f);
      controllers[f] = TextEditingController(text: map[key]?.toString() ?? '');
    }

    // Initialize controllers for custom fields
    for (final cf in _customFields) {
      final name = cf['name'] as String;
      final key = _fieldKey(name);
      controllers[name] =
          TextEditingController(text: map[key]?.toString() ?? '');
    }

    bool track = (map['track_stock'] ?? true) as bool;

    showModalBottomSheet(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (c, setStateLocal) {
          return Container(
            padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(
              children: [
                _buildSheetHeader(
                    doc == null ? 'Novo Produto' : 'Editar Produto',
                    () => Navigator.pop(ctx)),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Standard Fields
                        if (_selectedStandardFields.isNotEmpty) ...[
                          const Text('Informações Básicas',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.primaryPurple,
                                  fontSize: 14)),
                          const SizedBox(height: 16),
                          for (final f in _selectedStandardFields) ...[
                            _buildTextFieldInput(
                              label: f,
                              controller: controllers[f]!,
                              keyboardType: _getKeyboardType(f),
                            ),
                            const SizedBox(height: 16),
                          ],
                          const SizedBox(height: 8),
                        ],

                        // Custom Fields
                        if (_customFields.isNotEmpty) ...[
                          const Divider(),
                          const SizedBox(height: 16),
                          const Text('Informações Adicionais',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.primaryPurple,
                                  fontSize: 14)),
                          const SizedBox(height: 16),
                          for (final cf in _customFields) ...[
                            _buildTextFieldInput(
                              label: cf['name'],
                              controller: controllers[cf['name']]!,
                              keyboardType: cf['type'] == 'number'
                                  ? TextInputType.number
                                  : TextInputType.text,
                            ),
                            const SizedBox(height: 16),
                          ],
                        ],

                        // Stock Control Toggle
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.grey.shade50,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.grey.shade200),
                          ),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 8),
                          child: SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('Controlar Estoque',
                                style: TextStyle(fontWeight: FontWeight.w600)),
                            subtitle: const Text('Monitorar quantidade',
                                style: TextStyle(
                                    fontSize: 12, color: Colors.grey)),
                            value: track,
                            onChanged: (v) => setStateLocal(() => track = v),
                            activeThumbColor: AppColors.primaryPurple,
                          ),
                        ),
                        const SizedBox(height: 32),

                        // Buttons
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () => Navigator.pop(ctx),
                                style: OutlinedButton.styleFrom(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 16),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12)),
                                  side: BorderSide(color: Colors.grey.shade300),
                                ),
                                child: const Text('Cancelar',
                                    style: TextStyle(color: Colors.black)),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.primaryPurple,
                                  foregroundColor: Colors.white,
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 16),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12)),
                                  elevation: 2,
                                ),
                                onPressed: () async {
                                  final Map<String, dynamic> payload = {
                                    'track_stock': track
                                  };

                                  // Save Standard
                                  for (final f in _selectedStandardFields) {
                                    final key = _fieldKey(f);
                                    final v = controllers[f]!.text.trim();
                                    if (f == 'Preço' || f == 'Custo') {
                                      payload[key] = double.tryParse(
                                              v.replaceAll(',', '.')) ??
                                          0.0;
                                    } else if (f == 'Quantidade') {
                                      payload[key] = int.tryParse(v) ?? 0;
                                    } else {
                                      payload[key] = v;
                                    }
                                  }

                                  // Save Custom
                                  for (final cf in _customFields) {
                                    final name = cf['name'];
                                    final key = _fieldKey(name);
                                    final v = controllers[name]!.text.trim();
                                    if (cf['type'] == 'number') {
                                      payload[key] = double.tryParse(
                                              v.replaceAll(',', '.')) ??
                                          0.0;
                                    } else {
                                      payload[key] = v;
                                    }
                                  }

                                  payload['search_name'] =
                                      (payload['name'] ?? '')
                                          .toString()
                                          .toLowerCase();
                                  payload['updated_at'] =
                                      FieldValue.serverTimestamp();

                                  if (doc == null) {
                                    payload['created_at'] =
                                        FieldValue.serverTimestamp();
                                    await productsRef.add(payload);
                                  } else {
                                    await productsRef
                                        .doc(doc.id)
                                        .set(payload, SetOptions(merge: true));
                                  }
                                  if (ctx.mounted) Navigator.pop(ctx);
                                },
                                child: const Text('Salvar Produto',
                                    style:
                                        TextStyle(fontWeight: FontWeight.bold)),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildSheetHeader(String title, VoidCallback onClose) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.grey.shade100)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.black87),
          ),
          IconButton(
            onPressed: onClose,
            icon: const Icon(Icons.close, color: Colors.grey),
            splashRadius: 20,
          ),
        ],
      ),
    );
  }

  Widget _buildTextFieldInput({
    required String label,
    required TextEditingController controller,
    required TextInputType keyboardType,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 13,
                color: Colors.black87)),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          style: const TextStyle(fontSize: 15),
          decoration: InputDecoration(
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none),
            filled: true,
            fillColor: Colors.grey.shade50,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.grey.shade200)),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(
                    color: AppColors.primaryPurple, width: 1.5)),
          ),
        ),
      ],
    );
  }

  TextInputType _getKeyboardType(String field) {
    if (field == 'Preço' || field == 'Custo') {
      return const TextInputType.numberWithOptions(decimal: true);
    } else if (field == 'Quantidade') {
      return TextInputType.number;
    }
    return TextInputType.text;
  }

  // Improved Delete Dialog
  Future<void> _deleteProduct(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Excluir Produto'),
        content: const Text(
            'Deseja realmente excluir este produto? Esta ação não pode ser desfeita.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await productsRef.doc(id).delete();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Produto excluído'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Determine screen size for responsive layout
    final isDesktop = MediaQuery.of(context).size.width >= 900;

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FD),
      appBar: AppBar(
        title: const Text('Produtos e Catálogo',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,
        centerTitle: false,
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 16),
            child: OutlinedButton.icon(
              icon: Icon(_showFieldConfig ? Icons.close : Icons.tune_rounded,
                  size: 18),
              label: const Text('Campos'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primaryPurple,
                side: BorderSide(
                    color: AppColors.primaryPurple.withValues(alpha: 0.3)),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () =>
                  setState(() => _showFieldConfig = !_showFieldConfig),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // Config Panel Animation
          AnimatedSize(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            child: _showFieldConfig
                ? _buildFieldConfigPanel()
                : const SizedBox.shrink(),
          ),

          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: productsRef.orderBy('name').snapshots(),
              builder: (context, snap) {
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final docs = snap.data!.docs;

                if (docs.isEmpty) {
                  return _buildEmptyState();
                }

                if (isDesktop) {
                  return GridView.builder(
                    padding: const EdgeInsets.all(24),
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 400,
                      mainAxisSpacing: 16,
                      crossAxisSpacing: 16,
                      childAspectRatio: 2.5,
                    ),
                    itemCount: docs.length,
                    itemBuilder: (ctx, i) => _ProductCard(
                      data: docs[i].data() as Map<String, dynamic>,
                      docId: docs[i].id,
                      onEdit: () => _showProductEditor(docs[i]),
                      onDelete: () => _deleteProduct(docs[i].id),
                      fieldKey: _fieldKey,
                      standardFields: _selectedStandardFields,
                    ),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: docs.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, i) {
                    final d = docs[i];
                    return _ProductCard(
                      data: d.data() as Map<String, dynamic>,
                      docId: d.id,
                      onEdit: () => _showProductEditor(d),
                      onDelete: () => _deleteProduct(d.id),
                      fieldKey: _fieldKey,
                      standardFields: _selectedStandardFields,
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.primaryPurple,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('NOVO PRODUTO',
            style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1)),
        onPressed: () => _showProductEditor(),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(color: Colors.grey.shade200, blurRadius: 10)
                ]),
            child: Icon(Icons.inventory_2_outlined,
                size: 48, color: Colors.purple.shade200),
          ),
          const SizedBox(height: 20),
          const Text('Seu estoque está vazio',
              style: TextStyle(
                  color: Colors.black54,
                  fontSize: 16,
                  fontWeight: FontWeight.w500)),
          const SizedBox(height: 8),
          const Text('Adicione produtos para começar a vender.',
              style: TextStyle(color: Colors.grey)),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            icon: const Icon(Icons.add),
            label: const Text('Cadastrar Primeiro Produto'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryPurple,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(30)),
            ),
            onPressed: () => _showProductEditor(),
          ),
        ],
      ),
    );
  }

  Widget _buildFieldConfigPanel() {
    // We use a local controller to avoid rebuilding the entire field unnecessarily
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(24),
          bottomRight: Radius.circular(24),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.tune, size: 20, color: AppColors.primaryPurple),
              SizedBox(width: 8),
              Text('Personalizar Campos',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
              'Selecione os campos visíveis ou adicione novos campos personalizados.',
              style: TextStyle(color: Colors.grey, fontSize: 13)),
          const SizedBox(height: 20),

          // common fields (first 8)
          const Text('Campos Comuns',
              style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  color: Colors.grey)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _standardFields.take(8).map((field) {
              final isSelected = _selectedStandardFields.contains(field);
              return FilterChip(
                selected: isSelected,
                label: Text(field),
                onSelected: (selected) {
                  setState(() {
                    if (selected) {
                      _selectedStandardFields.add(field);
                    } else {
                      _selectedStandardFields.remove(field);
                    }
                  });
                  _saveConfig();
                },
                backgroundColor: Colors.white,
                selectedColor: AppColors.primaryPurple.withValues(alpha: 0.1),
                labelStyle: TextStyle(
                    color:
                        isSelected ? AppColors.primaryPurple : Colors.black87,
                    fontWeight:
                        isSelected ? FontWeight.bold : FontWeight.normal),
                side: BorderSide(
                    color: isSelected
                        ? AppColors.primaryPurple
                        : Colors.grey.shade300),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              );
            }).toList(),
          ),

          const SizedBox(height: 20),

          // Additional fields (the rest)
          const Text('Mais Opções Sugeridas',
              style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  color: Colors.grey)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _standardFields.skip(8).map((field) {
              final isSelected = _selectedStandardFields.contains(field);
              return FilterChip(
                selected: isSelected,
                label: Text(field),
                onSelected: (selected) {
                  setState(() {
                    if (selected) {
                      _selectedStandardFields.add(field);
                    } else {
                      _selectedStandardFields.remove(field);
                    }
                  });
                  _saveConfig();
                },
                backgroundColor: Colors.white,
                selectedColor: AppColors.primaryPurple.withValues(alpha: 0.1),
                labelStyle: TextStyle(
                    color:
                        isSelected ? AppColors.primaryPurple : Colors.black87,
                    fontWeight:
                        isSelected ? FontWeight.bold : FontWeight.normal),
                side: BorderSide(
                    color: isSelected
                        ? AppColors.primaryPurple
                        : Colors.grey.shade300),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              );
            }).toList(),
          ),

          const SizedBox(height: 24),

          // Custom Fields List (Already created by user)
          if (_customFields.isNotEmpty) ...[
            const Text('Seus Campos (Criados)',
                style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: Colors.grey)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _customFields.map((cf) {
                return Chip(
                  label: Text(
                      '${cf['name']} (${cf['type'] == 'text' ? 'Texto' : 'Num'})'),
                  deleteIcon: const Icon(Icons.close, size: 16),
                  onDeleted: () {
                    setState(() {
                      _customFields.remove(cf);
                    });
                    _saveConfig();
                  },
                  backgroundColor: AppColors.gold.withValues(alpha: 0.1),
                  side:
                      BorderSide(color: AppColors.gold.withValues(alpha: 0.5)),
                  labelStyle:
                      const TextStyle(color: Colors.black87, fontSize: 13),
                );
              }).toList(),
            ),
            const SizedBox(height: 20),
            const Divider(),
            const SizedBox(height: 20),
          ],

          // Add Custom Field form
          const Text('Não encontrou o que procura? Crie o seu:',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          const SizedBox(height: 12),
          _NewFieldForm(onAdd: (name, type) {
            if (_customFields.any((e) => e['name'] == name) ||
                _standardFields.contains(name)) {
              return;
            }
            setState(() {
              _customFields.add({'name': name, 'type': type});
            });
            _saveConfig();
          }),
        ],
      ),
    );
  }
}

class _NewFieldForm extends StatefulWidget {
  final Function(String, String) onAdd;
  const _NewFieldForm({required this.onAdd});

  @override
  State<_NewFieldForm> createState() => _NewFieldFormState();
}

class _NewFieldFormState extends State<_NewFieldForm> {
  final _nameCtrl = TextEditingController();
  String _type = 'text';

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          flex: 2,
          child: TextField(
            controller: _nameCtrl,
            decoration: InputDecoration(
              hintText: 'Nome (ex: Cor)',
              filled: true,
              isDense: true,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 1,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade400),
              borderRadius: BorderRadius.circular(8),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _type,
                isExpanded: true,
                items: const [
                  DropdownMenuItem(value: 'text', child: Text('Texto')),
                  DropdownMenuItem(value: 'number', child: Text('Número')),
                ],
                onChanged: (v) => setState(() => _type = v!),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primaryPurple,
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          onPressed: () {
            final name = _nameCtrl.text.trim();
            if (name.isEmpty) return;
            widget.onAdd(name, _type);
            _nameCtrl.clear();
          },
          child: const Icon(Icons.add, color: Colors.white),
        ),
      ],
    );
  }
}

class _ProductCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final String docId;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final String Function(String) fieldKey;
  final List<String> standardFields;

  const _ProductCard({
    required this.data,
    required this.docId,
    required this.onEdit,
    required this.onDelete,
    required this.fieldKey,
    required this.standardFields,
  });

  @override
  Widget build(BuildContext context) {
    // Basic fields
    final name = data[fieldKey('Nome')] ?? data['name'] ?? 'Produto sem nome';
    final price = data[fieldKey('Preço')] ?? data['price'] ?? 0.0;
    final qty = data[fieldKey('Quantidade')] ?? data['qty'] ?? 0;

    // Optional/Custom Display
    final codigo = data[fieldKey('Código')];
    final categoria = data[fieldKey('Categoria')];

    // Status color
    final qtyInt = (qty is num) ? qty.toInt() : 0;
    final statusColor = qtyInt > 10
        ? AppColors.successGreen
        : (qtyInt > 0 ? AppColors.gold : AppColors.errorRed);
    final statusText =
        qtyInt > 10 ? 'Em estoque' : (qtyInt > 0 ? 'Baixo' : 'Esgotado');

    return Container(
      margin: const EdgeInsets.only(bottom: 2),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade100, width: 1),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 12,
              offset: const Offset(0, 4)),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onEdit,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Icon / Image Placeholder
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: AppColors.primaryPurple.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                        color: AppColors.primaryPurple.withValues(alpha: 0.1)),
                  ),
                  child: Center(
                    child: Text(
                      name.toString().characters.first.toUpperCase(),
                      style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: AppColors.primaryPurple),
                    ),
                  ),
                ),
                const SizedBox(width: 12),

                // Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            color: Colors.black87),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'R\$ ${(price as num).toStringAsFixed(2)}',
                        style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                            color: Colors.green),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          if (standardFields.contains('Código') &&
                              codigo != null)
                            _Tag(text: '#$codigo', color: Colors.blueGrey),
                          if (standardFields.contains('Categoria') &&
                              categoria != null)
                            _Tag(text: '$categoria', color: Colors.purple),
                        ],
                      ),
                    ],
                  ),
                ),

                // Status & Actions
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '$statusText: $qtyInt',
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: statusColor,
                            fontSize: 10),
                      ),
                    ),
                    const SizedBox(height: 4),
                    _ActionMenu(onEdit: onEdit, onDelete: onDelete),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  final String text;
  final Color color;
  const _Tag({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Text(text,
          style: TextStyle(
              fontSize: 10, color: color, fontWeight: FontWeight.w600)),
    );
  }
}

class _ActionMenu extends StatelessWidget {
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _ActionMenu({required this.onEdit, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      onSelected: (value) {
        if (value == 'edit') onEdit();
        if (value == 'delete') onDelete();
      },
      itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
        const PopupMenuItem<String>(
          value: 'edit',
          child: ListTile(
            leading: Icon(Icons.edit, size: 20),
            title: Text('Editar'),
            contentPadding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
          ),
        ),
        const PopupMenuItem<String>(
          value: 'delete',
          child: ListTile(
            leading: Icon(Icons.delete, size: 20, color: Colors.red),
            title: Text('Excluir', style: TextStyle(color: Colors.red)),
            contentPadding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
          ),
        ),
      ],
      icon: const Icon(Icons.more_vert, size: 20, color: Colors.grey),
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(),
    );
  }
}
