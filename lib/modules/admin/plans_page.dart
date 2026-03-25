import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/theme/app_colors.dart';

class PlansPage extends StatefulWidget {
  const PlansPage({super.key});

  @override
  State<PlansPage> createState() => _PlansPageState();
}

class _PlansPageState extends State<PlansPage> {
  final uid = Supabase.instance.client.auth.currentUser?.id;
  bool _isAdmin = false;

  @override
  void initState() {
    super.initState();
    _checkAdmin();
  }

  Future<void> _checkAdmin() async {
    if (uid == null) return;
    try {
      final doc = await Supabase.instance.client
          .from('users')
          .select('role')
          .eq('id', uid!)
          .maybeSingle();

      if (doc != null) {
        final role = doc['role']?.toString();
        setState(() {
          _isAdmin = role == 'admin' || role == 'master' || role == 'admin_dev';
        });
      }
    } catch (e) {
      debugPrint("Error checking admin status: $e");
    }
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
        child: StreamBuilder<List<Map<String, dynamic>>>(
          stream: Supabase.instance.client
              .from('plans')
              .stream(primaryKey: ['id']).order('price_month'),
          builder: (context, snap) {
            if (!snap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final docs = snap.data!;
            // collect feature universe
            final Set<String> allFeatures = {};
            for (final d in docs) {
              final f = List<String>.from(d['features'] ?? []);
              allFeatures.addAll(f);
            }
            final featuresList = allFeatures.toList()..sort();
            
            return ListView(
              children: docs.map((data) {
                final planId = data['id']?.toString() ?? '';
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
                                  final sup = Supabase.instance.client.from('plans');
                                  if (sel) {
                                    final newF = List<String>.from(features)..add(feature);
                                    await sup.update({'features': newF}).eq('id', planId);
                                  } else {
                                    final newF = List<String>.from(features)..remove(feature);
                                    await sup.update({'features': newF}).eq('id', planId);
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
                                        title: const Text('Editar preço mensal'),
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
                                  await Supabase.instance.client
                                      .from('plans')
                                      .update({'price_month': newPrice})
                                      .eq('id', planId);
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
                                  await Supabase.instance.client
                                      .from('plans')
                                      .delete()
                                      .eq('id', planId);
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
