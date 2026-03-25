// ignore_for_file: use_build_context_synchronously
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:intl/intl.dart';
import '../../core/theme/app_colors.dart';
import 'categories_page.dart';

class AdminSimplePage extends StatefulWidget {
  const AdminSimplePage({super.key});
  @override
  State<AdminSimplePage> createState() => _AdminSimplePageState();
}

class _AdminSimplePageState extends State<AdminSimplePage> {
  final user = Supabase.instance.client.auth.currentUser;
  bool _loading = true;
  bool _isAdmin = false;
  // users list filters
  String? _tagFilter;
  bool _onlyVIP = false;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    if (user == null) {
      setState(() {
        _loading = false;
        _isAdmin = false;
      });
      return;
    }
    final data = await Supabase.instance.client
        .from('users')
        .select('role')
        .eq('id', user!.id)
        .maybeSingle();

    setState(() {
      _isAdmin = (data?['role'] == 'admin');
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (!_isAdmin) {
      return Scaffold(
          appBar: AppBar(title: const Text('Admin')),
          body: const Center(child: Text('Acesso restrito')));
    }

    return DefaultTabController(
      length: 9,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Painel Admin'),
          backgroundColor: AppColors.primaryPurple,
          foregroundColor: Colors.white,
          actions: [
            IconButton(
              tooltip: 'Categorias',
              icon: const Icon(Icons.category),
              onPressed: () => Navigator.push(
                  context, MaterialPageRoute(builder: (_) => CategoriesPage())),
            )
          ],
          bottom: const TabBar(tabs: [
            Tab(text: 'Resumo'),
            Tab(text: 'Negócios'),
            Tab(text: 'Categorias'),
            Tab(text: 'Usuários'),
            Tab(text: 'Funcionários'),
            Tab(text: 'Agendamentos'),
            Tab(text: 'Feriados'),
            Tab(text: 'Planos'),
            Tab(text: 'Afiliados'),
          ]),
        ),
        body: TabBarView(children: [
          _summaryTab(),
          _shopsTab(),
          _categoriesTab(),
          _usersTab(),
          _employeesTab(),
          _appointmentsTab(),
          _holidaysTab(),
          _plansLinkTab(),
          _affiliatesTab(),
        ]),
      ),
    );
  }

  Widget _summaryTab() {
    return FutureBuilder<List<int>>(
        future: Future.wait([
          Supabase.instance.client.from('shops').count(CountOption.exact),
          Supabase.instance.client.from('users').count(CountOption.exact),
          Supabase.instance.client.from('appointments').count(CountOption.exact),
        ]),
        builder: (ctx, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final c = snap.data!;
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _statCard('Lojas', c[0]),
                  _statCard('Usuários', c[1]),
                  _statCard('Agendamentos', c[2]),
                ]),
          );
        });
  }

  Widget _statCard(String title, int v) => Card(
      child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(children: [
            Text('$v', style: const TextStyle(fontSize: 18))
          ])));

  Widget _categoriesTab() => StreamBuilder<List<Map<String, dynamic>>>(
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
            itemBuilder: (c, i) {
              final data = docs[i];
              return ListTile(
                title: Text(data['name'] ?? ''),
                subtitle: Text('Shop: ${data['shop_id']}'),
              );
            });
      });

  Widget _shopsTab() {
    return StreamBuilder<List<Map<String, dynamic>>>(
        stream: Supabase.instance.client
            .from('shops')
            .stream(primaryKey: ['id'])
            .order('name'),
        builder: (ctx, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final docs = snap.data!;
          return ListView.builder(
              itemCount: docs.length,
              itemBuilder: (c, i) {
                final data = docs[i];
                final dId = data['id'];
                return ListTile(
                    title: Text(data['name'] ?? data['nome'] ?? dId),
                    subtitle: Text('Plano: ${data['plan_id'] ?? data['plan'] ?? 'start'}'),
                    trailing: IconButton(
                        icon: const Icon(Icons.edit),
                        onPressed: () => _editShop(data)));
              });
        });
  }

  Future<void> _editShop(Map<String, dynamic> data) async {
    final dId = data['id'];
    final name = TextEditingController(text: data['name'] ?? data['nome'] ?? '');
    final phone = TextEditingController(text: data['phone'] ?? data['telefone'] ?? '');
    final plansSnap = await Supabase.instance.client
        .from('plans')
        .select()
        .order('price_month');
    if (!mounted) return;
    final planIds = (plansSnap as List<dynamic>).map((d) => d['id'].toString()).toList();
    String selPlan =
        data['plan_id'] ?? data['plan'] ?? (planIds.isNotEmpty ? planIds.first : 'start');
    await showDialog(
        context: context,
        builder: (ctx) {
          return StatefulBuilder(
            builder: (ctx, setModalState) => AlertDialog(
                title: const Text('Editar loja'),
                content: Column(mainAxisSize: MainAxisSize.min, children: [
                  TextField(
                      controller: name,
                      decoration: const InputDecoration(labelText: 'Nome')),
                  TextField(
                      controller: phone,
                      decoration: const InputDecoration(labelText: 'Telefone')),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                      value: selPlan,
                      items: planIds
                          .map((p) => DropdownMenuItem<String>(value: p, child: Text(p)))
                          .toList(),
                      onChanged: (v) {
                        if (v != null) setModalState(() => selPlan = v);
                      },
                      decoration: const InputDecoration(labelText: 'Plano')),
                ]),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Cancelar')),
                  ElevatedButton(
                      onPressed: () async {
                        try {
                          final before = Map<String, dynamic>.from(data);
                          final after = {
                            ...before,
                            'name': name.text.trim(),
                            'phone': phone.text.trim(),
                            'plan_id': selPlan
                          };
                          await Supabase.instance.client
                              .from('shops')
                              .update(after)
                              .eq('id', dId);
                          await Supabase.instance.client
                              .from('admin_audit')
                              .insert({
                            'adminUid': user?.id,
                            'action': 'edit_shop',
                            'targetId': dId,
                            'before': before,
                            'after': after,
                            'createdAt': DateTime.now().toIso8601String()
                          });
                          Navigator.pop(ctx);
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Loja atualizada')));
                          }
                        } catch (e) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Erro ao salvar: $e')));
                          }
                        }
                      },
                      child: const Text('Salvar'))
                ]),
          );
        });
  }

  Widget _usersTab() {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: Supabase.instance.client
          .from('users')
          .stream(primaryKey: ['id'])
          .order('name'),
      builder: (c, snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        var docs = snap.data!;

        // apply tag filter if set
        if (_onlyVIP || (_tagFilter != null && _tagFilter!.trim().isNotEmpty)) {
          final f =
              (_onlyVIP ? 'VIP' : (_tagFilter ?? '').trim().toLowerCase());
          docs = docs.where((data) {
            final shopTags = data['shop_tags'] as Map<String, dynamic>? ?? {};
            // flatten values
            final allTags = shopTags.values
                .expand((v) {
                  if (v is List) return v.map((e) => e.toString());
                  return [v.toString()];
                })
                .map((s) => s.toLowerCase())
                .toList();
            return allTags.any((t) => t.contains(f));
          }).toList();
        }

        return Column(
          children: [
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8),
              child: Row(children: [
                Expanded(
                  child: TextField(
                    decoration: const InputDecoration(
                        labelText: 'Filtrar por tag (ex: VIP)',
                        prefixIcon: Icon(Icons.label)),
                    onChanged: (v) => setState(() {
                      _tagFilter = v;
                      _onlyVIP = false;
                    }),
                  ),
                ),
                const SizedBox(width: 8),
                FilterChip(
                  label: const Text('VIP'),
                  selected: _onlyVIP,
                  onSelected: (s) => setState(() {
                    _onlyVIP = s;
                    if (s) _tagFilter = 'VIP';
                  }),
                ),
                const SizedBox(width: 8),
                IconButton(
                    icon: const Icon(Icons.clear),
                    tooltip: 'Limpar filtro',
                    onPressed: () => setState(() {
                          _tagFilter = null;
                          _onlyVIP = false;
                        })),
              ]),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: docs.length,
                itemBuilder: (c, i) {
                  final data = docs[i];
                  final dId = data['id'];
                  final tagsMap =
                      (data['shop_tags'] as Map<String, dynamic>?) ?? {};
                  final tagsFlat = tagsMap.values
                      .expand((v) => (v is List)
                          ? v.map((e) => e.toString())
                          : [v.toString()])
                      .take(5)
                      .join(', ');
                  return ListTile(
                    title: Text(data['name'] ?? data['nome'] ?? data['email'] ?? dId),
                    subtitle: Text((data['email'] ?? '') +
                        (tagsFlat.isNotEmpty ? ' • Tags: $tagsFlat' : '')),
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      IconButton(
                          icon: const Icon(Icons.local_offer),
                          onPressed: () => _openTagDialog(data)),
                      IconButton(
                          icon: const Icon(Icons.edit),
                          onPressed: () => _openUserEditorSimple(data)),
                    ]),
                    onTap: () => _openClientCard(data),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _openUserEditorSimple(Map<String, dynamic> data) async {
    final dId = data['id'];
    final name = TextEditingController(text: data['name'] ?? data['nome'] ?? '');
    final email = TextEditingController(text: data['email'] ?? '');
    final phone = TextEditingController(text: data['phone'] ?? data['telefone'] ?? '');
    // load shops for stats dropdown
    final shopsSnap = await Supabase.instance.client
        .from('shops')
        .select()
        .order('name');
    if (!mounted) return;
    final shops = shopsSnap as List<dynamic>;
    String? selectedShop = shops.isNotEmpty ? shops.first['id'] : null;

    await showDialog(
        context: context,
        builder: (ctx) {
          return StatefulBuilder(
            builder: (ctx, setModalState) => AlertDialog(
              title: const Text('Editar usuário'),
              content: Column(mainAxisSize: MainAxisSize.min, children: [
                TextField(
                    controller: name,
                    decoration: const InputDecoration(labelText: 'Nome')),
                TextField(
                    controller: email,
                    decoration: const InputDecoration(labelText: 'E-mail')),
                TextField(
                    controller: phone,
                    decoration: const InputDecoration(labelText: 'Telefone')),
                const SizedBox(height: 8),
                if (shops.isNotEmpty)
                  DropdownButtonFormField<String>(
                    value: selectedShop,
                    items: shops.map((s) {
                      return DropdownMenuItem<String>(
                          value: s['id'].toString(),
                          child: Text(s['name'] ?? s['nome'] ?? s['id'].toString()));
                    }).toList(),
                    onChanged: (v) {
                      setModalState(() => selectedShop = v);
                    },
                    decoration: const InputDecoration(
                        labelText: 'Loja (para estatísticas)'),
                  ),
              ]),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Cancelar')),
                TextButton(
                    onPressed: () async {
                      // Show stats for selected shop
                      if (selectedShop == null) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content: Text('Nenhuma loja selecionada')));
                        }
                        return;
                      }
                      // compute stats
                      final apptsSnap = await Supabase.instance.client
                          .from('appointments')
                          .select()
                          .eq('client_id', dId)
                          .eq('shop_id', selectedShop!)
                          .order('scheduled_at', ascending: false);
                      if (!mounted) return;
                      final appts = apptsSnap as List<dynamic>;
                      final totalAppointments = appts.length;
                      final cancellations = appts
                          .where((a) => (a['status'] ?? '') == 'cancelado')
                          .length;
                      double totalSpent = 0;
                      final dates = <DateTime>[];
                      for (final a in appts) {
                        if (a['valor_pago'] != null) {
                          totalSpent +=
                              double.tryParse(a['valor_pago'].toString()) ?? 0.0;
                        }
                        try {
                          final dt = a['scheduled_at'];
                          if (dt != null) {
                            dates.add(DateTime.parse(dt.toString()));
                          }
                        } catch (_) {}
                      }
                      dates.sort();
                      final last = dates.isNotEmpty ? dates.last : null;
                      final daysSinceLast = last != null
                          ? DateTime.now().difference(last).inDays
                          : -1;
                      double avgReturn = 0;
                      if (dates.length > 1) {
                        int totalDays = 0;
                        for (var i = 1; i < dates.length; i++) {
                          totalDays += dates[i].difference(dates[i - 1]).inDays;
                        }
                        avgReturn = totalDays / (dates.length - 1);
                      }
                      // show dialog with stats and option to mark VIP
                      await showDialog(
                          context: context,
                          builder: (sctx) {
                            return AlertDialog(
                              title: const Text('Estatísticas do cliente'),
                              content: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                        'Total agendamentos: $totalAppointments'),
                                    Text('Cancelamentos: $cancellations'),
                                    Text(
                                        'Total gasto: R\$${totalSpent.toStringAsFixed(2)}'),
                                    Text(
                                        'Dias desde última visita: ${daysSinceLast >= 0 ? daysSinceLast.toString() : "N/A"}'),
                                    Text(
                                        'Média retorno: ${dates.length > 1 ? "${avgReturn.toStringAsFixed(1)} dias" : "N/A"}'),
                                  ]),
                              actions: [
                                TextButton(
                                    onPressed: () => Navigator.pop(sctx),
                                    child: const Text('Fechar')),
                                ElevatedButton(
                                    onPressed: () async {
                                      try {
                                        Navigator.pop(sctx);
                                        // add VIP tag
                                        final idToken = Supabase.instance.client.auth.currentSession?.accessToken;
                                        final url = Uri.parse(
                                            'https://us-central1-wismart-118c3.cloudfunctions.net/addTagToUser');
                                        final resp = await http.post(url,
                                            headers: {
                                              'Content-Type': 'application/json',
                                              'Authorization': 'Bearer $idToken'
                                            },
                                            body: jsonEncode({
                                              'userId': dId,
                                              'shopId': selectedShop,
                                              'tag': 'VIP'
                                            }));
                                        if (!mounted) return;
                                        if (resp.statusCode == 200) {
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(const SnackBar(
                                                  content: Text(
                                                      'Usuário marcado como VIP')));
                                        } else {
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(SnackBar(
                                                  content: Text(
                                                      'Erro ao marcar VIP: ${resp.statusCode}')));
                                        }
                                      } catch (e) {
                                        if (mounted) {
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(SnackBar(
                                                  content: Text('Erro: $e')));
                                        }
                                      }
                                    },
                                    child: const Text('Marcar VIP')),
                              ],
                            );
                          });
                    },
                    child: const Text('Ver Estatísticas')),
                ElevatedButton(
                    onPressed: () async {
                      try {
                        final before = Map<String, dynamic>.from(data);
                        final after = {
                          ...before,
                          'name': name.text.trim(),
                          'email': email.text.trim(),
                          'phone': phone.text.trim()
                        };
                        await Supabase.instance.client
                            .from('users')
                            .update(after)
                            .eq('id', dId);
                        await Supabase.instance.client
                            .from('admin_audit')
                            .insert({
                          'adminUid': user?.id,
                          'action': 'edit_user',
                          'targetId': dId,
                          'before': before,
                          'after': after,
                          'createdAt': DateTime.now().toIso8601String()
                        });
                        Navigator.pop(ctx);
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Usuário atualizado')));
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Erro ao salvar: $e')));
                        }
                      }
                    },
                    child: const Text('Salvar')),
              ],
            ),
          );
        });
  }

  Future<void> _openTagDialog(Map<String, dynamic> data) async {
    final dId = data['id'];
    final tagCtrl = TextEditingController();
    final shopCtrl = TextEditingController();
    final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) {
          return AlertDialog(
              title: const Text('Adicionar tag'),
              content: Column(mainAxisSize: MainAxisSize.min, children: [
                TextField(
                    controller: shopCtrl,
                    decoration: const InputDecoration(labelText: 'Shop ID')),
                TextField(
                    controller: tagCtrl,
                    decoration: const InputDecoration(labelText: 'Tag')),
              ]),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('Cancelar')),
                ElevatedButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('Adicionar'))
              ]);
        });
    if (ok != true) return;
    final shopId = shopCtrl.text.trim();
    final tag = tagCtrl.text.trim();
    if (shopId.isEmpty || tag.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Shop ID e tag necessários')));
      }
      return;
    }
    try {
      final idToken = await Supabase.instance.client.auth.currentSession?.accessToken;
      final url = Uri.parse(
          'https://us-central1-wismart-118c3.cloudfunctions.net/addTagToUser');
      final resp = await http.post(url,
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $idToken'
          },
          body:
              jsonEncode({'userId': dId, 'shopId': shopId, 'tag': tag}));
      if (resp.statusCode == 200) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('Tag adicionada')));
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Erro: ${resp.statusCode}')));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Erro: $e')));
      }
    }
  }

  Future<void> _openClientCard(Map<String, dynamic> data) async {
    final userId = data['id'];

    // compute aggregated stats across shops or for a selected shop
    // default: overall stats
    final apptsSnap = await Supabase.instance.client
        .from('appointments')
        .select()
        .eq('client_id', userId)
        .order('scheduled_at', ascending: false);
    final appts = apptsSnap as List<dynamic>;
    final totalAppointments = appts.length;
    final cancellations =
        appts.where((a) => (a['status'] ?? '') == 'cancelado').length;
    double totalSpent = 0;
    final dates = <DateTime>[];
    for (final a in appts) {
      if (a['valor_pago'] != null) {
        totalSpent += double.tryParse(a['valor_pago'].toString()) ?? 0.0;
      }
      try {
        final dt = a['scheduled_at'];
        if (dt != null) dates.add(DateTime.parse(dt.toString()));
      } catch (_) {}
    }
    dates.sort();
    final last = dates.isNotEmpty ? dates.last : null;
    final daysSinceLast =
        last != null ? DateTime.now().difference(last).inDays : -1;
    double avgReturn = 0;
    if (dates.length > 1) {
      int totalDays = 0;
      for (var i = 1; i < dates.length; i++) {
        totalDays += dates[i].difference(dates[i - 1]).inDays;
      }
      avgReturn = totalDays / (dates.length - 1);
    }

    // load shops for selector
    final shopsSnap = await Supabase.instance.client
        .from('shops')
        .select()
        .order('name');
    final shopsList = shopsSnap as List<dynamic>;

    await Navigator.push(context, MaterialPageRoute(builder: (ctx) {
      return Scaffold(
        appBar: AppBar(
            title: Text(data['name'] ?? data['nome'] ?? 'Cliente',
                style: const TextStyle(color: Colors.white)),
            backgroundColor: AppColors.primaryPurple,
            foregroundColor: Colors.white),
        body: Padding(
          padding: const EdgeInsets.all(16.0),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              CircleAvatar(
                  radius: 28,
                  backgroundImage: data['photoUrl'] != null
                      ? NetworkImage(data['photoUrl']) as ImageProvider
                      : null,
                  child: data['photoUrl'] == null
                      ? const Icon(Icons.person, size: 28)
                      : null),
              const SizedBox(width: 12),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(data['name'] ?? data['nome'] ?? '',
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text(data['email'] ?? '',
                        style: const TextStyle(color: Colors.grey)),
                  ])),
              IconButton(
                  icon: const Icon(Icons.edit),
                  onPressed: () {
                    _openUserEditorSimple(data);
                  }),
            ]),
            const SizedBox(height: 16),
            Card(
                child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Estatísticas',
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold)),
                          const SizedBox(height: 8),
                          Text('Total de agendamentos: $totalAppointments'),
                          Text('Cancelamentos: $cancellations'),
                          Text(
                              'Total gasto: R\$${totalSpent.toStringAsFixed(2)}'),
                          Text(
                              'Dias desde última visita: ${daysSinceLast >= 0 ? daysSinceLast.toString() : "N/A"}'),
                          Text(
                              'Média retorno: ${dates.length > 1 ? "${avgReturn.toStringAsFixed(1)} dias" : "N/A"}'),
                        ]))),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  decoration: const InputDecoration(
                      labelText: 'Loja (para aplicar tag)'),
                  items: shopsList.map((s) {
                    return DropdownMenuItem<String>(
                        value: s['id'].toString(), child: Text(s['name'] ?? s['nome'] ?? s['id'].toString()));
                  }).toList(),
                  onChanged: (_) {},
                  value:
                      shopsList.isNotEmpty ? shopsList.first['id'] : null,
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                  onPressed: () async {
                    final tag = 'VIP';
                    final selectedShopId =
                        shopsList.isNotEmpty ? shopsList.first['id'] : null;
                    if (selectedShopId == null) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                            content: Text(
                                'Nenhuma loja disponível para aplicar tag')));
                      }
                      return;
                    }
                    try {
                      final idToken =
                          await Supabase.instance.client.auth.currentSession?.accessToken;
                      final url = Uri.parse(
                          'https://us-central1-wismart-118c3.cloudfunctions.net/addTagToUser');
                      final resp = await http.post(url,
                          headers: {
                            'Content-Type': 'application/json',
                            'Authorization': 'Bearer $idToken'
                          },
                          body: jsonEncode({
                            'userId': userId,
                            'shopId': selectedShopId,
                            'tag': tag
                          }));
                      if (resp.statusCode == 200) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                              content: Text(
                                  'Tag VIP adicionada e notificação enviada')));
                        }
                      } else {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                              content: Text('Erro: ${resp.statusCode}')));
                        }
                      }
                    } catch (e) {
                      if (mounted) {
                        ScaffoldMessenger.of(context)
                            .showSnackBar(SnackBar(content: Text('Erro: $e')));
                      }
                    }
                  },
                  icon: const Icon(Icons.star),
                  label: const Text('Marcar VIP')),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                  },
                  icon: const Icon(Icons.close),
                  label: const Text('Fechar')),
            ]),
            const SizedBox(height: 12),
            const Divider(),
            const SizedBox(height: 8),
            const Text('Agendamentos recentes',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Expanded(
                child: ListView.builder(
                    itemCount: appts.length,
                    itemBuilder: (c, i) {
                      final a = appts[i];
                      final service = a['servico_nome'] ?? a['servico'] ?? '';
                      final when = a['scheduled_at'] != null ? DateTime.parse(a['scheduled_at'].toString()).toLocal().toString() : '';
                      return ListTile(
                          title: Text(service),
                          subtitle: Text(when),
                          trailing: Text(a['status'] ?? ''));
                    })),
          ]),
        ),
      );
    }));
  }

  Widget _employeesTab() => StreamBuilder<List<Map<String, dynamic>>>(
      stream: Supabase.instance.client
          .from('employees')
          .stream(primaryKey: ['id'])
          .order('name'),
      builder: (c, snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snap.data!;
        return ListView.builder(
            itemCount: docs.length,
            itemBuilder: (c, i) {
              final data = docs[i];
              final dId = data['id'];
              return ListTile(
                  title: Text(data['nome'] ?? dId),
                  subtitle: Text(data['email'] ?? ''));
            });
      });

  Widget _appointmentsTab() => StreamBuilder<List<Map<String, dynamic>>>(
      stream: Supabase.instance.client
          .from('appointments')
          .stream(primaryKey: ['id'])
          .order('created_at', ascending: false)
          .limit(200),
      builder: (c, snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snap.data!;
        return ListView.builder(
            itemCount: docs.length,
            itemBuilder: (c, i) {
              final data = docs[i];
              final d_id = data['id'];
              final rawClient = (data['client_name'] ?? data['client_nome'] ?? data['clientId'] ?? '').toString().trim();
              final client = (rawClient.toLowerCase() == 'null' || rawClient.isEmpty) ? 'Cliente' : rawClient;
              final rawService = (data['service_name'] ?? data['servico_nome'] ?? '').toString().trim();
              final service = (rawService.toLowerCase() == 'null' || rawService.isEmpty) ? 'Serviço' : rawService;

              return ListTile(
                  title: Text(client.toString()),
                  subtitle: Text(service.toString()),
                  onTap: () => showDialog(
                      context: context,
                      builder: (_) => AlertDialog(
                          title: Text('Agendamento $d_id'),
                          content: SingleChildScrollView(
                              child: Text(jsonEncode(data))))));
            });
      });

  Widget _plansLinkTab() {
    return Center(
        child: ElevatedButton.icon(
            onPressed: () => Navigator.pushNamed(context, '/admin/plans'),
            icon: const Icon(Icons.settings),
            label: const Text('Gerenciar Planos')));
  }

  Widget _holidaysTab() => StreamBuilder<List<Map<String, dynamic>>>(
      stream: Supabase.instance.client
          .from('global_holidays')
          .stream(primaryKey: ['id'])
          .order('date', ascending: false),
      builder: (c, snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snap.data!;
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: ElevatedButton.icon(
                onPressed: _showAddGlobalHolidayDialog,
                icon: const Icon(Icons.add),
                label: const Text("Adicionar Feriado Global"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blueAccent,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
            Expanded(
              child: ListView.builder(
                  itemCount: docs.length,
                  itemBuilder: (c, i) {
                    final data = docs[i];
                    final date = data['date'];
                    final name = data['name'] ?? 'Feriado';
                    return ListTile(
                      leading: const Icon(Icons.event, color: Colors.blue),
                      title: Text(name),
                      subtitle: Text(date),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () => _deleteGlobalHoliday(data['id']),
                      ),
                    );
                  }),
            ),
          ],
        );
      });

  Future<void> _showAddGlobalHolidayDialog() async {
    final nameCtrl = TextEditingController();
    DateTime selectedDate = DateTime.now();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Text("Novo Feriado Global"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: "Nome do Feriado"),
              ),
              const SizedBox(height: 16),
              ListTile(
                title: Text("Data: ${DateFormat('dd/MM/yyyy').format(selectedDate)}"),
                trailing: const Icon(Icons.calendar_today),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: selectedDate,
                    firstDate: DateTime(2023),
                    lastDate: DateTime(2030),
                  );
                  if (picked != null) {
                    setS(() => selectedDate = picked);
                  }
                },
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancelar")),
            ElevatedButton(
              onPressed: () async {
                if (nameCtrl.text.isEmpty) return;
                try {
                  await Supabase.instance.client.from('global_holidays').insert({
                    'date': DateFormat('yyyy-MM-dd').format(selectedDate),
                    'name': nameCtrl.text.trim(),
                    'is_platform_closed': true,
                  });
                  if (mounted) Navigator.pop(ctx);
                } catch (e) {
                  debugPrint("Erro ao salvar feriado global: $e");
                }
              },
              child: const Text("Salvar"),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteGlobalHoliday(String id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Excluir Feriado"),
        content: const Text("Tem certeza que deseja excluir este feriado global?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Não")),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Sim, Excluir", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await Supabase.instance.client.from('global_holidays').delete().eq('id', id);
      } catch (e) {
        debugPrint("Erro ao excluir feriado global: $e");
      }
    }
  }

  Widget _affiliatesTab() {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: Supabase.instance.client
          .from('affiliates')
          .stream(primaryKey: ['id'])
          .order('created_at', ascending: false),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final affiliates = snapshot.data!;
        
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: ElevatedButton.icon(
                onPressed: () => _editAffiliateConfig(),
                icon: const Icon(Icons.settings),
                label: const Text('Configurar Programa'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryPurple,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: affiliates.length,
                itemBuilder: (context, index) {
                  final aff = affiliates[index];
                  final bool isActive = aff['status'] == 'active';
                  
                  return ListTile(
                    title: Text(aff['coupon_code'] ?? 'SEM CUPOM'),
                    subtitle: Text('Status: ${aff['status']} • Vendas: ${aff['total_referrals']}'),
                    trailing: Switch(
                      value: isActive,
                      onChanged: (val) => _toggleAffiliateStatus(aff['id'], val),
                    ),
                    onTap: () => _showAffiliateDetails(aff),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _toggleAffiliateStatus(String id, bool val) async {
    try {
      await Supabase.instance.client
          .from('affiliates')
          .update({'status': val ? 'active' : 'inactive'})
          .eq('id', id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Status atualizado: ${val ? "Ativo" : "Inativo"}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao atualizar status: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _editAffiliateConfig() async {
    final configSnap = await Supabase.instance.client
        .from('affiliate_program_config')
        .select()
        .maybeSingle();
    
    final Map<String, dynamic> config = configSnap ?? {
      'commission_percent': 20,
      'discount_percent': 10,
      'is_active': true,
    };

    final commCtrl = TextEditingController(text: config['commission_percent'].toString());
    final discCtrl = TextEditingController(text: config['discount_percent'].toString());
    bool isActive = config['is_active'] ?? true;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => AlertDialog(
          title: const Text('Configuração do Programa'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: commCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Comissão (%)', suffixText: '%'),
              ),
              TextField(
                controller: discCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Desconto Cliente (%)', suffixText: '%'),
              ),
              SwitchListTile(
                title: const Text('Programa Ativo'),
                value: isActive,
                onChanged: (val) => setModalState(() => isActive = val),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
            ElevatedButton(
              onPressed: () async {
                final newConfig = {
                  'commission_percent': int.tryParse(commCtrl.text) ?? 20,
                  'discount_percent': int.tryParse(discCtrl.text) ?? 10,
                  'is_active': isActive,
                  'updated_at': DateTime.now().toIso8601String(),
                };
                
                if (configSnap == null) {
                  await Supabase.instance.client.from('affiliate_program_config').insert(newConfig);
                } else {
                  await Supabase.instance.client.from('affiliate_program_config').update(newConfig).eq('id', config['id']);
                }
                
                if (mounted) {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Configuração salva!')));
                }
              },
              child: const Text('Salvar'),
            ),
          ],
        ),
      ),
    );
  }

  void _showAffiliateDetails(Map<String, dynamic> aff) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Cupom: ${aff['coupon_code']}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const Divider(),
            Text('ID: ${aff['id']}'),
            Text('Total de Vendas: ${aff['total_referrals']}'),
            Text('Comissões Totais: R\$ ${((aff['total_commissions'] ?? 0) / 100).toStringAsFixed(2)}'),
            Text('Pendente: R\$ ${((aff['pending_payout'] ?? 0) / 100).toStringAsFixed(2)}'),
            const SizedBox(height: 16),
            const Text('Histórico de comissões e vendas pode ser visualizado no banco de dados.', style: TextStyle(fontStyle: FontStyle.italic, color: Colors.grey)),
          ],
        ),
      ),
    );
  }
}
