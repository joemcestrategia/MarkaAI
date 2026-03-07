import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../core/theme/app_colors.dart';
import '../../core/services/session_service.dart';

/// Gestão de estoque (somente donos): produtos (nome, marca, peso, tipo), entrada e saída.
class InventoryPage extends StatefulWidget {
  const InventoryPage({super.key});

  @override
  State<InventoryPage> createState() => _InventoryPageState();
}

class _InventoryPageState extends State<InventoryPage> {
  String? _shopId;

  @override
  void initState() {
    super.initState();
    _loadShop();
  }

  Future<void> _loadShop() async {
    final id = await SessionService.getShopId();
    if (mounted) setState(() => _shopId = id);
  }

  @override
  Widget build(BuildContext context) {
    if (_shopId == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Estoque'),
          backgroundColor: AppColors.primaryPurple,
          foregroundColor: Colors.white,
          bottom: const TabBar(
            labelColor: Colors.white,
            tabs: [Tab(text: 'Produtos'), Tab(text: 'Movimentações')],
          ),
        ),
        body: TabBarView(
          children: [
            _ProductsList(shopId: _shopId!),
            _MovementsList(shopId: _shopId!),
          ],
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: () => _showAddProduct(context),
          backgroundColor: AppColors.primaryPurple,
          foregroundColor: Colors.white,
          child: const Icon(Icons.add),
        ),
      ),
    );
  }

  void _showAddProduct(BuildContext context) {
    final nome = TextEditingController();
    final marca = TextEditingController();
    final peso = TextEditingController();
    final tipo = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cadastrar produto'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                  controller: nome,
                  decoration: const InputDecoration(labelText: 'Nome *')),
              TextField(
                  controller: marca,
                  decoration: const InputDecoration(labelText: 'Marca')),
              TextField(
                  controller: peso,
                  keyboardType: TextInputType.number,
                  decoration:
                      const InputDecoration(labelText: 'Peso (ex: 0.5 kg)')),
              TextField(
                  controller: tipo,
                  decoration: const InputDecoration(
                      labelText: 'Tipo (ex: Shampoo, Tinta)')),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () async {
              if (nome.text.trim().isEmpty) return;
              await FirebaseFirestore.instance.collection('inventory').add({
                'shopId': _shopId,
                'nome': nome.text.trim(),
                'marca': marca.text.trim(),
                'peso': peso.text.trim(),
                'tipo': tipo.text.trim(),
                'quantidade': 0,
                'criado_em': FieldValue.serverTimestamp(),
              });
              if (context.mounted) Navigator.pop(ctx);
            },
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
  }
}

class _ProductsList extends StatelessWidget {
  final String shopId;

  const _ProductsList({required this.shopId});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('inventory')
          .where('shopId', isEqualTo: shopId)
          .orderBy('nome')
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snapshot.data!.docs;
        if (docs.isEmpty) {
          return const Center(
              child: Text('Nenhum produto. Toque em + para cadastrar.'));
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: docs.length,
          itemBuilder: (context, i) {
            final d = docs[i].data() as Map<String, dynamic>;
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                title: Text(d['nome'] ?? ''),
                subtitle: Text(
                    '${d['marca'] ?? ''} • ${d['tipo'] ?? ''} • ${d['peso'] ?? ''}\nEstoque: ${d['quantidade'] ?? 0}'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.add_circle, color: Colors.green),
                      onPressed: () => _movement(context, docs[i].id, true),
                    ),
                    IconButton(
                      icon:
                          const Icon(Icons.remove_circle, color: Colors.orange),
                      onPressed: () => _movement(context, docs[i].id, false),
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

  Future<void> _movement(
      BuildContext context, String productId, bool isEntrada) async {
    final qtdCtrl = TextEditingController(text: '1');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isEntrada ? 'Entrada' : 'Saída'),
        content: TextField(
          controller: qtdCtrl,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Quantidade'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Confirmar')),
        ],
      ),
    );
    if (ok != true) return;
    final qtd = int.tryParse(qtdCtrl.text) ?? 1;
    if (qtd <= 0) return;
    final ref =
        FirebaseFirestore.instance.collection('inventory').doc(productId);
    await FirebaseFirestore.instance.runTransaction((tx) async {
      final snap = await tx.get(ref);
      final current = (snap.data()?['quantidade'] ?? 0) as int;
      final newQty = isEntrada ? current + qtd : current - qtd;
      if (newQty < 0) throw Exception('Estoque insuficiente');
      tx.update(ref, {'quantidade': newQty});
      final movRef =
          FirebaseFirestore.instance.collection('inventory_movements').doc();
      tx.set(movRef, {
        'shopId': shopId,
        'productId': productId,
        'tipo': isEntrada ? 'entrada' : 'saida',
        'quantidade': qtd,
        'quantidade_apos': newQty,
        'criado_em': FieldValue.serverTimestamp(),
        'userId': FirebaseAuth.instance.currentUser?.uid,
      });
    });
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content:
              Text(isEntrada ? 'Entrada registrada' : 'Saída registrada')));
    }
  }
}

class _MovementsList extends StatelessWidget {
  final String shopId;

  const _MovementsList({required this.shopId});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('inventory_movements')
          .where('shopId', isEqualTo: shopId)
          .orderBy('criado_em', descending: true)
          .limit(100)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snapshot.data!.docs;
        if (docs.isEmpty) {
          return const Center(child: Text('Nenhuma movimentação.'));
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: docs.length,
          itemBuilder: (context, i) {
            final d = docs[i].data() as Map<String, dynamic>;
            final tipo = d['tipo'] == 'entrada' ? 'Entrada' : 'Saída';
            final ts = d['criado_em'] as Timestamp?;
            final date =
                ts != null ? '${ts.toDate().day}/${ts.toDate().month}' : '';
            return ListTile(
              leading: CircleAvatar(
                backgroundColor:
                    d['tipo'] == 'entrada' ? Colors.green : Colors.orange,
                child: Icon(
                    d['tipo'] == 'entrada'
                        ? Icons.arrow_downward
                        : Icons.arrow_upward,
                    color: Colors.white),
              ),
              title: Text('$tipo: ${d['quantidade']} un.'),
              subtitle: Text('Estoque após: ${d['quantidade_apos']} • $date'),
            );
          },
        );
      },
    );
  }
}
