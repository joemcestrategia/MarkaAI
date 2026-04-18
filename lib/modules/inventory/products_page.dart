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
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint("Error loading shop context: $e");
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
    if (_shopId == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
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

  Widget _buildProductsList() {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: productsRef.stream(primaryKey: ['id']).eq('shop_id', _shopId!),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final docs = snapshot.data!;

        if (docs.isEmpty) {
          return const Center(child: Text('Nenhum produto cadastrado.'));
        }

        return ListView.builder(
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final data = docs[index];
            return Card(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: ListTile(
                title: Text(data['name'] ?? 'Sem Nome'),
                subtitle: Text("R\$ ${data['price'] ?? '0.00'} - Qtd: ${data['stock_quantity'] ?? '0'}"),
                onTap: () => _editProduct(data),
              ),
            );
          },
        );
      },
    );
  }

  void _addProduct() {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Funcionalidade em desenvolvimento.')));
  }

  void _editProduct(Map<String, dynamic> data) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Funcionalidade em desenvolvimento.')));
  }
}
