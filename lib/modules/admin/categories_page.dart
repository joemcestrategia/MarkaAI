// ignore_for_file: use_build_context_synchronously
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/theme/app_colors.dart';
import '../../core/services/shop_data_cache_service.dart';

class CategoriesPage extends StatefulWidget {
  const CategoriesPage({super.key});

  @override
  State<CategoriesPage> createState() => _CategoriesPageState();
}

class _CategoriesPageState extends State<CategoriesPage> {
  final _ctrl = TextEditingController();


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
    final q = await Supabase.instance.client
        .from('categories')
        .select()
        .eq('name', name)
        .limit(1);
    if ((q as List).isNotEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Categoria já existe')));
      }
      return;
    }
    await Supabase.instance.client.from('categories').insert({
      'name': name,
      'created_at': DateTime.now().toIso8601String()
    });
    _ctrl.clear();
  }

  Future<void> _findDuplicates() async {
    final snap =
        await Supabase.instance.client.from('categories').select();
    final docs = snap as List<dynamic>;
    // first, exact-normalized duplicates
    final Map<String, List<Map<String, dynamic>>> groups = {};
    for (final d in docs) {
      final m = d as Map<String, dynamic>;
      final nl = (m['name'] ?? '').toString().toLowerCase();
      groups.putIfAbsent(nl, () => []).add(m);
    }
    final exactDup = groups.values.where((g) => g.length > 1).toList();

    // then fuzzy suggestions via Levenshtein on normalized names
    final items = docs.map((d) {
      final m = d as Map<String, dynamic>;
      final nameStr = (m['name'] ?? '').toString();
      return {'doc': d, 'name': nameStr, 'nl': nameStr.toLowerCase()};
    }).toList();
    final fuzzyPairs = <List<Map<String, dynamic>>>[];
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
            items[i]['doc'] as Map<String, dynamic>,
            items[j]['doc'] as Map<String, dynamic>
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
            content: Container(
                constraints: const BoxConstraints(maxWidth: 600),
                height: 400,
                child: ListView(
                  children: [
                    if (exactDup.isNotEmpty) ...[
                      const Text('Duplicatas por normalização',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      ...exactDup.asMap().entries.map((e) {
                        final group = e.value;
                        final names = group.map((m) {
                          return m['name'] ?? m['id'];
                        }).join(' • ');
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
                        final na = a['name'] ?? '';
                        final nb = b['name'] ?? '';
                        return ListTile(
                            title: Text('$na  ?  $nb'),
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

  Future<void> _showMergeDialog(List<Map<String, dynamic>> group) async {
    final names = group
        .map((d) => d['name']?.toString() ?? '')
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
                    // find or create final
                    final q = await Supabase.instance.client
                        .from('categories')
                        .select()
                        .eq('name', finalName)
                        .limit(1);
                    String finalId;
                    if ((q as List).isNotEmpty) {
                      finalId = q.first['id'].toString();
                    } else {
                      final doc = await Supabase.instance.client
                          .from('categories')
                          .insert({
                        'name': finalName,
                        'created_at': DateTime.now().toIso8601String()
                      }).select().single();
                      finalId = doc['id'].toString();
                    }
                    for (final s in group) {
                      final sName = s['name'] ?? '';
                      final sId = s['id'].toString();
                      if (sId == finalId) continue;
                      // update shops
                      final shopsSnap = await Supabase.instance.client
                          .from('shops')
                          .select()
                          .eq('category', sName);
                      for (final shop in shopsSnap as List<dynamic>) {
                        final before = shop;
                        final shopId = shop['id'].toString();
                        await Supabase.instance.client
                            .from('shops')
                            .update({'category': finalName})
                            .eq('id', shopId);
                        
                        // Invalida o cache da loja afetada
                        ShopDataCacheService().invalidateAll(shopId);

                        await Supabase.instance.client
                            .from('admin_audit')
                            .insert({
                          'adminUid': Supabase.instance.client.auth.currentUser?.id,
                          'action': 'merge_category_update_shop',
                          'targetId': shopId,
                          'before': before,
                          'after': {'category': finalName},
                          'createdAt': DateTime.now().toIso8601String()
                        });
                      }
                      // delete source
                      await Supabase.instance.client
                          .from('categories')
                          .delete()
                          .eq('id', sId);
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
      ),
      body: StreamBuilder<List<Map<String, dynamic>>>(
          stream: Supabase.instance.client
              .from('categories')
              .stream(primaryKey: ['id'])
              .order('name'),
          builder: (c, snap) {
            if (!snap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final docs = snap.data!;
            return ListView.builder(
                itemCount: docs.length,
                itemBuilder: (ctx, i) {
                  final data = docs[i];
                  final dId = data['id'].toString();
                  return ListTile(
                      title: Text(data['name'] ?? ''),
                      subtitle: Text('id: ${dId}'),
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
                                                await Supabase.instance.client
                                                    .from('categories')
                                                    .update({'name': name}).eq(
                                                        'id', dId);
                                                if (context.mounted) {
                                                  Navigator.pop(context);
                                                }
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
                                await Supabase.instance.client
                                    .from('categories')
                                    .delete()
                                    .eq('id', dId);
                              }
                            })
                      ]));
                });
          }),
    );
  }
}
