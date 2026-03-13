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
    return Theme(
      data: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0F1117),
        cardColor: const Color(0xFF1A1D27),
      ),
      child: Column(
        children: [
          // Search Bar
          Padding(
            padding: const EdgeInsets.all(24.0),
            child: TextField(
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Buscar por nome, slug ou plano...',
                hintStyle: const TextStyle(color: Colors.grey),
                prefixIcon: const Icon(Icons.search, color: Color(0xFF4F8EF7)),
                filled: true,
                fillColor: const Color(0xFF1A1D27),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: Colors.white.withOpacity(0.06)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: Colors.white.withOpacity(0.06)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: Color(0xFF4F8EF7)),
                ),
              ),
              onChanged: (value) => setState(() => _searchQuery = value),
            ),
          ),
  
          // Shops List
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance.collection('shops').orderBy('nome').snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
  
                var shops = snapshot.data!.docs;
                if (_searchQuery.isNotEmpty) {
                  shops = shops.where((doc) {
                    final data = doc.data() as Map<String, dynamic>;
                    final nome = (data['nome'] ?? '').toString().toLowerCase();
                    final slug = (data['slug'] ?? '').toString().toLowerCase();
                    final plan = (data['plan'] ?? '').toString().toLowerCase();
                    final query = _searchQuery.toLowerCase();
                    return nome.contains(query) || slug.contains(query) || plan.contains(query);
                  }).toList();
                }
  
                return Container(
                  margin: const EdgeInsets.symmetric(horizontal: 24),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A1D27),
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                    border: Border.all(color: Colors.white.withOpacity(0.04)),
                  ),
                  child: ListView.separated(
                    itemCount: shops.length,
                    separatorBuilder: (context, index) => Divider(color: Colors.white.withOpacity(0.04), height: 1),
                    itemBuilder: (context, index) {
                      final doc = shops[index];
                      final data = doc.data() as Map<String, dynamic>;
                      final nome = data['nome'] ?? 'Sem nome';
                      final slug = data['slug'] ?? '';
                      final plan = (data['plan'] ?? 'free').toString();
                      final isTrial = data['trial_active'] == true;
                      final photoUrl = data['logoUrl'];
                      final boostExpires = data['boost_expires_at'] as Timestamp?;
                      final isBoosted = boostExpires != null && boostExpires.toDate().isAfter(DateTime.now());
  
                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                        leading: CircleAvatar(
                          backgroundColor: const Color(0xFF4F8EF7).withOpacity(0.1),
                          backgroundImage: photoUrl != null ? NetworkImage(photoUrl) : null,
                          child: photoUrl == null ? const Icon(Icons.storefront_rounded, color: Color(0xFF4F8EF7)) : null,
                        ),
                        title: Row(
                          children: [
                            Text(nome, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                            if (isBoosted) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.amber.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(color: Colors.amber.withOpacity(0.3)),
                                ),
                                child: const Text(
                                  'BOOST',
                                  style: TextStyle(color: Colors.amber, fontSize: 8, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ],
                          ],
                        ),
                        subtitle: Text('/$slug', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: (plan != 'free')
                                    ? const Color(0xFF22C55E).withOpacity(0.1)
                                    : Colors.white.withOpacity(0.05),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                isTrial ? 'TRIAL' : plan.toUpperCase(),
                                style: TextStyle(
                                  color: (plan != 'free') ? const Color(0xFF22C55E) : Colors.grey,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            PopupMenuButton<String>(
                              icon: const Icon(Icons.more_vert, color: Colors.grey),
                              onSelected: (value) {
                                if (value == 'edit') _editShop(doc);
                                if (value == 'boost') _addBoost(doc);
                                if (value == 'plan') _changePlan(doc);
                                if (value == 'trial') _liberarTrial(doc);
                                if (value == 'delete') _deleteShop(doc);
                              },
                              itemBuilder: (context) => [
                                const PopupMenuItem(value: 'edit', child: Text('Editar')),
                                const PopupMenuItem(value: 'trial', child: Text('Liberar Trial Customizado')),
                                const PopupMenuItem(value: 'boost', child: Text('Adicionar Boost')),
                                const PopupMenuItem(value: 'plan', child: Text('Alterar Plano')),
                                const PopupMenuItem(value: 'delete', child: Text('Excluir Loja', style: TextStyle(color: Colors.red))),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
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
                DropdownMenuItem(value: 'start', child: Text('Start')),
                DropdownMenuItem(value: 'plus', child: Text('Plus')),
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
                'trial_active': false,
                'subscription': null,
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

  Future<void> _deleteShop(QueryDocumentSnapshot doc) async {
    final data = doc.data() as Map<String, dynamic>;
    final nome = data['nome'] ?? 'este negócio';
    
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Excluir Negócio?'),
        content: Text('Tem certeza que deseja excluir permanetemente o negócio "$nome"? Esta ação não pode ser desfeita.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await FirebaseFirestore.instance.collection('shops').doc(doc.id).delete();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Negócio excluído com sucesso.')),
        );
      }
    }
  }

  Future<void> _liberarTrial(QueryDocumentSnapshot doc) async {
    String? selectedPlan = 'start';
    String? selectedDuration = '30';

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Liberar Trial Customizado'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Escolha o plano e a duração do teste gratuito.'),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: selectedPlan,
              items: const [
                DropdownMenuItem(value: 'start', child: Text('Start')),
                DropdownMenuItem(value: 'plus', child: Text('Plus')),
                DropdownMenuItem(value: 'pro', child: Text('Pro')),
              ],
              onChanged: (value) => selectedPlan = value,
              decoration: const InputDecoration(labelText: 'Plano'),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: selectedDuration,
              items: const [
                DropdownMenuItem(value: '7', child: Text('7 dias')),
                DropdownMenuItem(value: '15', child: Text('15 dias')),
                DropdownMenuItem(value: '30', child: Text('30 dias (1 mês)')),
                DropdownMenuItem(value: '60', child: Text('60 dias (2 meses)')),
                DropdownMenuItem(value: '90', child: Text('90 dias (3 meses)')),
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
              final endDate = DateTime.now().add(Duration(days: days));

              await FirebaseFirestore.instance
                  .collection('shops')
                  .doc(doc.id)
                  .update({
                'plan': selectedPlan,
                'trial_active': true,
                'trial_plan': selectedPlan,
                'trial_end_date': Timestamp.fromDate(endDate),
                'trial_used': true,
                'subscription': null,
              });

              if (context.mounted) Navigator.pop(context);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                      content: Text(
                          'Trial de $days dias do plano ${selectedPlan!.toUpperCase()} liberado!')),
                );
              }
            },
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );
  }
}
