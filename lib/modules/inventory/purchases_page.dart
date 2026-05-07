import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/theme/app_colors.dart';
import '../../core/services/session_service.dart';

class PurchasesPage extends StatefulWidget {
  const PurchasesPage({super.key});

  @override
  State<PurchasesPage> createState() => _PurchasesPageState();
}

class _PurchasesPageState extends State<PurchasesPage> {
  final productsRef = Supabase.instance.client.from('products');
  final purchasesRef = Supabase.instance.client.from('purchases');
  
  List<Map<String, dynamic>> products = [];
  List<Map<String, dynamic>> lines = [];
  bool _isLoadingProducts = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadProducts();
  }

  Future<void> _loadProducts() async {
    try {
      final shopId = await SessionService.getShopId();
      if (shopId == null) return;

      final data = await productsRef.select().eq('shop_id', shopId);
      setState(() {
        products = List<Map<String, dynamic>>.from(data);
        _isLoadingProducts = false;
      });
    } catch (e) {
      debugPrint('Erro ao carregar produtos: $e');
      setState(() => _isLoadingProducts = false);
    }
  }

  void _addLine() {
    _showProductPicker();
  }

  void _showProductPicker() {
    String search = '';
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Container(
          height: MediaQuery.of(ctx).size.height * 0.80,
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(top: 12, bottom: 8),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                child: Row(
                  children: [
                    const Text(
                      'Selecionar Produto',
                      style: TextStyle(
                          fontSize: 17, fontWeight: FontWeight.bold),
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: () => Navigator.pop(ctx),
                      icon: Icon(Icons.close, color: Colors.grey.shade600),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  autofocus: true,
                  decoration: InputDecoration(
                    hintText: 'Buscar produto...',
                    prefixIcon:
                        const Icon(Icons.search, color: Colors.grey),
                    filled: true,
                    fillColor: const Color(0xFFF8F9FD),
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
                      borderSide: const BorderSide(
                          color: AppColors.primaryPurple, width: 1.5),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                  ),
                  onChanged: (v) => setSheet(() => search = v.toLowerCase()),
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: products.isEmpty
                    ? Center(
                        child: Text(
                          'Nenhum produto cadastrado',
                          style: TextStyle(color: Colors.grey.shade500),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 4),
                        itemCount: products
                            .where((p) => search.isEmpty ||
                                (p['name'] ?? '')
                                    .toLowerCase()
                                    .contains(search))
                            .length,
                        itemBuilder: (context, i) {
                          final filtered = products
                              .where((p) => search.isEmpty ||
                                  (p['name'] ?? '')
                                      .toLowerCase()
                                      .contains(search))
                              .toList();
                          final p = filtered[i];
                          final color = p['color'] as String?;
                          final weight = p['weight'];
                          final unit =
                              (p['weight_unit'] as String?) ?? 'g';
                          final stock = (p['stock_quantity'] ??
                              p['qty'] ??
                              0) as num;
                          final price = (p['price'] ?? 0.0) as num;

                          return InkWell(
                            onTap: () {
                              Navigator.pop(ctx);
                              setState(() {
                                lines.add({
                                  'productId': p['id'],
                                  'name': p['name'] ?? '',
                                  'color': color,
                                  'weight': weight,
                                  'weight_unit': unit,
                                  'qty': 1,
                                  'price': price.toDouble(),
                                });
                              });
                            },
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF8F9FD),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                    color: Colors.grey.shade100),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 40,
                                    height: 40,
                                    decoration: BoxDecoration(
                                      color: AppColors.primaryPurple
                                          .withValues(alpha: 0.1),
                                      borderRadius:
                                          BorderRadius.circular(10),
                                    ),
                                    child: const Icon(
                                        Icons.inventory_2_outlined,
                                        color: AppColors.primaryPurple,
                                        size: 20),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          p['name'] ?? '',
                                          style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 14),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          [
                                            if (color != null &&
                                                color.isNotEmpty)
                                              'Cor: $color',
                                            if (weight != null)
                                              '$weight$unit',
                                            'Estoque: $stock',
                                          ].join(' • '),
                                          style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.grey.shade600),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Text(
                                    'R\$ ${price.toStringAsFixed(2)}',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: AppColors.primaryPurple,
                                        fontSize: 13),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  double _calculateTotal() {
    return lines.fold(0, (sum, item) => sum + ((item['price'] ?? 0.0) * (item['qty'] ?? 1)));
  }

  Future<void> _finalizePurchase() async {
    if (lines.isEmpty) return;
    if (lines.any((l) => l['productId'] == null)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecione todos os produtos')),
      );
      return;
    }

    final shopId = await SessionService.getShopId();
    if (shopId == null) return;

    setState(() => _isSaving = true);

    try {
      final supabase = Supabase.instance.client;

      // Criar a compra
      final purchaseData = {
        'shop_id': shopId,
        'items': lines,
        'total': _calculateTotal(),
        'created_at': DateTime.now().toIso8601String(),
      };

      final purchaseResponse = await supabase.from('purchases').insert(purchaseData).select().single();
      final purchaseId = purchaseResponse['id'];

      // Atualizar estoque e criar movimentações
      for (var item in lines) {
        final pDoc = await productsRef.select().eq('id', item['productId']).single();
        final currentQty = ((pDoc['stock_quantity'] ?? pDoc['qty'] ?? 0) as num).toInt();
        final newQty = currentQty + (item['qty'] as int);

        await productsRef.update({'stock_quantity': newQty, 'qty': newQty}).eq('id', item['productId']);

        await supabase.from('stock_movements').insert({
          'shop_id': shopId,
          'product_id': item['productId'],
          'type': 'purchase',
          'delta': item['qty'],
          'ref_id': purchaseId,
          'created_at': DateTime.now().toIso8601String(),
        });
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Compra registrada e estoque atualizado!')),
        );
        setState(() {
          lines.clear();
          _isSaving = false;
        });
      }
    } catch (e) {
      debugPrint('Erro ao salvar compra: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro: $e')),
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
        title: const Text('Compras',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        backgroundColor: AppColors.primaryPurple,
        foregroundColor: Colors.white,
        elevation: 0,
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
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Itens da Compra',
                  style:
                      TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ElevatedButton.icon(
                onPressed: _addLine,
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Adicionar'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryPurple,
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
              ),
            ],
          ),
        ),
        Expanded(child: _buildLinesList(isMobile: true)),
        Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border(top: BorderSide(color: Colors.grey.shade200)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 10,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          child: Row(
            children: [
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
                          fontSize: 18,
                          color: AppColors.primaryPurple),
                    ),
                  ],
                ),
              ),
              ElevatedButton(
                onPressed:
                    (_isSaving || lines.isEmpty) ? null : _finalizePurchase,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryPurple,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 24, vertical: 14),
                ),
                child: _isSaving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2))
                    : const Text('Salvar',
                        style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      ],
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
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Itens da Compra',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 16)),
                    ElevatedButton.icon(
                      onPressed: _addLine,
                      icon: const Icon(Icons.add),
                      label: const Text('Adicionar Item'),
                      style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primaryPurple,
                          foregroundColor: Colors.white),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Expanded(child: _buildLinesList()),
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
                child: Text('Histórico Recente',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              ),
              Expanded(child: _buildPurchasesHistory()),
              Padding(
                padding: const EdgeInsets.all(20),
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16)),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Total:',
                              style: TextStyle(fontWeight: FontWeight.bold)),
                          Text(
                              'R\$ ${_calculateTotal().toStringAsFixed(2)}',
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 20,
                                  color: Colors.blue)),
                        ],
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton(
                          onPressed: (_isSaving || lines.isEmpty)
                              ? null
                              : _finalizePurchase,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                          child: _isSaving
                              ? const CircularProgressIndicator(
                                  color: Colors.white)
                              : const Text('SALVAR ENTRADA',
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold)),
                        ),
                      ),
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

  Widget _buildLinesList({bool isMobile = false}) {
    if (_isLoadingProducts) {
      return const Center(child: CircularProgressIndicator());
    }

    if (lines.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add_shopping_cart_outlined,
                size: 64, color: Colors.grey[300]),
            const SizedBox(height: 16),
            Text(
              'Toque em "Adicionar" para selecionar um produto',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[500], fontSize: 14),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: lines.length,
      itemBuilder: (context, i) {
        final line = lines[i];
        final qty = (line['qty'] as int? ?? 1);
        final price = (line['price'] as double? ?? 0.0);
        final subtotal = (qty * price).toStringAsFixed(2);
        final color = line['color'] as String?;
        final weight = line['weight'];
        final unit = (line['weight_unit'] as String?) ?? 'g';
        final details = [
          if (color != null && color.isNotEmpty) 'Cor: $color',
          if (weight != null) '$weight$unit',
        ].join(' • ');

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding:
                    const EdgeInsets.fromLTRB(12, 12, 8, 0),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: AppColors.primaryPurple.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: const Icon(Icons.inventory_2_outlined,
                          color: AppColors.primaryPurple, size: 18),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            line['name'] ?? 'Produto',
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 14),
                          ),
                          if (details.isNotEmpty)
                            Text(
                              details,
                              style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade500),
                            ),
                        ],
                      ),
                    ),
                    TextButton(
                      onPressed: () {
                        setState(() => lines.removeAt(i));
                        _showProductPicker();
                      },
                      style: TextButton.styleFrom(
                          padding: EdgeInsets.zero,
                          minimumSize: const Size(0, 0),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                      child: Text('Trocar',
                          style: TextStyle(
                              color: Colors.grey.shade500, fontSize: 12)),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline,
                          color: Colors.red, size: 20),
                      padding: const EdgeInsets.all(4),
                      constraints: const BoxConstraints(),
                      onPressed: () => setState(() => lines.removeAt(i)),
                    ),
                  ],
                ),
              ),
              const Divider(height: 16, indent: 12, endIndent: 12),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Quantidade',
                              style: TextStyle(
                                  fontSize: 11, color: Colors.grey.shade500)),
                          const SizedBox(height: 4),
                          TextFormField(
                            key: ValueKey('qty_$i'),
                            initialValue: qty.toString(),
                            keyboardType: TextInputType.number,
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 15),
                            decoration: InputDecoration(
                              isDense: true,
                              filled: true,
                              fillColor: const Color(0xFFF8F9FD),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide:
                                    BorderSide(color: Colors.grey.shade200),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide:
                                    BorderSide(color: Colors.grey.shade200),
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 8),
                            ),
                            onChanged: (v) => setState(
                                () => lines[i]['qty'] = int.tryParse(v) ?? 1),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Preço unit. (R\$)',
                              style: TextStyle(
                                  fontSize: 11, color: Colors.grey.shade500)),
                          const SizedBox(height: 4),
                          TextFormField(
                            key: ValueKey('price_$i'),
                            initialValue: price.toStringAsFixed(2),
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 15),
                            decoration: InputDecoration(
                              isDense: true,
                              filled: true,
                              fillColor: const Color(0xFFF8F9FD),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide:
                                    BorderSide(color: Colors.grey.shade200),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide:
                                    BorderSide(color: Colors.grey.shade200),
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 8),
                            ),
                            onChanged: (v) => setState(() =>
                                lines[i]['price'] =
                                    double.tryParse(v.replaceAll(',', '.')) ??
                                        0.0),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text('Subtotal',
                            style: TextStyle(
                                fontSize: 11, color: Colors.grey.shade500)),
                        const SizedBox(height: 6),
                        Text(
                          'R\$ $subtotal',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                              color: AppColors.primaryPurple),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPurchasesHistory() {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: purchasesRef.stream(primaryKey: ['id']).limit(50),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snap.data!;

        if (docs.isEmpty) {
          return Center(
            child: Text('Nenhuma compra registrada',
                style: TextStyle(color: Colors.grey[600])),
          );
        }

        // Ordenar por data manualmente se o stream não suportar orderBy na versão atual
        final sortedDocs = List<Map<String, dynamic>>.from(docs);
        sortedDocs.sort((a, b) => (b['created_at'] ?? '').toString().compareTo((a['created_at'] ?? '')));

        return ListView.builder(
          itemCount: sortedDocs.length,
          itemBuilder: (context, i) {
            final data = sortedDocs[i];
            final items = (data['items'] as List<dynamic>?) ?? [];
            final dateStr = (data['created_at'] ?? '').toString();
            final dateDisplay = dateStr.isNotEmpty ? '${dateStr.substring(8, 10)}/${dateStr.substring(5, 7)}' : '-';

            return Container(
              margin: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade100),
              ),
              child: ExpansionTile(
                title: Text('Compra #${data['id'].toString().substring(0, 5)}',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                subtitle: Text('$dateDisplay • ${items.length} itens'),
                children: [
                   Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      children: items.map((item) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(item['name'] ?? ''),
                              Text('${item['qty']}x R\$ ${item['price']}'),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  )
                ],
              ),
            );
          },
        );
      },
    );
  }
}
