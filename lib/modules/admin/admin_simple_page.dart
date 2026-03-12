// ignore_for_file: use_build_context_synchronously
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../../core/theme/app_colors.dart';
import 'categories_page.dart';

class AdminSimplePage extends StatefulWidget {
  const AdminSimplePage({super.key});
  @override
  State<AdminSimplePage> createState() => _AdminSimplePageState();
}

class _AdminSimplePageState extends State<AdminSimplePage> {
  final user = FirebaseAuth.instance.currentUser;
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
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user!.uid)
        .get();
    final data = doc.exists ? doc.data() : {};
    final roles =
        (data?['roles'] as List<dynamic>?)?.map((e) => e.toString()).toList() ??
            [];
    setState(() {
      _isAdmin = roles.contains('admin') ||
          roles.contains('admin_dev') ||
          (data?['is_admin_dev'] == true);
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
      length: 6,
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
            Tab(text: 'Lojas'),
            Tab(text: 'Usuários'),
            Tab(text: 'Funcionários'),
            Tab(text: 'Agendamentos'),
            Tab(text: 'Planos'),
          ]),
        ),
        body: TabBarView(children: [
          _summaryTab(),
          _shopsTab(),
          _usersTab(),
          _employeesTab(),
          _appointmentsTab(),
          _plansLinkTab(),
        ]),
      ),
    );
  }

  Widget _summaryTab() {
    return FutureBuilder<List<int>>(
        future: Future.wait([
          FirebaseFirestore.instance
              .collection('shops')
              .get()
              .then((s) => s.size),
          FirebaseFirestore.instance
              .collection('users')
              .get()
              .then((s) => s.size),
          FirebaseFirestore.instance
              .collection('appointments')
              .get()
              .then((s) => s.size),
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
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text('$v', style: const TextStyle(fontSize: 18))
          ])));

  Widget _shopsTab() {
    return StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('shops')
            .orderBy('nome')
            .snapshots(),
        builder: (ctx, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final docs = snap.data!.docs;
          return ListView.builder(
              itemCount: docs.length,
              itemBuilder: (c, i) {
                final d = docs[i];
                final data = d.data() as Map<String, dynamic>? ?? {};
                return ListTile(
                    title: Text(data['nome'] ?? d.id),
                    subtitle: Text('Plano: ${data['plan'] ?? 'start'}'),
                    trailing: IconButton(
                        icon: const Icon(Icons.edit),
                        onPressed: () => _editShop(d)));
              });
        });
  }

  Future<void> _editShop(QueryDocumentSnapshot doc) async {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    final name = TextEditingController(text: data['nome'] ?? '');
    final phone = TextEditingController(text: data['telefone'] ?? '');
    final plansSnap = await FirebaseFirestore.instance
        .collection('plans')
        .orderBy('price_month')
        .get();
    if (!mounted) return;
    final planIds = plansSnap.docs.map((d) => d.id).toList();
    String selPlan =
        data['plan'] ?? (planIds.isNotEmpty ? planIds.first : 'start');
    await showDialog(
        context: context,
        builder: (ctx) {
          return AlertDialog(
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
                    initialValue: selPlan,
                    items: planIds
                        .map((p) => DropdownMenuItem(value: p, child: Text(p)))
                        .toList(),
                    onChanged: (v) {
                      if (v != null) selPlan = v;
                    },
                    decoration: const InputDecoration(labelText: 'Plano')),
              ]),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Cancelar')),
                ElevatedButton(
                    onPressed: () async {
                      final before = Map<String, dynamic>.from(data);
                      final after = {
                        ...before,
                        'nome': name.text.trim(),
                        'telefone': phone.text.trim(),
                        'plan': selPlan
                      };
                      await FirebaseFirestore.instance
                          .collection('shops')
                          .doc(doc.id)
                          .set(after, SetOptions(merge: true));
                      await FirebaseFirestore.instance
                          .collection('admin_audit')
                          .add({
                        'adminUid': user?.uid,
                        'action': 'edit_shop',
                        'targetId': doc.id,
                        'before': before,
                        'after': after,
                        'createdAt': FieldValue.serverTimestamp()
                      });
                      Navigator.pop(ctx);
                    },
                    child: const Text('Salvar'))
              ]);
        });
  }

  Widget _usersTab() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .orderBy('nome')
          .snapshots(),
      builder: (c, snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        var docs = snap.data!.docs;

        // apply tag filter if set
        if (_onlyVIP || (_tagFilter != null && _tagFilter!.trim().isNotEmpty)) {
          final f =
              (_onlyVIP ? 'VIP' : (_tagFilter ?? '').trim().toLowerCase());
          docs = docs.where((d) {
            final data = d.data() as Map<String, dynamic>? ?? {};
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
                  final d = docs[i];
                  final data = d.data() as Map<String, dynamic>? ?? {};
                  final tagsMap =
                      (data['shop_tags'] as Map<String, dynamic>?) ?? {};
                  final tagsFlat = tagsMap.values
                      .expand((v) => (v is List)
                          ? v.map((e) => e.toString())
                          : [v.toString()])
                      .take(5)
                      .join(', ');
                  return ListTile(
                    title: Text(data['nome'] ?? data['email'] ?? d.id),
                    subtitle: Text((data['email'] ?? '') +
                        (tagsFlat.isNotEmpty ? ' • Tags: $tagsFlat' : '')),
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      IconButton(
                          icon: const Icon(Icons.local_offer),
                          onPressed: () => _openTagDialog(d)),
                      IconButton(
                          icon: const Icon(Icons.edit),
                          onPressed: () => _openUserEditorSimple(d)),
                    ]),
                    onTap: () => _openClientCard(d),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _openUserEditorSimple(QueryDocumentSnapshot doc) async {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    final name = TextEditingController(text: data['nome'] ?? '');
    final email = TextEditingController(text: data['email'] ?? '');
    final phone = TextEditingController(text: data['telefone'] ?? '');
    // load shops for stats dropdown
    final shopsSnap = await FirebaseFirestore.instance
        .collection('shops')
        .orderBy('nome')
        .get();
    if (!mounted) return;
    final shops = shopsSnap.docs;
    String? selectedShop = shops.isNotEmpty ? shops.first.id : null;

    await showDialog(
        context: context,
        builder: (ctx) {
          return AlertDialog(
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
                  initialValue: selectedShop,
                  items: shops.map((s) {
                    final sd = s.data();
                    return DropdownMenuItem(
                        value: s.id, child: Text(sd['nome'] ?? s.id));
                  }).toList(),
                  onChanged: (v) {
                    selectedShop = v;
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
                    final apptsSnap = await FirebaseFirestore.instance
                        .collection('appointments')
                        .where('clientId', isEqualTo: doc.id)
                        .where('shopId', isEqualTo: selectedShop)
                        .orderBy('data_agendamento', descending: true)
                        .get();
                    if (!mounted) return;
                    final appts = apptsSnap.docs.map((d) => d.data()).toList();
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
                        final dt = a['data_agendamento'];
                        if (dt != null && dt is Timestamp) {
                          dates.add(dt.toDate());
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
                                    Navigator.pop(sctx);
                                    // add VIP tag
                                    final idToken = await FirebaseAuth
                                        .instance.currentUser
                                        ?.getIdToken();
                                    final url = Uri.parse(
                                        'https://us-central1-wismart-118c3.cloudfunctions.net/addTagToUser');
                                    final resp = await http.post(url,
                                        headers: {
                                          'Content-Type': 'application/json',
                                          'Authorization': 'Bearer $idToken'
                                        },
                                        body: jsonEncode({
                                          'userId': doc.id,
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
                                  },
                                  child: const Text('Marcar VIP')),
                            ],
                          );
                        });
                  },
                  child: const Text('Ver Estatísticas')),
              ElevatedButton(
                  onPressed: () async {
                    final before = Map<String, dynamic>.from(data);
                    final after = {
                      ...before,
                      'nome': name.text.trim(),
                      'email': email.text.trim(),
                      'telefone': phone.text.trim()
                    };
                    await FirebaseFirestore.instance
                        .collection('users')
                        .doc(doc.id)
                        .set(after, SetOptions(merge: true));
                    await FirebaseFirestore.instance
                        .collection('admin_audit')
                        .add({
                      'adminUid': user?.uid,
                      'action': 'edit_user',
                      'targetId': doc.id,
                      'before': before,
                      'after': after,
                      'createdAt': FieldValue.serverTimestamp()
                    });
                    Navigator.pop(ctx);
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Usuário atualizado')));
                  },
                  child: const Text('Salvar')),
            ],
          );
        });
  }

  Future<void> _openTagDialog(QueryDocumentSnapshot userDoc) async {
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
      final idToken = await FirebaseAuth.instance.currentUser?.getIdToken();
      final url = Uri.parse(
          'https://us-central1-wismart-118c3.cloudfunctions.net/addTagToUser');
      final resp = await http.post(url,
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $idToken'
          },
          body:
              jsonEncode({'userId': userDoc.id, 'shopId': shopId, 'tag': tag}));
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

  Future<void> _openClientCard(QueryDocumentSnapshot userDoc) async {
    final userId = userDoc.id;
    final data = userDoc.data() as Map<String, dynamic>? ?? {};

    // compute aggregated stats across shops or for a selected shop
    // default: overall stats
    final apptsSnap = await FirebaseFirestore.instance
        .collection('appointments')
        .where('clientId', isEqualTo: userId)
        .orderBy('data_agendamento', descending: true)
        .get();
    final appts = apptsSnap.docs.map((d) => d.data()).toList();
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
        final dt = a['data_agendamento'];
        if (dt != null && dt is Timestamp) dates.add(dt.toDate());
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
    final shopsSnap = await FirebaseFirestore.instance
        .collection('shops')
        .orderBy('nome')
        .get();
    final shopsList = shopsSnap.docs;

    await Navigator.push(context, MaterialPageRoute(builder: (ctx) {
      return Scaffold(
        appBar: AppBar(
            title: Text(data['nome'] ?? 'Cliente',
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
                    Text(data['nome'] ?? '',
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text(data['email'] ?? '',
                        style: const TextStyle(color: Colors.grey)),
                  ])),
              IconButton(
                  icon: const Icon(Icons.edit),
                  onPressed: () {
                    _openUserEditorSimple(userDoc);
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
                    final sd = s.data();
                    return DropdownMenuItem(
                        value: s.id, child: Text(sd['nome'] ?? s.id));
                  }).toList(),
                  onChanged: (_) {},
                  initialValue:
                      shopsList.isNotEmpty ? shopsList.first.id : null,
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                  onPressed: () async {
                    final tag = 'VIP';
                    final selectedShopId =
                        shopsList.isNotEmpty ? shopsList.first.id : null;
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
                          await FirebaseAuth.instance.currentUser?.getIdToken();
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
                      final when = (a['data_agendamento'] is Timestamp)
                          ? (a['data_agendamento'] as Timestamp)
                              .toDate()
                              .toLocal()
                              .toString()
                          : (a['data_agendamento']?.toString() ?? '');
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

  Widget _employeesTab() => StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('employees')
          .orderBy('nome')
          .snapshots(),
      builder: (c, snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snap.data!.docs;
        return ListView.builder(
            itemCount: docs.length,
            itemBuilder: (c, i) {
              final d = docs[i];
              final data = d.data() as Map<String, dynamic>? ?? {};
              return ListTile(
                  title: Text(data['nome'] ?? d.id),
                  subtitle: Text(data['email'] ?? ''));
            });
      });

  Widget _appointmentsTab() => StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('appointments')
          .orderBy('criado_em', descending: true)
          .limit(200)
          .snapshots(),
      builder: (c, snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snap.data!.docs;
        return ListView.builder(
            itemCount: docs.length,
            itemBuilder: (c, i) {
              final d = docs[i];
              final data = d.data() as Map<String, dynamic>? ?? {};
              final client =
                  data['client_nome'] ?? data['clientId'] ?? 'Cliente';
              return ListTile(
                  title: Text(client),
                  subtitle: Text(data['servico_nome'] ?? ''),
                  onTap: () => showDialog(
                      context: context,
                      builder: (_) => AlertDialog(
                          title: Text('Agendamento ${d.id}'),
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
}
