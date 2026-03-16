import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

class AdminSupportWidget extends StatelessWidget {
  const AdminSupportWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0F1117),
        cardColor: const Color(0xFF1A1D27),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Ações Rápidas de Suporte',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            const SizedBox(height: 8),
            Text(
              'Gerenciamento manual, exportação de dados e utilitários administrativos.',
              style: TextStyle(color: Colors.grey[500], fontSize: 14),
            ),
            const SizedBox(height: 32),
  
            LayoutBuilder(builder: (context, constraints) {
              final cols = constraints.maxWidth > 1000 ? 4 : (constraints.maxWidth > 600 ? 2 : 1);
              return GridView.count(
                crossAxisCount: cols,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisSpacing: 20,
                mainAxisSpacing: 20,
                childAspectRatio: 1.5,
                children: [
                  _buildActionCard(
                    context,
                    'Gerenciar Assinatura',
                    Icons.card_membership_rounded,
                    const Color(0xFF4F8EF7),
                    () => _showSubscriptionOverride(context),
                  ),
                  _buildActionCard(
                    context,
                    'Exportar Usuários',
                    Icons.people_alt_rounded,
                    const Color(0xFF22C55E),
                    () => _exportUsers(context),
                  ),
                  _buildActionCard(
                    context,
                    'Exportar Negócios',
                    Icons.storefront_rounded,
                    const Color(0xFF7C5CFC),
                    () => _exportShops(context),
                  ),
                  _buildActionCard(
                    context,
                    'Estatísticas Base',
                    Icons.analytics_rounded,
                    const Color(0xFFF59E0B),
                    () => _showGeneralStats(context),
                  ),
                ],
              );
            }),
  
            const SizedBox(height: 40),
            const Text(
              'Ferramentas de Intervenção',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            const SizedBox(height: 16),
  
            _buildListItem(
              context,
              'Buscar Usuário por Email',
              'Encontrar e modificar dados de usuário específicos.',
              Icons.search_rounded,
              const Color(0xFF4F8EF7),
              () => _searchUserByEmail(context),
            ),
            const SizedBox(height: 12),
            _buildListItem(
              context,
              'Enviar Notificação Manual',
              'Enviar push notification para usuários selecionados.',
              Icons.notifications_active_rounded,
              const Color(0xFFF59E0B),
              () => _sendManualNotification(context),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildListItem(BuildContext context, String title, String sub, IconData icon, Color color, VoidCallback onTap) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1A1D27),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.04)),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
        leading: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
          child: Icon(icon, color: color),
        ),
        title: Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        subtitle: Text(sub, style: const TextStyle(color: Colors.grey, fontSize: 12)),
        trailing: const Icon(Icons.chevron_right_rounded, color: Colors.grey),
        onTap: onTap,
      ),
    );
  }
  
  Widget _buildActionCard(BuildContext context, String title, IconData icon, Color color, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1D27),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withValues(alpha: 0.04)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: color.withValues(alpha: 0.1), shape: BoxShape.circle),
              child: Icon(icon, color: color, size: 28),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  void _showSubscriptionOverride(BuildContext context) async {
    final emailController = TextEditingController();
    String? selectedPlan = 'premium';

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Override de Assinatura'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: emailController,
              decoration: const InputDecoration(
                labelText: 'Email do usuário',
                hintText: 'usuario@example.com',
              ),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: selectedPlan,
              decoration: const InputDecoration(labelText: 'Novo Plano'),
              items: const [
                DropdownMenuItem(value: 'free', child: Text('Free')),
                DropdownMenuItem(value: 'start', child: Text('Start')),
                DropdownMenuItem(value: 'plus', child: Text('Plus')),
                DropdownMenuItem(value: 'pro', child: Text('Pro')),
              ],
              onChanged: (value) => selectedPlan = value,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () async {
              final email = emailController.text.trim();
              if (email.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Digite um email válido')),
                );
                return;
              }

              // Find user by email
              final usersSnap = await FirebaseFirestore.instance
                  .collection('users')
                  .where('email', isEqualTo: email)
                  .get();

              if (usersSnap.docs.isEmpty) {
                if (ctx.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Usuário não encontrado')),
                  );
                }
                return;
              }

              final userDoc = usersSnap.docs.first;
              await userDoc.reference.update({
                'plano': selectedPlan,
                'plano_expira': Timestamp.fromDate(
                  DateTime.now().add(const Duration(days: 365)),
                ),
              });

              if (ctx.mounted) Navigator.pop(ctx);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Plano alterado para $selectedPlan!')),
                );
              }
            },
            child: const Text('Aplicar'),
          ),
        ],
      ),
    );
  }

  void _exportUsers(BuildContext context) async {
    try {
      final usersSnap =
          await FirebaseFirestore.instance.collection('users').get();

      List<List<dynamic>> rows = [
        ['Nome', 'Email', 'Telefone', 'Tipo', 'Plano', 'Data Cadastro']
      ];

      for (var doc in usersSnap.docs) {
        final data = doc.data();
        rows.add([
          data['nome'] ?? '',
          data['email'] ?? '',
          data['telefone'] ?? '',
          data['tipo'] ?? '',
          data['plano'] ?? 'free',
          data['criado_em']?.toString() ?? '',
        ]);
      }

      // Implementing manual CSV generation
      final buffer = StringBuffer();
      for (var row in rows) {
        buffer.writeln(row.map((e) {
          final str = e.toString().replaceAll('"', '""');
          return '"$str"';
        }).join(','));
      }

      final directory = await getApplicationDocumentsDirectory();
      final file = File(
          '${directory.path}/usuarios_${DateTime.now().millisecondsSinceEpoch}.csv');
      await file.writeAsString(buffer.toString());

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Usuários exportados para: ${file.path}')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao exportar: $e')),
        );
      }
    }
  }

  void _exportShops(BuildContext context) async {
    try {
      final shopsSnap =
          await FirebaseFirestore.instance.collection('shops').get();

      List<List<dynamic>> rows = [
        ['Nome', 'Categoria', 'Telefone', 'Plano', 'Boost Ativo']
      ];

      for (var doc in shopsSnap.docs) {
        final data = doc.data();
        final boostExpires = data['boost_expires_at'] as Timestamp?;
        final isBoosted = boostExpires != null &&
            boostExpires.toDate().isAfter(DateTime.now());

        rows.add([
          data['nome'] ?? '',
          data['categoria'] ?? '',
          data['telefone'] ?? '',
          data['plan'] ?? 'free',
          isBoosted ? 'Sim' : 'Não',
        ]);
      }

      // Manual CSV generation
      final buffer = StringBuffer();
      for (var row in rows) {
        buffer.writeln(row.map((e) {
          final str = e.toString().replaceAll('"', '""');
          return '"$str"';
        }).join(','));
      }

      final directory = await getApplicationDocumentsDirectory();
      final file = File(
          '${directory.path}/negocios_${DateTime.now().millisecondsSinceEpoch}.csv');
      await file.writeAsString(buffer.toString());

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Negócios exportados para: ${file.path}')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao exportar: $e')),
        );
      }
    }
  }

  void _showGeneralStats(BuildContext context) async {
    final usersSnap =
        await FirebaseFirestore.instance.collection('users').get();
    final shopsSnap =
        await FirebaseFirestore.instance.collection('shops').get();
    final appointmentsSnap =
        await FirebaseFirestore.instance.collection('appointments').get();

    if (context.mounted) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Estatísticas Gerais'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Total de usuários: ${usersSnap.size}'),
              Text('Total de negócios: ${shopsSnap.size}'),
              Text('Total de agendamentos: ${appointmentsSnap.size}'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Fechar'),
            ),
          ],
        ),
      );
    }
  }

  void _searchUserByEmail(BuildContext context) async {
    final emailController = TextEditingController();

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Buscar Usuário'),
        content: TextField(
          controller: emailController,
          decoration: const InputDecoration(
            labelText: 'Email',
            hintText: 'usuario@example.com',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () async {
              final email = emailController.text.trim();
              if (email.isEmpty) {
                return;
              }

              final usersSnap = await FirebaseFirestore.instance
                  .collection('users')
                  .where('email', isEqualTo: email)
                  .get();

              if (ctx.mounted) Navigator.pop(ctx);

              if (usersSnap.docs.isEmpty) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Usuário não encontrado')),
                  );
                }
              } else {
                final data = usersSnap.docs.first.data();
                if (context.mounted) {
                  showDialog(
                    context: context,
                    builder: (c) => AlertDialog(
                      title: const Text('Usuário Encontrado'),
                      content: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Nome: ${data['nome'] ?? 'N/A'}'),
                          Text('Email: ${data['email'] ?? 'N/A'}'),
                          Text('Tipo: ${data['tipo'] ?? 'cliente'}'),
                          Text('Plano: ${data['plano'] ?? 'free'}'),
                        ],
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(c),
                          child: const Text('Fechar'),
                        ),
                      ],
                    ),
                  );
                }
              }
            },
            child: const Text('Buscar'),
          ),
        ],
      ),
    );
  }

  void _sendManualNotification(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Funcionalidade de notificação em desenvolvimento'),
      ),
    );
  }
}
