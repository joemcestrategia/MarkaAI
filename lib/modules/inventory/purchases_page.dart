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
    setState(() {
      lines.add({
        'productId': null,
        'qty': 1,
        'price': 0.0,
        'name': '',
      });
    });
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
        'shopId': shopId,
        'items': lines,
        'total': _calculateTotal(),
        'created_at': DateTime.now().toIso8601String(),
      };

      final purchaseResponse = await supabase.from('purchases').insert(purchaseData).select().single();
      final purchaseId = purchaseResponse['id'];

      // Atualizar estoque e criar movimentações
      for (var item in lines) {
        final pDoc = await productsRef.select().eq('id', item['productId']).single();
        final currentQty = (pDoc['qty'] ?? 0) as int;

        await productsRef.update({'qty': currentQty + item['qty']}).eq('id', item['productId']);

        await supabase.from('stock_movements').insert({
          'shopId': shopId,
          'productId': item['productId'],
          'type': 'purchase',
          'delta': item['qty'],
          'refId': purchaseId,
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Entradas de Estoque',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        backgroundColor: AppColors.primaryPurple,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Row(
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
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
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
                        color: Colors.white, borderRadius: BorderRadius.circular(16)),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Total:',
                                style: TextStyle(fontWeight: FontWeight.bold)),
                            Text('R\$ ${_calculateTotal().toStringAsFixed(2)}',
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
                            onPressed: (_isSaving || lines.isEmpty) ? null : _finalizePurchase,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                            ),
                            child: _isSaving
                                ? const CircularProgressIndicator(color: Colors.white)
                                : const Text('SALVAR ENTRADA',
                                    style: TextStyle(fontWeight: FontWeight.bold)),
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
      ),
    );
  }

  Widget _buildLinesList() {
    if (_isLoadingProducts) {
      return const Center(child: CircularProgressIndicator());
    }

    return ListView.builder(
      itemCount: lines.length,
      itemBuilder: (context, i) {
        final line = lines[i];
        final subtotal = (line['qty'] * line['price']).toStringAsFixed(2);

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey.shade100),
          ),
          child: Row(
            children: [
              Expanded(
                flex: 3,
                child: DropdownButtonFormField<String>(
                  decoration: const InputDecoration(labelText: 'Produto'),
                  value: line['productId'],
                  items: products.map((p) {
                    return DropdownMenuItem<String>(
                      value: p['id'],
                      child: Text(p['name'] ?? ''),
                    );
                  }).toList(),
                  onChanged: (val) {
                    final p = products.firstWhere((element) => element['id'] == val);
                    setState(() {
                      lines[i]['productId'] = val;
                      lines[i]['name'] = p['name'];
                      // Opcional: sugerir preço de custo se houver
                    });
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  decoration: const InputDecoration(labelText: 'Qtd'),
                  keyboardType: TextInputType.number,
                  initialValue: line['qty'].toString(),
                  onChanged: (v) => setState(() => lines[i]['qty'] = int.tryParse(v) ?? 1),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  decoration: const InputDecoration(labelText: 'Preço Un.'),
                  keyboardType: TextInputType.number,
                  initialValue: line['price'].toString(),
                  onChanged: (v) => setState(() => lines[i]['price'] = double.tryParse(v) ?? 0.0),
                ),
              ),
              const SizedBox(width: 12),
              Text('R\$ $subtotal', style: const TextStyle(fontWeight: FontWeight.bold)),
              IconButton(
                icon: const Icon(Icons.delete, color: Colors.red),
                onPressed: () => setState(() => lines.removeAt(i)),
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
            final dateDisplay = dateStr.isNotEmpty ? dateStr.substring(8, 10) + '/' + dateStr.substring(5, 7) : '-';

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
