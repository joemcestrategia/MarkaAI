// ignore_for_file: use_build_context_synchronously
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../core/theme/app_colors.dart';

class CategoriesPage extends StatefulWidget {
  const CategoriesPage({super.key});

  @override
  State<CategoriesPage> createState() => _CategoriesPageState();
}

class _CategoriesPageState extends State<CategoriesPage> {
  final _ctrl = TextEditingController();

  String _normalize(String s) {
    final map = {
      'á': 'a',
      'Ã ': 'a',
      'ã': 'a',
      'â': 'a',
      'ä': 'a',
      'é': 'e',
      'ê': 'e',
      'í': 'i',
      'ó': 'o',
      'ô': 'o',
      'ú': 'u',
      'ç': 'c'
    };
    var out = s.trim();
    map.forEach((k, v) {
      out = out.replaceAll(k, v);
      out = out.replaceAll(k.toUpperCase(), v.toUpperCase());
    });
    out = out.replaceAll(RegExp(r'\s+'), ' ');
    return out.toLowerCase();
  }

  int _levenshtein(String a, String b) {
    final la = a.length, lb = b.length;
    final dp = List.generate(la + 1, (_) => List<int>.filled(lb + 1, 0));
    for (var i = 0; i <= la; i++) {
      dp[i][0] = i;
    }
    for (var j = 0; j <= lb; j++) {
      dp[0][j] = j;
    }
    for (var i = 1; i <= la; i++) {
      for (var j = 1; j <= lb; j++) {
        final cost = a[i - 1] == b[j - 1] ? 0 : 1;
        dp[i][j] = [dp[i - 1][j] + 1, dp[i][j - 1] + 1, dp[i - 1][j - 1] + cost]
            .reduce((v, e) => v < e ? v : e);
      }
    }
    return dp[la][lb];
  }

  Future<void> _createCategory() async {
    final name = _ctrl.text.trim();
    if (name.isEmpty) return;
    final nl = _normalize(name);
    final q = await FirebaseFirestore.instance
        .collection('service_categories')
        .where('name_lower', isEqualTo: nl)
        .limit(1)
        .get();
    if (q.docs.isNotEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Categoria já existe')));
      }
      return;
    }
    await FirebaseFirestore.instance.collection('service_categories').add({
      'name': name,
      'name_lower': nl,
      'createdAt': FieldValue.serverTimestamp()
    });
    _ctrl.clear();
  }

  Future<void> _findDuplicates() async {
    final snap =
        await FirebaseFirestore.instance.collection('service_categories').get();
    final docs = snap.docs;
    // first, exact-normalized duplicates
    final Map<String, List<QueryDocumentSnapshot>> groups = {};
    for (final d in docs) {
      final m = d.data() as Map<String, dynamic>?;
      final nl = m?['name_lower'] ?? '';
      groups.putIfAbsent(nl, () => []).add(d);
    }
    final exactDup = groups.values.where((g) => g.length > 1).toList();

    // then fuzzy suggestions via Levenshtein on normalized names
    final items = docs.map((d) {
      final m = d.data() as Map<String, dynamic>?;
      return {'doc': d, 'name': m?['name'] ?? '', 'nl': m?['name_lower'] ?? ''};
    }).toList();
    final fuzzyPairs = <List<QueryDocumentSnapshot>>[];
    for (var i = 0; i < items.length; i++) {
      for (var j = i + 1; j < items.length; j++) {
        final a = items[i]['nl'] as String;
        final b = items[j]['nl'] as String;
        if (a.isEmpty || b.isEmpty) continue;
        final dist = _levenshtein(a, b);
        final maxL = a.length > b.length ? a.length : b.length;
        final rel = maxL == 0 ? 0.0 : dist / maxL;
        if (dist <= 2 || rel <= 0.25) {
          fuzzyPairs.add([
            items[i]['doc'] as QueryDocumentSnapshot,
            items[j]['doc'] as QueryDocumentSnapshot
          ]);
        }
      }
    }

    if (exactDup.isEmpty && fuzzyPairs.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Nenhuma duplicata ou sugestão fuzzy encontrada')));
      }
      return;
    }

    if (!mounted) return;
    showDialog(
        context: context,
        builder: (_) {
          return AlertDialog(
            title: const Text('Duplicatas e sugestões'),
            content: SizedBox(
                width: 600,
                height: 400,
                child: ListView(
                  children: [
                    if (exactDup.isNotEmpty) ...[
                      const Text('Duplicatas por normalização',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      ...exactDup.asMap().entries.map((e) {
                        final group = e.value;
                        final names = group.map((d) {
                          final m = d.data() as Map<String, dynamic>?;
                          return m?['name'] ?? d.id;
                        }).join(' â€¢ ');
                        return ListTile(
                            title: Text('Grupo ${e.key + 1}'),
                            subtitle: Text(names),
                            onTap: () {
                              Navigator.pop(context);
                              _showMergeDialog(group);
                            });
                      }),
                      const Divider(),
                    ],
                    if (fuzzyPairs.isNotEmpty) ...[
                      const Text('Sugestões fuzzy (possíveis duplicatas)',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      ...fuzzyPairs.map((pair) {
                        final a = pair[0];
                        final b = pair[1];
                        final na =
                            (a.data() as Map<String, dynamic>?)?['name'] ?? '';
                        final nb =
                            (b.data() as Map<String, dynamic>?)?['name'] ?? '';
                        return ListTile(
                            title: Text('$na  â†”  $nb'),
                            subtitle: Text('Toque para mesclar ambos'),
                            onTap: () {
                              Navigator.pop(context);
                              _showMergeDialog([a, b]);
                            });
                      })
                    ]
                  ],
                )),
          );
        });
  }

  Future<void> _showMergeDialog(List<QueryDocumentSnapshot> group) async {
    final names = group
        .map((d) => (d.data() as Map<String, dynamic>?)?['name'] ?? '')
        .toList();
    final ctrl = TextEditingController(text: names.first);
    await showDialog(
        context: context,
        builder: (_) {
          return AlertDialog(
            title: const Text('Mesclar categorias'),
            content: Column(mainAxisSize: MainAxisSize.min, children: [
              ...names.map((n) => ListTile(
                  title: Text(n), onTap: () => ctrl.text = n.toString())),
              TextField(
                  controller: ctrl,
                  decoration: const InputDecoration(labelText: 'Nome final')),
            ]),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancelar')),
              ElevatedButton(
                  onPressed: () async {
                    final finalName = ctrl.text.trim();
                    if (finalName.isEmpty) return;
                    final normalized = _normalize(finalName);
                    // find or create final
                    final q = await FirebaseFirestore.instance
                        .collection('service_categories')
                        .where('name_lower', isEqualTo: normalized)
                        .limit(1)
                        .get();
                    String finalId;
                    if (q.docs.isNotEmpty) {
                      finalId = q.docs.first.id;
                    } else {
                      final doc = await FirebaseFirestore.instance
                          .collection('service_categories')
                          .add({
                        'name': finalName,
                        'name_lower': normalized,
                        'createdAt': FieldValue.serverTimestamp()
                      });
                      finalId = doc.id;
                    }
                    for (final s in group) {
                      final sName =
                          (s.data() as Map<String, dynamic>?)?['name'] ?? '';
                      if (s.id == finalId) continue;
                      // update shops
                      final shopsSnap = await FirebaseFirestore.instance
                          .collection('shops')
                          .where('category', isEqualTo: sName)
                          .get();
                      for (final shop in shopsSnap.docs) {
                        final before = shop.data();
                        await FirebaseFirestore.instance
                            .collection('shops')
                            .doc(shop.id)
                            .update({'category': finalName});
                        await FirebaseFirestore.instance
                            .collection('admin_audit')
                            .add({
                          'adminUid': FirebaseAuth.instance.currentUser?.uid,
                          'action': 'merge_category_update_shop',
                          'targetId': shop.id,
                          'before': before,
                          'after': {'category': finalName},
                          'createdAt': FieldValue.serverTimestamp()
                        });
                      }
                      // delete source
                      await FirebaseFirestore.instance
                          .collection('service_categories')
                          .doc(s.id)
                          .delete();
                    }
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                          content: Text('Mesclagem concluída')));
                      Navigator.pop(context);
                    }
                  },
                  child: const Text('Mesclar'))
            ],
          );
        });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Categorias'),
        backgroundColor: AppColors.primaryPurple,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(children: [
          Row(children: [
            Expanded(
                child: TextField(
                    controller: _ctrl,
                    decoration:
                        const InputDecoration(labelText: 'Nova categoria'))),
            const SizedBox(width: 8),
            ElevatedButton(
                onPressed: _createCategory, child: const Text('Criar'))
          ]),
          const SizedBox(height: 12),
          Row(children: [
            ElevatedButton.icon(
                onPressed: _findDuplicates,
                icon: const Icon(Icons.merge_type),
                label: const Text('Encontrar duplicatas')),
            const SizedBox(width: 12),
            ElevatedButton.icon(
                onPressed: () {
                  Navigator.push(context,
                      MaterialPageRoute(builder: (_) => CategoriesListPage()));
                },
                icon: const Icon(Icons.list),
                label: const Text('Listar categorias')),
          ]),
        ]),
      ),
    );
  }
}

class CategoriesListPage extends StatelessWidget {
  const CategoriesListPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Todas as categorias'),
        backgroundColor: AppColors.primaryPurple,
        foregroundColor: Colors.white,
      ),
      body: StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('service_categories')
              .orderBy('name_lower')
              .snapshots(),
          builder: (c, snap) {
            if (!snap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final docs = snap.data!.docs;
            return ListView.builder(
                itemCount: docs.length,
                itemBuilder: (ctx, i) {
                  final d = docs[i];
                  final data = d.data() as Map<String, dynamic>? ?? {};
                  return ListTile(
                      title: Text(data['name'] ?? ''),
                      subtitle: Text('id: ${d.id}'),
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        IconButton(
                            icon: const Icon(Icons.edit),
                            onPressed: () async {
                              final ctrl = TextEditingController(
                                  text: data['name'] ?? '');
                              await showDialog(
                                  context: context,
                                  builder: (_) {
                                    return AlertDialog(
                                        title: const Text('Editar categoria'),
                                        content: TextField(controller: ctrl),
                                        actions: [
                                          TextButton(
                                              onPressed: () =>
                                                  Navigator.pop(context),
                                              child: const Text('Cancelar')),
                                          ElevatedButton(
                                              onPressed: () async {
                                                final name = ctrl.text.trim();
                                                if (name.isEmpty) return;
                                                final nl = name.toLowerCase();
                                                await FirebaseFirestore.instance
                                                    .collection(
                                                        'service_categories')
                                                    .doc(d.id)
                                                    .set({
                                                  'name': name,
                                                  'name_lower': nl
                                                }, SetOptions(merge: true));
                                                Navigator.pop(context);
                                              },
                                              child: const Text('Salvar'))
                                        ]);
                                  });
                            }),
                        IconButton(
                            icon: const Icon(Icons.delete),
                            onPressed: () async {
                              final ok = await showDialog<bool>(
                                  context: context,
                                  builder: (_) => AlertDialog(
                                          title: const Text('Excluir?'),
                                          content: const Text(
                                              'Deseja excluir esta categoria?'),
                                          actions: [
                                            TextButton(
                                                onPressed: () => Navigator.pop(
                                                    context, false),
                                                child: const Text('Cancelar')),
                                            ElevatedButton(
                                                onPressed: () => Navigator.pop(
                                                    context, true),
                                                child: const Text('Excluir'))
                                          ]));
                              if (ok == true) {
                                await FirebaseFirestore.instance
                                    .collection('service_categories')
                                    .doc(d.id)
                                    .delete();
                              }
                            })
                      ]));
                });
          }),
    );
  }
}
