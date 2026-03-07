import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../core/theme/app_colors.dart';

class PlansPage extends StatefulWidget {
  const PlansPage({super.key});

  @override
  State<PlansPage> createState() => _PlansPageState();
}

class _PlansPageState extends State<PlansPage> {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  bool _isAdmin = false;

  @override
  void initState() {
    super.initState();
    _checkAdmin();
  }

  Future<void> _checkAdmin() async {
    if (uid == null) return;
    final doc =
        await FirebaseFirestore.instance.collection('users').doc(uid).get();
    final data = doc.exists ? doc.data() : null;
    final roles =
        (data?['roles'] as List<dynamic>?)?.map((e) => e.toString()).toList() ??
            [];
    setState(() {
      _isAdmin = roles.contains('admin') ||
          roles.contains('admin_dev') ||
          (data?['is_admin_dev'] == true);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_isAdmin) {
      return Scaffold(
        appBar: AppBar(title: const Text('Planos')),
        body: const Center(child: Text('Acesso restrito')),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Gerenciar Planos')),
      body: Padding(
        padding: const EdgeInsets.all(12.0),
        child: StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('plans')
              .orderBy('price_month')
              .snapshots(),
          builder: (context, snap) {
            if (!snap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final docs = snap.data!.docs;
            // collect feature universe
            final Set<String> allFeatures = {};
            for (final d in docs) {
              final f = List<String>.from(
                  (d.data() as Map<String, dynamic>)['features'] ?? []);
              allFeatures.addAll(f);
            }
            final featuresList = allFeatures.toList()..sort();
            return ListView(
              children: docs.map((d) {
                final data = d.data() as Map<String, dynamic>;
                final planId = d.id;
                final planName = data['name'] ?? planId;
                final price = data['price_month']?.toString() ?? '0';
                final features = List<String>.from(data['features'] ?? []);
                return Card(
                  margin: const EdgeInsets.symmetric(vertical: 8),
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                                child: Text('$planName ($planId)',
                                    style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold))),
                            Text('R\$ $price',
                                style: const TextStyle(fontSize: 16)),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          children: featuresList.map((feature) {
                            final available = features.contains(feature);
                            return Opacity(
                              opacity: available ? 1.0 : 0.45,
                              child: FilterChip(
                                label: Text(feature),
                                selected: available,
                                onSelected: (sel) async {
                                  // toggle feature in plan doc
                                  final ref = FirebaseFirestore.instance
                                      .collection('plans')
                                      .doc(planId);
                                  if (sel) {
                                    await ref.update({
                                      'features':
                                          FieldValue.arrayUnion([feature])
                                    });
                                  } else {
                                    await ref.update({
                                      'features':
                                          FieldValue.arrayRemove([feature])
                                    });
                                  }
                                },
                                selectedColor: AppColors.primaryPurple
                                    .withValues(alpha: 0.15),
                                checkmarkColor: AppColors.primaryPurple,
                              ),
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 8),
                        Text(data['description'] ?? '',
                            style: const TextStyle(color: Colors.grey)),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            TextButton.icon(
                              onPressed: () async {
                                // quick edit price
                                final ctrl = TextEditingController(text: price);
                                final ok = await showDialog<bool>(
                                    context: context,
                                    builder: (_) {
                                      return AlertDialog(
                                        title:
                                            const Text('Editar preço mensal'),
                                        content: TextField(
                                            controller: ctrl,
                                            keyboardType: TextInputType.number),
                                        actions: [
                                          TextButton(
                                              onPressed: () =>
                                                  Navigator.pop(context, false),
                                              child: const Text('Cancelar')),
                                          ElevatedButton(
                                              onPressed: () =>
                                                  Navigator.pop(context, true),
                                              child: const Text('Salvar')),
                                        ],
                                      );
                                    });
                                if (ok == true) {
                                  final newPrice = double.tryParse(
                                          ctrl.text.replaceAll(',', '.')) ??
                                      0;
                                  await FirebaseFirestore.instance
                                      .collection('plans')
                                      .doc(planId)
                                      .update({'price_month': newPrice});
                                }
                              },
                              icon: const Icon(Icons.edit),
                              label: const Text('Editar preço'),
                            ),
                            const SizedBox(width: 12),
                            TextButton.icon(
                              onPressed: () async {
                                final confirm = await showDialog<bool>(
                                    context: context,
                                    builder: (_) {
                                      return AlertDialog(
                                        title: const Text('Confirmar excluir'),
                                        content: Text('Excluir plano $planId?'),
                                        actions: [
                                          TextButton(
                                              onPressed: () =>
                                                  Navigator.pop(context, false),
                                              child: const Text('Cancelar')),
                                          ElevatedButton(
                                              onPressed: () =>
                                                  Navigator.pop(context, true),
                                              child: const Text('Excluir')),
                                        ],
                                      );
                                    });
                                if (confirm == true) {
                                  await FirebaseFirestore.instance
                                      .collection('plans')
                                      .doc(planId)
                                      .delete();
                                }
                              },
                              icon: const Icon(Icons.delete),
                              label: const Text('Excluir plano'),
                            ),
                          ],
                        )
                      ],
                    ),
                  ),
                );
              }).toList(),
            );
          },
        ),
      ),
    );
  }
}
