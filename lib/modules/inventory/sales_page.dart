import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/theme/app_colors.dart';
import '../../core/services/session_service.dart';

class SalesPage extends StatefulWidget {
  const SalesPage({super.key});

  @override
  State<SalesPage> createState() => _SalesPageState();
}

class _SalesPageState extends State<SalesPage> {
  final productsRef = Supabase.instance.client.from('products');
  String search = '';
  List<Map<String, dynamic>> cart = [];
  bool _isSaving = false;

  void _addToCart(Map<String, dynamic> data) {
    setState(() {
      final index = cart.indexWhere((item) => item['id'] == data['id']);
      if (index >= 0) {
        cart[index]['qty']++;
      } else {
        cart.add({
          'id': data['id'],
          'name': data['name'],
          'price': data['price'] ?? 0.0,
          'qty': 1,
        });
      }
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${data['name']} adicionado ao carrinho'),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  double _calculateTotal() {
    return cart.fold(0.0, (sum, item) => sum + ((item['price'] ?? 0.0) * (item['qty'] ?? 1)));
  }

  Future<void> _finalizeSale() async {
    if (cart.isEmpty) return;

    final shopId = await SessionService.getShopId();
    if (shopId == null) return;

    setState(() => _isSaving = true);

    try {
      final supabase = Supabase.instance.client;
      
      final saleData = {
        'shop_id': shopId,
        'items': cart,
        'total': _calculateTotal(),
        'created_at': DateTime.now().toIso8601String(),
      };

      final saleResponse = await supabase.from('sales').insert(saleData).select().single();
      final saleId = saleResponse['id'];

      for (var item in cart) {
        final pDoc = await productsRef.select().eq('id', item['id']).single();
        final currentQty = ((pDoc['stock_quantity'] ?? pDoc['qty'] ?? 0) as num).toInt();
        final newQty = (currentQty - (item['qty'] as int)).clamp(0, 999999);
        
        await productsRef.update({'stock_quantity': newQty, 'qty': newQty}).eq('id', item['id']);

        await supabase.from('stock_movements').insert({
          'shop_id': shopId,
          'product_id': item['id'],
          'type': 'sale',
          'delta': -item['qty'],
          'ref_id': saleId,
          'created_at': DateTime.now().toIso8601String(),
        });
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Venda finalizada com sucesso!')),
        );
        setState(() {
          cart.clear();
          _isSaving = false;
        });
      }
    } catch (e) {
      debugPrint('Erro ao finalizar venda: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao finalizar venda: $e')),
        );
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 768;
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FD),
      appBar: AppBar(
        title: const Text('Registrar Venda',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        backgroundColor: AppColors.primaryPurple,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
      ),
      body: SafeArea(
        bottom: true,
        child: isMobile ? _buildMobileLayout() : _buildDesktopLayout(),
      ),
    );
  }

  Widget _buildMobileLayout() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: _buildSearchField(),
        ),
        Expanded(child: _buildProductsList()),
        if (cart.isNotEmpty) _buildMobileCartBar(),
      ],
    );
  }

  Widget _buildMobileCartBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey.shade200)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: _showCartBottomSheet,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.primaryPurple.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Icon(Icons.shopping_cart_outlined,
                      color: AppColors.primaryPurple, size: 18),
                  const SizedBox(width: 6),
                  Text(
                    '${cart.length} ${cart.length == 1 ? "item" : "itens"}',
                    style: const TextStyle(
                        color: AppColors.primaryPurple,
                        fontWeight: FontWeight.bold,
                        fontSize: 13),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Total',
                    style: TextStyle(fontSize: 11, color: Colors.grey)),
                Text(
                  'R\$ ${_calculateTotal().toStringAsFixed(2)}',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: Colors.green),
                ),
              ],
            ),
          ),
          ElevatedButton(
            onPressed: (_isSaving || cart.isEmpty) ? null : _finalizeSale,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
            child: _isSaving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2))
                : const Text('Finalizar',
                    style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showCartBottomSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.75),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(top: 12, bottom: 4),
                decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(4)),
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Icon(Icons.shopping_cart_outlined,
                      color: AppColors.primaryPurple),
                  SizedBox(width: 8),
                  Text('Carrinho',
                      style: TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 18)),
                ],
              ),
            ),
            Flexible(child: _buildCart()),
            Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: (_isSaving || cart.isEmpty)
                      ? null
                      : () {
                          Navigator.pop(ctx);
                          _finalizeSale();
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('FINALIZAR VENDA',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDesktopLayout() {
    return Row(
      children: [
        Expanded(
          flex: 2,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                _buildSearchField(),
                const SizedBox(height: 20),
                Expanded(child: _buildProductsList()),
              ],
            ),
          ),
        ),
        Container(
          width: 350,
          decoration: BoxDecoration(
            color: const Color(0xFFF8F9FA),
            border: Border(left: BorderSide(color: Colors.grey.shade200)),
          ),
          child: Column(
            children: [
              const Padding(
                padding: EdgeInsets.all(20),
                child: Text('Carrinho',
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              ),
              Expanded(child: _buildCart()),
              Padding(
                padding: const EdgeInsets.all(20),
                child: SizedBox(
                  width: double.infinity,
                  height: 55,
                  child: ElevatedButton(
                    onPressed:
                        (_isSaving || cart.isEmpty) ? null : _finalizeSale,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                    ),
                    child: _isSaving
                        ? const CircularProgressIndicator(color: Colors.white)
                        : const Text('FINALIZAR VENDA',
                            style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSearchField() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: TextField(
        decoration: InputDecoration(
          prefixIcon:
              const Icon(Icons.search_rounded, size: 20, color: Colors.grey),
          hintText: 'Buscar produto por nome...',
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide.none),
          filled: true,
          fillColor: Colors.white,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
        onChanged: (v) => setState(() => search = v.trim()),
      ),
    );
  }

  Widget _buildProductsList() {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: productsRef.stream(primaryKey: ['id']).map((list) {
        var filtered = list;
        if (search.isNotEmpty) {
          filtered = list.where((p) => (p['name'] ?? '').toString().toLowerCase().contains(search.toLowerCase())).toList();
        }
        filtered.sort((a, b) => (a['name'] ?? '').toString().compareTo((b['name'] ?? '').toString()));
        return filtered.take(50).toList();
      }),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snap.data!;

        if (docs.isEmpty) {
          return Center(
              child: Text('Nenhum produto encontrado',
                  style: TextStyle(color: Colors.grey[600])));
        }

        return ListView.builder(
          itemCount: docs.length,
          itemBuilder: (context, i) {
            final data = docs[i];
            final qty = data['qty'] ?? 0;
            final price = ((data['price'] ?? 0.0) as num).toStringAsFixed(2);
            final name = data['name'] ?? '-';

            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.grey.shade100, width: 1),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.02),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ListTile(
                onTap: () => _addToCart(data),
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
                title: Text(name,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 14)),
                subtitle: Text('R\$ $price',
                    style: const TextStyle(
                        fontSize: 13,
                        color: Colors.green,
                        fontWeight: FontWeight.w600)),
                trailing: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: (qty > 10
                            ? Colors.green
                            : (qty > 0 ? Colors.orange : Colors.red))
                        .withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: (qty > 10
                                ? Colors.green
                                : (qty > 0 ? Colors.orange : Colors.red))
                            .withValues(alpha: 0.2)),
                  ),
                  child: Text(
                    'Qtd: $qty',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: qty > 10
                          ? Colors.green
                          : (qty > 0 ? Colors.orange : Colors.red),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildCart() {
    return Column(
      children: [
        Expanded(
          child: ListView.builder(
            itemCount: cart.length,
            itemBuilder: (context, i) {
              final item = cart[i];
              final subtotal = ((item['price'] ?? 0.0) * (item['qty'] ?? 1))
                  .toStringAsFixed(2);

              return Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(item['name'],
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600, fontSize: 13)),
                            const SizedBox(height: 4),
                            Text(
                                '${item['qty']}x R\$ ${((item['price'] ?? 0.0) as num).toStringAsFixed(2)}',
                                style: TextStyle(
                                    fontSize: 12, color: Colors.grey[600])),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.green.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color: Colors.green.withValues(alpha: 0.2)),
                        ),
                        child: Text('R\$ $subtotal',
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.green[700],
                                fontSize: 11)),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: () => setState(() => cart.removeAt(i)),
                        child: Icon(Icons.close,
                            size: 18, color: Colors.red.shade400),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        Container(
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: Colors.grey.shade200)),
          ),
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Total:',
                      style:
                          TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                  Text('R\$ ${_calculateTotal().toStringAsFixed(2)}',
                      style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 18,
                          color: Colors.green)),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}
