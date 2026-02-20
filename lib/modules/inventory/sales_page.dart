import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';

class SalesPage extends StatefulWidget {
  const SalesPage({super.key});

  @override
  State<SalesPage> createState() => _SalesPageState();
}

class _SalesPageState extends State<SalesPage> {
  final CollectionReference productsRef =
      FirebaseFirestore.instance.collection('products');
  final CollectionReference salesRef =
      FirebaseFirestore.instance.collection('sales');
  final CollectionReference movementsRef =
      FirebaseFirestore.instance.collection('stock_movements');

  final List<Map<String, dynamic>> cart = [];
  String search = '';

  double _calculateTotal() =>
      cart.fold(0.0, (t, e) => t + ((e['price'] ?? 0.0) * (e['qty'] ?? 1)));

  Future<void> _addToCart(DocumentSnapshot prod) async {
    final data = (prod.data() as Map<String, dynamic>?) ?? {};
    int qty = 1;

    await showModalBottomSheet(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (c, setStateLocal) {
          return ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            child: Container(
              color: Colors.white,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 20),
                    decoration: BoxDecoration(
                      border: Border(
                          bottom: BorderSide(color: Colors.grey.shade200)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('${data['name']}',
                            style: const TextStyle(
                                fontSize: 18, fontWeight: FontWeight.w700)),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade50,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Preço Unitário',
                                      style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey[600])),
                                  const SizedBox(height: 4),
                                  Text(
                                      'R\$ ${((data['price'] ?? 0) as num).toStringAsFixed(2)}',
                                      style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w700)),
                                ],
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text('Disponível',
                                      style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey[600])),
                                  const SizedBox(height: 4),
                                  Text('${data['qty'] ?? 0}',
                                      style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w700)),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),
                        Text('Quantidade',
                            style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Colors.grey[700])),
                        const SizedBox(height: 12),
                        Container(
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey.shade300),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: IconButton(
                                  icon: const Icon(Icons.remove),
                                  onPressed: qty > 1
                                      ? () => setStateLocal(() => qty--)
                                      : null,
                                ),
                              ),
                              Expanded(
                                child: TextField(
                                  textAlign: TextAlign.center,
                                  keyboardType: TextInputType.number,
                                  decoration: InputDecoration(
                                    border: InputBorder.none,
                                    hintText: qty.toString(),
                                  ),
                                  onChanged: (v) => setStateLocal(
                                      () => qty = int.tryParse(v) ?? 1),
                                ),
                              ),
                              Expanded(
                                child: IconButton(
                                  icon: const Icon(Icons.add),
                                  onPressed: () => setStateLocal(() => qty++),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primaryPurple,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10)),
                            ),
                            onPressed: () {
                              if (qty > 0) {
                                cart.add({
                                  'productId': prod.id,
                                  'name': data['name'],
                                  'qty': qty,
                                  'price': data['price'] ?? 0.0,
                                });
                                Navigator.pop(ctx);
                                setState(() {});
                              }
                            },
                            child: const Text('Adicionar ao Carrinho',
                                style: TextStyle(
                                    fontWeight: FontWeight.w600, fontSize: 15)),
                          ),
                        ),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _checkout() async {
    if (cart.isEmpty) return;

    final saleDoc = salesRef.doc();
    try {
      for (final line in cart) {
        final pid = line['productId'] as String;
        final qty = line['qty'] as int;
        final prodDoc = productsRef.doc(pid);

        await FirebaseFirestore.instance.runTransaction((tx) async {
          final snap = await tx.get(prodDoc);
          if (!snap.exists) throw Exception('Produto não encontrado: $pid');
          final map = (snap.data() as Map<String, dynamic>?) ?? {};
          final cur = (map['qty'] ?? 0) as int;
          final track = (map['track_stock'] ?? true) as bool;
          if (track && cur < qty) {
            throw Exception('Estoque insuficiente para ${map['name'] ?? pid}');
          }
          final newQty = track ? cur - qty : cur;
          tx.update(prodDoc, {'qty': newQty});
          final mv = movementsRef.doc();
          tx.set(mv, {
            'productId': pid,
            'delta': -qty,
            'type': 'sale',
            'refId': saleDoc.id,
            'created_at': FieldValue.serverTimestamp()
          });
        });
      }

      await saleDoc.set({
        'items': cart,
        'total': _calculateTotal(),
        'created_at': FieldValue.serverTimestamp(),
      });

      cart.clear();
      setState(() {});

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Venda registrada com sucesso'),
            backgroundColor: Colors.green.shade600,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro: $e'),
            backgroundColor: Colors.red.shade600,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 900;

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FD),
      appBar: AppBar(
        title: const Text('Frente de Caixa (PDV)',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,
      ),
      body: isMobile ? _buildMobileLayout() : _buildDesktopLayout(),
      floatingActionButton: cart.isNotEmpty
          ? FloatingActionButton.extended(
              backgroundColor: Colors.green.shade600,
              onPressed: _checkout,
              icon: const Icon(Icons.check_circle),
              label: Text(
                  'Finalizar: R\$ ${_calculateTotal().toStringAsFixed(2)}'),
            )
          : null,
    );
  }

  Widget _buildMobileLayout() {
    return Column(
      children: [
        _buildSearchBar(),
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Produtos',
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: Colors.grey[800])),
                      const SizedBox(height: 12),
                      _buildProductsList(),
                    ],
                  ),
                ),
                if (cart.isNotEmpty) ...[
                  const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Carrinho',
                            style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: Colors.grey[800])),
                        const SizedBox(height: 12),
                        _buildCart(),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDesktopLayout() {
    return Column(
      children: [
        _buildSearchBar(),
        Expanded(
          child: Row(
            children: [
              Expanded(
                flex: 2,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Produtos',
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: Colors.grey[800])),
                      const SizedBox(height: 12),
                      Expanded(child: _buildProductsList()),
                    ],
                  ),
                ),
              ),
              Container(width: 1, color: Colors.grey.shade200),
              Expanded(
                flex: 1,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Carrinho',
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: Colors.grey[800])),
                      const SizedBox(height: 12),
                      cart.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.shopping_cart_outlined,
                                      size: 48, color: Colors.grey[300]),
                                  const SizedBox(height: 12),
                                  Text('Vazio',
                                      style:
                                          TextStyle(color: Colors.grey[600])),
                                ],
                              ),
                            )
                          : Expanded(child: _buildCart()),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: TextField(
        decoration: InputDecoration(
          prefixIcon:
              const Icon(Icons.search_rounded, size: 20, color: Colors.grey),
          hintText: 'Buscar produto por nome ou código...',
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
    return StreamBuilder<QuerySnapshot>(
      stream: (search.isEmpty)
          ? productsRef.orderBy('name').limit(50).snapshots()
          : productsRef
              .where('name', isGreaterThanOrEqualTo: search)
              .where('name', isLessThanOrEqualTo: '$search\uf8ff')
              .snapshots(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snap.data!.docs;

        if (docs.isEmpty) {
          return Center(
              child: Text('Nenhum produto encontrado',
                  style: TextStyle(color: Colors.grey[600])));
        }

        return ListView.builder(
          itemCount: docs.length,
          itemBuilder: (context, i) {
            final d = docs[i];
            final data = (d.data() as Map<String, dynamic>?) ?? {};
            final qty = data['qty'] ?? 0;
            final price = ((data['price'] ?? 0) as num).toStringAsFixed(2);
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
                onTap: () => _addToCart(d),
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
                                '${item['qty']}x R\$ ${((item['price'] ?? 0) as num).toStringAsFixed(2)}',
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
