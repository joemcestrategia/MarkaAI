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
  Map<String, String> _productNames = {};

  @override
  void initState() {
    super.initState();
    _loadShopId();
  }

  Future<void> _loadShopId() async {
    final id = await SessionService.getShopId();
    if (id != null) {
      setState(() => shopId = id);
      _loadProductNames(id);
    }
  }

  Future<void> _loadProductNames(String sid) async {
    try {
      final data = await Supabase.instance.client
          .from('products')
          .select('id, name')
          .eq('shop_id', sid);
      if (mounted) {
        setState(() {
          _productNames = {
            for (final p in data) (p['id'] as String): (p['name'] as String? ?? ''),
          };
        });
      }
    } catch (_) {}
  }

  String _typeLabel(String? type) {
    switch (type?.toLowerCase()) {
      case 'sale':       return 'Venda';
      case 'purchase':   return 'Compra';
      case 'adjustment': return 'Ajuste';
      case 'in':         return 'Entrada';
      case 'out':        return 'Saída';
      case 'manual':     return 'Manual';
      default:           return type ?? 'Desconhecido';
    }
  }

  Color _typeColor(String? type) {
    switch (type?.toLowerCase()) {
      case 'sale':
      case 'out':  return Colors.red.shade400;
      case 'purchase':
      case 'in':   return Colors.green.shade500;
      default:     return Colors.orange.shade400;
    }
  }

  IconData _typeIcon(String? type) {
    switch (type?.toLowerCase()) {
      case 'sale':       return Icons.point_of_sale_outlined;
      case 'purchase':   return Icons.shopping_cart_outlined;
      case 'adjustment': return Icons.tune;
      case 'in':         return Icons.arrow_downward;
      case 'out':        return Icons.arrow_upward;
      default:           return Icons.swap_horiz;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (shopId == null) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(color: AppColors.primaryPurple),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FD),
      appBar: AppBar(
        title: const Text('Movimentações de Estoque',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        backgroundColor: AppColors.primaryPurple,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
      ),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: Supabase.instance.client
            .from('stock_movements')
            .stream(primaryKey: ['id'])
            .eq('shop_id', shopId!)
            .limit(200),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(
              child: CircularProgressIndicator(color: AppColors.primaryPurple),
            );
          }

          final docs = List<Map<String, dynamic>>.from(snap.data!);
          docs.sort((a, b) {
            final dA = a['created_at'] as String? ?? '';
            final dB = b['created_at'] as String? ?? '';
            return dB.compareTo(dA);
          });

          if (docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.swap_horiz, size: 64, color: Colors.grey[300]),
                  const SizedBox(height: 16),
                  Text(
                    'Nenhuma movimentação registrada',
                    style: TextStyle(color: Colors.grey[500], fontSize: 14),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            itemBuilder: (context, i) {
              final data = docs[i];
              final type  = data['type'] as String?;
              final delta = (data['delta'] as num? ?? 0).toInt();
              final productId = data['product_id'] as String?;
              final productName = productId != null
                  ? (_productNames[productId] ?? 'Produto desconhecido')
                  : 'Produto não identificado';

              DateTime? createdAt;
              try {
                createdAt = data['created_at'] != null
                    ? DateTime.parse(data['created_at']).toLocal()
                    : null;
              } catch (_) {}

              final dateStr = createdAt != null
                  ? '${createdAt.day.toString().padLeft(2, '0')}/${createdAt.month.toString().padLeft(2, '0')}/${createdAt.year}  ${createdAt.hour.toString().padLeft(2, '0')}:${createdAt.minute.toString().padLeft(2, '0')}'
                  : '—';

              final color = _typeColor(type);

              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
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
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  leading: Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Icon(_typeIcon(type), color: color, size: 20),
                  ),
                  title: Text(
                    productName,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            _typeLabel(type),
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: color),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          dateStr,
                          style: TextStyle(
                              fontSize: 11, color: Colors.grey.shade500),
                        ),
                      ],
                    ),
                  ),
                  trailing: Text(
                    delta > 0 ? '+$delta' : '$delta',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 17,
                      color: delta > 0 ? Colors.green.shade600 : Colors.red.shade400,
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
