// ignore_for_file: use_build_context_synchronously
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:intl/intl.dart';
import '../../core/theme/app_colors.dart';
import '../../core/constants/api_keys.dart';
import 'admin_banners_page.dart';
import '../../core/services/shop_data_cache_service.dart';

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
      length: 10,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Painel Admin'),
          backgroundColor: AppColors.primaryPurple,
          foregroundColor: Colors.white,
          bottom: const TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: 'Resumo'),
              Tab(text: 'Negócios'),
              Tab(text: 'Categorias'),
              Tab(text: 'Usuários'),
              Tab(text: 'Funcionários'),
              Tab(text: 'Agendamentos'),
              Tab(text: 'Feriados'),
              Tab(text: 'Planos'),
              Tab(text: 'Banners'),
              Tab(text: 'Emails'),
            ],
          ),
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
          const AdminBannersPage(),
          _emailsTab(),
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
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Wrap(
                spacing: 16,
                runSpacing: 16,
                alignment: WrapAlignment.center,
                children: [
                  _statCard('Lojas', c[0], Icons.store),
                  _statCard('Usuários', c[1], Icons.people),
                  _statCard('Agendamentos', c[2], Icons.calendar_today),
                ]),
          );
        });
  }

  Widget _statCard(String title, int v, IconData icon) => Card(
      child: Container(
          width: 150,
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: AppColors.primaryPurple, size: 24),
              const SizedBox(height: 8),
              Text('$v', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
              Text(title, style: const TextStyle(fontSize: 12, color: Colors.grey)),
            ],
          )));

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
                    subtitle: Text('Plano: ${data['plan_id'] ?? data['plan'] ?? 'starter'}'),
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
        data['plan_id'] ?? data['plan'] ?? (planIds.isNotEmpty ? planIds.first : 'starter');
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

                  // Invalida o cache global
                  ShopDataCacheService().invalidateAll(null);

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
        
        // Invalida o cache global
        ShopDataCacheService().invalidateAll(null);
      } catch (e) {
        debugPrint("Erro ao excluir feriado global: $e");
      }
    }
  }

  // ============================================================
  // Aba Emails — Monitor de envios via Resend
  // ============================================================
  Widget _emailsTab() {
    return _EmailsTabContent(accessToken: Supabase.instance.client.auth.currentSession?.accessToken ?? '');
  }
}

// ---------------------------------------------------------------------------
// Widget isolado para a aba de Emails (com estado próprio)
// ---------------------------------------------------------------------------
class _EmailsTabContent extends StatefulWidget {
  final String accessToken;
  const _EmailsTabContent({required this.accessToken});

  @override
  State<_EmailsTabContent> createState() => _EmailsTabContentState();
}

class _EmailsTabContentState extends State<_EmailsTabContent> {
  List<Map<String, dynamic>> _emails = [];
  bool _loading = true;
  String? _error;
  int _page = 0;
  bool _hasMore = true;
  static const int _pageSize = 25;

  static const Map<String, Map<String, dynamic>> _statusConfig = {
    'delivered':        {'label': 'Entregue',  'color': 0xFF16A34A},
    'sent':             {'label': 'Enviado',   'color': 0xFF2563EB},
    'opened':           {'label': 'Aberto',    'color': 0xFF0D9488},
    'clicked':          {'label': 'Clicado',   'color': 0xFF7C3AED},
    'delivery_delayed': {'label': 'Atrasado',  'color': 0xFFEA580C},
    'bounced':          {'label': 'Bounce',    'color': 0xFFDC2626},
    'complained':       {'label': 'Spam',      'color': 0xFFDC2626},
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({int page = 0}) async {
    if (!mounted) return;
    setState(() { _loading = true; _error = null; });

    try {
      const supabaseUrl = ApiKeys.supabaseUrl;
      final offset = page * _pageSize;
      final uri = Uri.parse('$supabaseUrl/functions/v1/admin-resend-emails?limit=$_pageSize&offset=$offset');
      final res = await http.get(uri, headers: {
        'Authorization': 'Bearer ${widget.accessToken}',
        'Content-Type': 'application/json',
      });

      if (!mounted) return;
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        final list = (body['data'] as List?)?.cast<Map<String, dynamic>>() ?? [];
        setState(() {
          _emails = list;
          _page = page;
          _hasMore = list.length == _pageSize;
        });
      } else {
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        setState(() { _error = body['error']?.toString() ?? 'Erro HTTP ${res.statusCode}'; });
      }
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); });
    } finally {
      if (mounted) setState(() { _loading = false; });
    }
  }

  String _formatDate(String iso) {
    try {
      final d = DateTime.parse(iso).toLocal();
      return '${d.day.toString().padLeft(2,'0')}/${d.month.toString().padLeft(2,'0')}/${d.year} '
             '${d.hour.toString().padLeft(2,'0')}:${d.minute.toString().padLeft(2,'0')}';
    } catch (_) { return iso; }
  }

  Widget _statusChip(String status) {
    final cfg = _statusConfig[status] ?? {'label': status, 'color': 0xFF6B7280};
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Color(cfg['color'] as int).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Color(cfg['color'] as int).withValues(alpha: 0.4)),
      ),
      child: Text(
        cfg['label'] as String,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(cfg['color'] as int)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Stats
    final delivered = _emails.where((e) => ['delivered','opened','clicked'].contains(e['last_event'])).length;
    final bounced   = _emails.where((e) => ['bounced','complained'].contains(e['last_event'])).length;
    final delayed   = _emails.where((e) => e['last_event'] == 'delivery_delayed').length;

    return Column(children: [
      // Cards de estatísticas
      Container(
        color: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(children: [
          _statMini('Total', _emails.length.toString(), Colors.grey.shade700),
          const SizedBox(width: 8),
          _statMini('Entregues', delivered.toString(), const Color(0xFF16A34A)),
          const SizedBox(width: 8),
          _statMini('Bounces', bounced.toString(), const Color(0xFFDC2626)),
          const SizedBox(width: 8),
          _statMini('Atrasados', delayed.toString(), const Color(0xFFEA580C)),
        ]),
      ),
      const Divider(height: 1),

      // Conteúdo principal
      Expanded(child: _loading
        ? const Center(child: CircularProgressIndicator())
        : _error != null
          ? Center(child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.error_outline, color: Colors.red, size: 40),
                const SizedBox(height: 8),
                Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.red)),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  onPressed: () => _load(page: _page),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Tentar novamente'),
                ),
              ]),
            ))
          : _emails.isEmpty
            ? const Center(child: Text('Nenhum email encontrado.', style: TextStyle(color: Colors.grey)))
            : ListView.separated(
                itemCount: _emails.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final e = _emails[i];
                  final toList = (e['to'] as List?)?.join(', ') ?? '';
                  final subject = e['subject']?.toString() ?? '';
                  final status  = e['last_event']?.toString() ?? 'sent';
                  final date    = e['created_at']?.toString() ?? '';
                  return ListTile(
                    dense: true,
                    title: Text(toList, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis),
                    subtitle: Text(subject, style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis),
                    trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                      _statusChip(status),
                      const SizedBox(height: 3),
                      Text(_formatDate(date), style: const TextStyle(fontSize: 10, color: Colors.grey)),
                    ]),
                  );
                },
              ),
      ),

      // Paginação
      if (!_loading && _error == null)
        Container(
          color: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            TextButton.icon(
              onPressed: _page > 0 ? () => _load(page: _page - 1) : null,
              icon: const Icon(Icons.chevron_left, size: 18),
              label: const Text('Anterior'),
            ),
            Text('Página ${_page + 1}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
            TextButton.icon(
              onPressed: _hasMore ? () => _load(page: _page + 1) : null,
              icon: const Icon(Icons.chevron_right, size: 18),
              label: const Text('Próxima'),
            ),
          ]),
        ),
    ]);
  }

  Widget _statMini(String label, String value, Color color) {
    return Expanded(child: Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
        Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey)),
      ]),
    ));
  }
}
