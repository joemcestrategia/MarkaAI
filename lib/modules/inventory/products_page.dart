import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/services/session_service.dart';

class ProductsPage extends StatefulWidget {
  const ProductsPage({super.key});

  @override
  State<ProductsPage> createState() => _ProductsPageState();
}

class _ProductsPageState extends State<ProductsPage> {
  final productsRef = Supabase.instance.client.from('products');
  String? _shopId;

  final List<String> _standardFields = [
    'Codigo',
    'Nome',
    'Descricao',
    'Preco',
    'Custo',
    'Quantidade',
    'Categoria',
    'Marca',
    'Tamanho',
    'Cor',
    'Peso',
    'Fornecedor',
    'Localizacao',
    'Validade',
    'NCM',
    'EAN/GTIN',
    'Unidade (UN, KG, L)',
  ];

  List<String> _selectedStandardFields = [
    'Codigo',
    'Nome',
    'Preco',
    'Quantidade'
  ];

  List<Map<String, dynamic>> _customFields = [];
  bool _showFieldConfig = false;
  bool _isLoading = true;

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
        final doc = await Supabase.instance.client.from('shops').select('inventory_config').eq('id', sid).maybeSingle();
        
        if (doc != null) {
          final cfg = doc['inventory_config'] as Map<String, dynamic>?;

          if (cfg != null) {
            if (cfg['product_fields'] != null) {
              _selectedStandardFields = List<String>.from(cfg['product_fields']);
            }
            if (cfg['custom_fields'] != null) {
              _customFields = List<Map<String, dynamic>>.from(cfg['custom_fields']);
            }
          }
        }
      }
    } catch (e) {
      debugPrint("Error loading shop context: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _saveConfig() async {
    if (_shopId == null) return;
    try {
      await Supabase.instance.client.from('shops').update({
        'inventory_config': {
          'product_fields': _selectedStandardFields,
          'custom_fields': _customFields,
        }
      }).eq('id', _shopId!);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Configuração salva!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao salvar config: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(color: AppColors.primaryPurple),
        ),
      );
    }

    if (_shopId == null) {
      return Scaffold(
        backgroundColor: const Color(0xFFF8F9FD),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.store_mall_directory_outlined,
                  size: 64, color: Colors.grey[300]),
              const SizedBox(height: 16),
              const Text('Loja não encontrada.',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.black54)),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () {
                  setState(() => _isLoading = true);
                  _loadShopContext();
                },
                child: const Text('Tentar novamente'),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FD),
      appBar: AppBar(
        title: const Text('Produtos'),
        backgroundColor: AppColors.primaryPurple,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: Icon(_showFieldConfig ? Icons.close : Icons.settings),
            onPressed: () => setState(() => _showFieldConfig = !_showFieldConfig),
          ),
        ],
      ),
      body: _showFieldConfig ? _buildConfigUI() : _buildProductsList(),
      floatingActionButton: FloatingActionButton(
        onPressed: _addProduct,
        backgroundColor: AppColors.primaryPurple,
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  Widget _buildConfigUI() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Campos Visíveis do Produto:', style: TextStyle(fontWeight: FontWeight.bold)),
          Wrap(
            spacing: 8,
            children: _standardFields.map((field) {
              final isSelected = _selectedStandardFields.contains(field);
              return FilterChip(
                label: Text(field),
                selected: isSelected,
                onSelected: (val) {
                  setState(() {
                    if (val) {
                      _selectedStandardFields.add(field);
                    } else {
                      _selectedStandardFields.remove(field);
                    }
                  });
                },
              );
            }).toList(),
          ),
          const SizedBox(height: 20),
          ElevatedButton(onPressed: _saveConfig, child: const Text('Salvar Configuração')),
        ],
      ),
    );
  }

  String _buildProductSubtitle(
      Map<String, dynamic> data, String priceStr, dynamic qty) {
    final parts = <String>['R\$ $priceStr', 'Qtd: $qty'];
    final color = data['color'] as String?;
    if (color != null && color.isNotEmpty) parts.add('Cor: $color');
    final weight = data['weight'];
    final unit = (data['weight_unit'] as String?) ?? 'g';
    if (weight != null) parts.add('$weight$unit');
    return parts.join(' • ');
  }

  Widget _buildProductsList() {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: productsRef.stream(primaryKey: ['id']).eq('shop_id', _shopId!),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final docs = snapshot.data!;

        if (docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.inventory_2_outlined,
                    size: 72, color: Colors.grey[300]),
                const SizedBox(height: 16),
                const Text(
                  'Nenhum produto cadastrado',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87),
                ),
                const SizedBox(height: 8),
                Text(
                  'Toque no + para adicionar seu primeiro produto',
                  style: TextStyle(color: Colors.grey[600], fontSize: 13),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final data = docs[index];
            final price = (data['price'] ?? 0.0);
            final priceStr = price is num
                ? price.toStringAsFixed(2)
                : price.toString();
            final qty = data['stock_quantity'] ?? data['qty'] ?? 0;
            return Container(
              margin:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade100),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.03),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: ListTile(
                leading: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.primaryPurple.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.inventory_2_outlined,
                      color: AppColors.primaryPurple, size: 20),
                ),
                title: Text(
                  data['name'] ?? 'Sem nome',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Text(
                  _buildProductSubtitle(data, priceStr, qty),
                  style:
                      TextStyle(color: Colors.grey[600], fontSize: 13),
                ),
                trailing: const Icon(Icons.chevron_right,
                    color: Colors.grey, size: 20),
                onTap: () => _editProduct(data),
              ),
            );
          },
        );
      },
    );
  }

  void _addProduct() {
    _showProductDialog();
  }

  void _editProduct(Map<String, dynamic> data) {
    _showProductDialog(existing: data);
  }

  InputDecoration _fieldDecoration(String label, String hint, IconData icon) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
      filled: true,
      fillColor: const Color(0xFFF8F9FD),
      prefixIcon: Icon(icon, color: Colors.grey.shade500, size: 20),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey.shade200),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey.shade200),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide:
            const BorderSide(color: AppColors.primaryPurple, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.red),
      ),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    );
  }

  void _showProductDialog({Map<String, dynamic>? existing}) {
    final isEditing = existing != null;
    final nameCtrl = TextEditingController(text: existing?['name'] ?? '');
    final priceCtrl = TextEditingController(
        text: existing != null
            ? (existing['price'] ?? 0.0).toString()
            : '');
    final qtyCtrl = TextEditingController(
        text: existing != null
            ? (existing['stock_quantity'] ?? existing['qty'] ?? 0).toString()
            : '0');
    final colorCtrl =
        TextEditingController(text: existing?['color'] ?? '');
    final weightCtrl = TextEditingController(
        text: existing != null && existing['weight'] != null
            ? existing['weight'].toString()
            : '');
    String weightUnit = (existing?['weight_unit'] as String?) ?? 'g';
    final formKey = GlobalKey<FormState>();
    bool isSaving = false;

    Future<void> onSave(StateSetter setDlgState, BuildContext ctx) async {
      if (!formKey.currentState!.validate()) return;
      setDlgState(() => isSaving = true);

      final name = nameCtrl.text.trim();
      final price =
          double.tryParse(priceCtrl.text.replaceAll(',', '.')) ?? 0.0;
      final qty = int.tryParse(qtyCtrl.text.trim()) ?? 0;
      final color = colorCtrl.text.trim().isEmpty
          ? null
          : colorCtrl.text.trim();
      final weightRaw = weightCtrl.text.trim();
      final weight = weightRaw.isEmpty
          ? null
          : double.tryParse(weightRaw.replaceAll(',', '.'));

      try {
        final payload = {
          'name': name,
          'price': price,
          'stock_quantity': qty,
          'color': color,
          'weight': weight,
          'weight_unit': weightUnit,
        };
        if (isEditing) {
          await productsRef.update(payload).eq('id', existing['id']);
        } else {
          await productsRef.insert({...payload, 'shop_id': _shopId});
        }
        if (ctx.mounted) Navigator.pop(ctx);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(isEditing
                ? 'Produto atualizado!'
                : 'Produto cadastrado!'),
            backgroundColor: Colors.green,
          ));
        }
      } catch (e) {
        setDlgState(() => isSaving = false);
        if (ctx.mounted) {
          ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
            content: Text('Erro ao salvar: $e'),
            backgroundColor: Colors.red,
          ));
        }
      }
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => Padding(
          padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius:
                  BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(top: 12, bottom: 4),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 8, 4),
                    child: Row(
                      children: [
                        Text(
                          isEditing ? 'Editar Produto' : 'Novo Produto',
                          style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold),
                        ),
                        const Spacer(),
                        if (isEditing)
                          IconButton(
                            onPressed: isSaving
                                ? null
                                : () =>
                                    _confirmDeleteProduct(ctx, existing),
                            icon: const Icon(Icons.delete_outline,
                                color: Colors.red),
                            tooltip: 'Excluir produto',
                          ),
                        IconButton(
                          onPressed: () => Navigator.pop(ctx),
                          icon: Icon(Icons.close,
                              color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                  ),
                  SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                    child: Form(
                      key: formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          TextFormField(
                            controller: nameCtrl,
                            autofocus: true,
                            textCapitalization:
                                TextCapitalization.sentences,
                            decoration: _fieldDecoration(
                                'Nome do produto',
                                'Ex: Shampoo 500ml',
                                Icons.label_outline),
                            validator: (v) =>
                                (v == null || v.trim().isEmpty)
                                    ? 'Informe o nome'
                                    : null,
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: TextFormField(
                                  controller: priceCtrl,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                          decimal: true),
                                  decoration: _fieldDecoration(
                                      'Preço (R\$)',
                                      '0,00',
                                      Icons.attach_money_outlined),
                                  validator: (v) {
                                    if (v == null || v.trim().isEmpty) {
                                      return 'Informe o preço';
                                    }
                                    final p = double.tryParse(
                                        v.replaceAll(',', '.'));
                                    return (p == null || p < 0)
                                        ? 'Inválido'
                                        : null;
                                  },
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: TextFormField(
                                  controller: qtyCtrl,
                                  keyboardType: TextInputType.number,
                                  decoration: _fieldDecoration(
                                      'Qtd em estoque',
                                      '0',
                                      Icons.numbers_outlined),
                                  validator: (v) =>
                                      (v == null ||
                                              int.tryParse(v) == null)
                                          ? 'Inválido'
                                          : null,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: colorCtrl,
                            textCapitalization:
                                TextCapitalization.sentences,
                            decoration: _fieldDecoration(
                                'Cor',
                                'Ex: Azul, Louro 7.0',
                                Icons.palette_outlined),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                flex: 3,
                                child: TextFormField(
                                  controller: weightCtrl,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                          decimal: true),
                                  decoration: _fieldDecoration(
                                      'Peso / Volume',
                                      '0',
                                      Icons.scale_outlined),
                                  validator: (v) {
                                    if (v != null &&
                                        v.trim().isNotEmpty) {
                                      final p = double.tryParse(
                                          v.replaceAll(',', '.'));
                                      return (p == null || p < 0)
                                          ? 'Inválido'
                                          : null;
                                    }
                                    return null;
                                  },
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                flex: 2,
                                child: DropdownButtonFormField<String>(
                                  value: weightUnit,
                                  decoration: InputDecoration(
                                    labelText: 'Unidade',
                                    filled: true,
                                    fillColor: const Color(0xFFF8F9FD),
                                    border: OutlineInputBorder(
                                      borderRadius:
                                          BorderRadius.circular(12),
                                      borderSide: BorderSide(
                                          color: Colors.grey.shade200),
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius:
                                          BorderRadius.circular(12),
                                      borderSide: BorderSide(
                                          color: Colors.grey.shade200),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius:
                                          BorderRadius.circular(12),
                                      borderSide: const BorderSide(
                                          color: AppColors.primaryPurple,
                                          width: 1.5),
                                    ),
                                    contentPadding:
                                        const EdgeInsets.symmetric(
                                            horizontal: 16, vertical: 14),
                                  ),
                                  items: const [
                                    DropdownMenuItem(
                                        value: 'g', child: Text('g')),
                                    DropdownMenuItem(
                                        value: 'kg', child: Text('kg')),
                                    DropdownMenuItem(
                                        value: 'ml', child: Text('ml')),
                                    DropdownMenuItem(
                                        value: 'L', child: Text('L')),
                                  ],
                                  onChanged: (val) {
                                    if (val != null) {
                                      setDlgState(() => weightUnit = val);
                                    }
                                  },
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                    child: SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        onPressed: isSaving
                            ? null
                            : () => onSave(setDlgState, ctx),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primaryPurple,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor:
                              AppColors.primaryPurple.withValues(alpha: 0.5),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                          elevation: 0,
                        ),
                        child: isSaving
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                    color: Colors.white, strokeWidth: 2.5))
                            : Text(
                                isEditing
                                    ? 'Salvar alterações'
                                    : 'Cadastrar produto',
                                style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold),
                              ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _confirmDeleteProduct(
      BuildContext ctx, Map<String, dynamic> product) {
    Navigator.pop(ctx);
    showDialog(
      context: context,
      builder: (ctx2) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Excluir produto?'),
        content: Text(
            'Tem certeza que deseja excluir "${product['name']}"? Esta ação não pode ser desfeita.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx2),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () async {
              try {
                await productsRef
                    .delete()
                    .eq('id', product['id']);
                if (ctx2.mounted) Navigator.pop(ctx2);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Produto excluído.'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              } catch (e) {
                if (ctx2.mounted) Navigator.pop(ctx2);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Erro ao excluir: $e')),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
  }
}
