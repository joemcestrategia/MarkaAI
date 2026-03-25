import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/theme/app_colors.dart';
import '../../core/services/session_service.dart';

class StockMovementsPage extends StatefulWidget {
  const StockMovementsPage({super.key});

  @override
  State<StockMovementsPage> createState() => _StockMovementsPageState();
}

class _StockMovementsPageState extends State<StockMovementsPage> {
  String? shopId;

  @override
  void initState() {
    super.initState();
    _loadShopId();
  }

  Future<void> _loadShopId() async {
    final id = await SessionService.getShopId();
    setState(() => shopId = id);
  }

  @override
  Widget build(BuildContext context) {
    if (shopId == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Movimentacao de Estoque',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        backgroundColor: AppColors.primaryPurple,
        foregroundColor: Colors.white,
      ),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: Supabase.instance.client
            .from('stock_movements')
            .stream(primaryKey: ['id'])
            .eq('shop_id', shopId!)
            .limit(100),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final docs = snap.data!;

          if (docs.isEmpty) {
            return const Center(child: Text('Nenhuma movimentacao encontrada.'));
          }

          final sortedDocs = List<Map<String, dynamic>>.from(docs);
          sortedDocs.sort((a, b) {
            final dateA = DateTime.parse(a['created_at'] ?? DateTime.now().toIso8601String());
            final dateB = DateTime.parse(b['created_at'] ?? DateTime.now().toIso8601String());
            return dateB.compareTo(dateA);
          });

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: sortedDocs.length,
            itemBuilder: (context, i) {
              final data = sortedDocs[i];
              final type = data['type'] ?? 'unknown';
              final delta = data['delta'] ?? 0;
              final createdAt = data['created_at'] != null 
                  ? DateTime.parse(data['created_at']) 
                  : DateTime.now();

              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: delta > 0 
                        ? Colors.green.withValues(alpha: 0.1) 
                        : Colors.red.withValues(alpha: 0.1),
                    child: Icon(
                      delta > 0 ? Icons.add : Icons.remove,
                      color: delta > 0 ? Colors.green : Colors.red,
                    ),
                  ),
                  title: FutureBuilder<Map<String, dynamic>?>(
                    future: Supabase.instance.client
                        .from('products')
                        .select('name')
                        .eq('id', data['productId'] ?? '')
                        .maybeSingle(),
                    builder: (context, pSnap) {
                      final pName = pSnap.data?['name'] ?? 'Produto ID: ${data['productId']}';
                      return Text(pName, style: const TextStyle(fontWeight: FontWeight.bold));
                    },
                  ),
                  subtitle: Text('Tipo: ${type.toUpperCase()} • ${createdAt.day}/${createdAt.month}/${createdAt.year} ${createdAt.hour}:${createdAt.minute.toString().padLeft(2, "0")}'),
                  trailing: Text(
                    delta > 0 ? '+$delta' : '$delta',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: delta > 0 ? Colors.green : Colors.red,
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
