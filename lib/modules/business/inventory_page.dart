import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/theme/app_colors.dart';
import '../../core/services/session_service.dart';

/// Página de movimentações de estoque (histórico de entradas/saídas de produtos)
class InventoryPage extends StatefulWidget {
  const InventoryPage({super.key});

  @override
  State<InventoryPage> createState() => _InventoryPageState();
}

class _InventoryPageState extends State<InventoryPage> {
  String? _shopId;
  bool _isLoading = true;
  List<Map<String, dynamic>> _movements = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final id = await SessionService.getShopId();
    if (id == null || !mounted) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }
    setState(() {
      _shopId = id;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_shopId == null) {
      return const Scaffold(body: Center(child: Text('Loja não identificada.')));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Movimentações de Estoque'),
        backgroundColor: AppColors.primaryPurple,
        foregroundColor: Colors.white,
      ),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: Supabase.instance.client
            .from('products')
            .stream(primaryKey: ['id'])
            .eq('shop_id', _shopId!),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final docs = snapshot.data!;
          if (docs.isEmpty) {
            return const Center(child: Text('Nenhuma movimentação registrada.'));
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            itemBuilder: (context, i) {
              final d = docs[i];
              return ListTile(
                leading: const CircleAvatar(
                  backgroundColor: AppColors.primaryPurple,
                  child: Icon(Icons.inventory_2, color: Colors.white),
                ),
                title: Text(d['name'] ?? 'Produto'),
                subtitle: Text('Qtd: ${d['stock_quantity'] ?? '0'}'),
                trailing: Text('R\$ ${d['price'] ?? '0.00'}',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
              );
            },
          );
        },
      ),
    );
  }
}
