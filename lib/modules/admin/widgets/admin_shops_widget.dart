import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AdminShopsWidget extends StatefulWidget {
  const AdminShopsWidget({super.key});

  @override
  State<AdminShopsWidget> createState() => _AdminShopsWidgetState();
}

class _AdminShopsWidgetState extends State<AdminShopsWidget> {
  String _searchQuery = '';

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Search Bar
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: TextField(
            decoration: InputDecoration(
              hintText: 'Buscar negócio...',
              prefixIcon: const Icon(Icons.search),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onChanged: (value) => setState(() => _searchQuery = value),
          ),
        ),

        // Shops List
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('shops')
                .orderBy('nome')
                .snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              var shops = snapshot.data!.docs;

              // Apply search filter
              if (_searchQuery.isNotEmpty) {
                shops = shops.where((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  final nome = (data['nome'] ?? '').toString().toLowerCase();
                  final category =
                      (data['categoria'] ?? '').toString().toLowerCase();
                  final query = _searchQuery.toLowerCase();
                  return nome.contains(query) || category.contains(query);
                }).toList();
              }

              if (shops.isEmpty) {
                return const Center(child: Text('Nenhum negócio encontrado'));
              }

              return ListView.separated(
                itemCount: shops.length,
                separatorBuilder: (context, index) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final doc = shops[index];
                  final data = doc.data() as Map<String, dynamic>;

                  final nome = data['nome'] ?? 'Sem nome';
                  final categoria = data['categoria'] ?? '';
                  final plan = data['plan'] ?? 'free';
                  final logoUrl = data['logoUrl'];
                  final boostExpires = data['boost_expires_at'] as Timestamp?;
                  final isBoosted = boostExpires != null &&
                      boostExpires.toDate().isAfter(DateTime.now());

                  return ListTile(
                    leading: CircleAvatar(
                      backgroundImage:
                          logoUrl != null ? NetworkImage(logoUrl) : null,
                      child: logoUrl == null ? const Icon(Icons.store) : null,
                    ),
                    title: Row(
                      children: [
                        Text(nome),
                        if (isBoosted) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.amber,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              'BOOST',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    subtitle:
                        Text('$categoria • Plano: ${plan.toUpperCase()}'),
                    trailing: PopupMenuButton<String>(
                      icon: const Icon(Icons.more_vert),
                      onSelected: (value) {
                        if (value == 'edit') {
                          _editShop(doc);
                        } else if (value == 'boost') {
                          _addBoost(doc);
                        } else if (value == 'plan') {
                          _changePlan(doc);
                        }
                      },
                      itemBuilder: (context) => [
                        const PopupMenuItem(
                          value: 'edit',
                          child: Row(
                            children: [
                              Icon(Icons.edit, size: 18),
                              SizedBox(width: 8),
                              Text('Editar'),
                            ],
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'boost',
                          child: Row(
                            children: [
                              Icon(Icons.rocket_launch, size: 18),
                              SizedBox(width: 8),
                              Text('Adicionar Boost'),
                            ],
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'plan',
                          child: Row(
                            children: [
                              Icon(Icons.upgrade, size: 18),
                              SizedBox(width: 8),
                              Text('Alterar Plano'),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _editShop(QueryDocumentSnapshot doc) async {
    final data = doc.data() as Map<String, dynamic>;
    final nomeController = TextEditingController(text: data['nome'] ?? '');
    final telefoneController =
        TextEditingController(text: data['telefone'] ?? '');

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Editar Negócio'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nomeController,
              decoration: const InputDecoration(labelText: 'Nome'),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: telefoneController,
              decoration: const InputDecoration(labelText: 'Telefone'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () async {
              await FirebaseFirestore.instance
                  .collection('shops')
                  .doc(doc.id)
                  .update({
                'nome': nomeController.text,
                'telefone': telefoneController.text,
              });
              if (context.mounted) Navigator.pop(context);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Negócio atualizado!')),
                );
              }
            },
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
  }

  Future<void> _addBoost(QueryDocumentSnapshot doc) async {
    String? selectedDuration = '7';

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Adicionar Boost'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Selecione a duração do boost:'),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: selectedDuration,
              items: const [
                DropdownMenuItem(value: '7', child: Text('7 dias')),
                DropdownMenuItem(value: '14', child: Text('14 dias')),
                DropdownMenuItem(value: '30', child: Text('30 dias')),
              ],
              onChanged: (value) => selectedDuration = value,
              decoration: const InputDecoration(labelText: 'Duração'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () async {
              final days = int.parse(selectedDuration!);
              final expiresAt = DateTime.now().add(Duration(days: days));

              await FirebaseFirestore.instance
                  .collection('shops')
                  .doc(doc.id)
                  .update({
                'boost_expires_at': Timestamp.fromDate(expiresAt),
                'is_boosted': true,
              });

              if (context.mounted) Navigator.pop(context);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Boost de $days dias adicionado!')),
                );
              }
            },
            child: const Text('Adicionar'),
          ),
        ],
      ),
    );
  }

  Future<void> _changePlan(QueryDocumentSnapshot doc) async {
    final data = doc.data() as Map<String, dynamic>;
    String? selectedPlan = data['plan'] ?? 'free';

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Alterar Plano'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Selecione o novo plano:'),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: selectedPlan,
              items: const [
                DropdownMenuItem(value: 'free', child: Text('Free')),
                DropdownMenuItem(value: 'premium', child: Text('Premium')),
                DropdownMenuItem(value: 'pro', child: Text('Pro')),
              ],
              onChanged: (value) => selectedPlan = value,
              decoration: const InputDecoration(labelText: 'Plano'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () async {
              await FirebaseFirestore.instance
                  .collection('shops')
                  .doc(doc.id)
                  .update({
                'plan': selectedPlan,
                'trial_active': false, // Desativa trial ao mudar manualmente
                'subscription': null, // Limpa assinatura anterior para evitar conflitos
              });

              if (context.mounted) Navigator.pop(context);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                      content: Text(
                          'Plano alterado para ${selectedPlan!.toUpperCase()} e Trial desativado!')),
                );
              }
            },
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
  }
}
