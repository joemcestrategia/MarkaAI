import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';

class PurchasesPage extends StatefulWidget {
  const PurchasesPage({super.key});

  @override
  State<PurchasesPage> createState() => _PurchasesPageState();
}

class _PurchasesPageState extends State<PurchasesPage> {
  final CollectionReference productsRef =
      FirebaseFirestore.instance.collection('products');
  final CollectionReference purchasesRef =
      FirebaseFirestore.instance.collection('purchases');
  final CollectionReference movementsRef =
      FirebaseFirestore.instance.collection('stock_movements');

  List<Map<String, dynamic>> lines = [];

  double _calculateTotal() =>
      lines.fold(0.0, (t, e) => t + ((e['price'] ?? 0.0) * (e['qty'] ?? 1)));

  Future<void> _addLineSheet() async {
    final prodSnap = await productsRef.orderBy('name').get();
    final prodList = prodSnap.docs;
    String? selectedId;
    int qty = 1;

    if (!mounted) return;

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
                        const Text('Adicionar Produto',
                            style: TextStyle(
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
                        Text('Selecione o Produto',
                            style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Colors.grey[700])),
                        const SizedBox(height: 12),
                        Container(
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey.shade300),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: DropdownButton<String>(
                            isExpanded: true,
                            underline: const SizedBox(),
                            value: selectedId,
                            hint: const Text('Escolha o produto'),
                            items: prodList.map((d) {
                              final data =
                                  (d.data() as Map<String, dynamic>?) ?? {};
                              return DropdownMenuItem(
                                value: d.id,
                                child: Text('${data['name'] ?? '-'}'),
                              );
                            }).toList(),
                            onChanged: (v) =>
                                setStateLocal(() => selectedId = v),
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
                            borderRadius: BorderRadius.circular(10),
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
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10)),
                            ),
                            onPressed: () {
                              if (selectedId != null && qty > 0) {
                                final p = prodList
                                    .firstWhere((d) => d.id == selectedId);
                                final data = p.data() as Map<String, dynamic>;
                                lines.add({
                                  'productId': selectedId,
                                  'name': data['name'],
                                  'qty': qty,
                                  'price': data['cost'] ?? 0.0,
                                });
                                Navigator.pop(ctx);
                                setState(() {});
                              }
                            },
                            child: const Text('Adicionar',
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

  Future<void> _receivePurchase() async {
    if (lines.isEmpty) return;

    try {
      final purchaseDoc = purchasesRef.doc();
      final createdAt = FieldValue.serverTimestamp();

      for (final line in lines) {
        final pid = line['productId'] as String;
        final qty = line['qty'] as int;
        final prodDoc = productsRef.doc(pid);

        await FirebaseFirestore.instance.runTransaction((tx) async {
          final snap = await tx.get(prodDoc);
          if (!snap.exists) throw Exception('Produto não encontrado');
          final map = (snap.data() as Map<String, dynamic>?) ?? {};
          final cur = (map['qty'] ?? 0) as int;
          final newQty = cur + qty;
          tx.update(prodDoc, {'qty': newQty});
          final mv = movementsRef.doc();
          tx.set(mv, {
            'productId': pid,
            'delta': qty,
            'type': 'purchase',
            'refId': purchaseDoc.id,
            'created_at': FieldValue.serverTimestamp(),
          });
        });
      }

      await purchaseDoc.set({
        'items': lines,
        'status': 'received',
        'created_at': createdAt,
      });

      setState(() => lines.clear());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Entrada aplicada com sucesso'),
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
    final isMobile = MediaQuery.of(context).size.width < 768;

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FD),
      appBar: AppBar(
        title: const Text('Entradas e Compras',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        backgroundColor: AppColors.primaryPurple,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: isMobile ? _buildMobileLayout() : _buildDesktopLayout(),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (lines.isNotEmpty)
            FloatingActionButton(
              heroTag: 'receive',
              backgroundColor: Colors.green.shade600,
              onPressed: _receivePurchase,
              tooltip: 'Receber compra',
              child: const Icon(Icons.check_circle),
            ),
          if (lines.isNotEmpty) const SizedBox(height: 12),
          FloatingActionButton(
            heroTag: 'add',
            backgroundColor: AppColors.primaryPurple,
            foregroundColor: Colors.white,
            onPressed: _addLineSheet,
            tooltip: 'Adicionar produto',
            child: const Icon(Icons.add),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileLayout() {
    return SingleChildScrollView(
      child: Column(
        children: [
          if (lines.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Entrada Atual',
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Colors.grey[800])),
                  const SizedBox(height: 12),
                  _buildCurrentPurchase(),
                ],
              ),
            ),
            const Divider(height: 1),
          ],
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Histórico',
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Colors.grey[800])),
                const SizedBox(height: 12),
                _buildPurchasesHistory(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDesktopLayout() {
    return Row(
      children: [
        Expanded(
          flex: 1,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Entrada Atual',
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: Colors.grey[800])),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
              if (lines.isEmpty)
                Expanded(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.shopping_cart_outlined,
                            size: 48, color: Colors.grey[300]),
                        const SizedBox(height: 12),
                        Text('Nenhum item',
                            style: TextStyle(color: Colors.grey[600])),
                      ],
                    ),
                  ),
                )
              else
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: _buildCurrentPurchase(),
                  ),
                ),
            ],
          ),
        ),
        Container(width: 1, color: Colors.grey.shade200),
        Expanded(
          flex: 1,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text('Histórico',
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Colors.grey[800])),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _buildPurchasesHistory(),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCurrentPurchase() {
    return Column(
      children: [
        Expanded(
          child: ListView.builder(
            itemCount: lines.length,
            itemBuilder: (context, i) {
              final line = lines[i];
              final price = ((line['price'] ?? 0) as num).toStringAsFixed(2);
              final subtotal = ((line['price'] ?? 0.0) * (line['qty'] ?? 1))
                  .toStringAsFixed(2);

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
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: Colors.blue.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.shopping_bag_outlined,
                            color: Colors.blue, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(line['name'],
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold, fontSize: 13)),
                            const SizedBox(height: 4),
                            Text('${line['qty']}x R\$ $price',
                                style: TextStyle(
                                    fontSize: 12, color: Colors.grey[600])),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.blue.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color: Colors.blue.withValues(alpha: 0.2)),
                        ),
                        child: Text('R\$ $subtotal',
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.blue[700],
                                fontSize: 11)),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: () => setState(() => lines.removeAt(i)),
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: Colors.red.withValues(alpha: 0.05),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(Icons.close,
                              size: 16, color: Colors.red.shade400),
                        ),
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
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Total:',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
              Text('R\$ ${_calculateTotal().toStringAsFixed(2)}',
                  style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                      color: Colors.blue)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPurchasesHistory() {
    return StreamBuilder<QuerySnapshot>(
      stream: purchasesRef
          .orderBy('created_at', descending: true)
          .limit(50)
          .snapshots(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snap.data!.docs;

        if (docs.isEmpty) {
          return Center(
            child: Text('Nenhuma compra registrada',
                style: TextStyle(color: Colors.grey[600])),
          );
        }

        return ListView.builder(
          itemCount: docs.length,
          itemBuilder: (context, i) {
            final d = docs[i];
            final data = d.data() as Map<String, dynamic>;
            final items = (data['items'] as List<dynamic>?) ?? [];
            final timestamp = (data['created_at'] as Timestamp?)?.toDate();
            final dateStr =
                timestamp != null ? '${timestamp.day}/${timestamp.month}' : '-';

            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.grey.shade100, width: 1),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: ExpansionTile(
                  shape: const RoundedRectangleBorder(side: BorderSide.none),
                  collapsedShape:
                      const RoundedRectangleBorder(side: BorderSide.none),
                  title: Text('Compra ${d.id.substring(0, 8)}',
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 13)),
                  subtitle: Text('$dateStr • ${items.length} itens',
                      style: const TextStyle(fontSize: 12)),
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: items.map((item) {
                          final i = item as Map<String, dynamic>;
                          final price =
                              ((i['price'] ?? 0) as num).toStringAsFixed(2);
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text('${i['name']}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 12)),
                                ),
                                Text('${i['qty']}x R\$ $price',
                                    style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500)),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}
