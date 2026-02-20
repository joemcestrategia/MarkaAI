import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../../../core/theme/app_colors.dart';

class AdminSupportWidget extends StatelessWidget {
  const AdminSupportWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Quick Actions
          const Text(
            'Ações Rápidas',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),

          Wrap(
            spacing: 16,
            runSpacing: 16,
            children: [
              _buildActionCard(
                context,
                'Gerenciar Assinatura',
                Icons.card_membership,
                Colors.blue,
                () => _showSubscriptionOverride(context),
              ),
              _buildActionCard(
                context,
                'Exportar Usuários CSV',
                Icons.download,
                Colors.green,
                () => _exportUsers(context),
              ),
              _buildActionCard(
                context,
                'Exportar Negócios CSV',
                Icons.file_download,
                Colors.orange,
                () => _exportShops(context),
              ),
              _buildActionCard(
                context,
                'Estatísticas Gerais',
                Icons.analytics,
                AppColors.primaryPurple,
                () => _showGeneralStats(context),
              ),
            ],
          ),

          const SizedBox(height: 32),

          // Manual Intervention Tools
          const Text(
            'Ferramentas de Intervenção Manual',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),

          Card(
            child: ListTile(
              leading: const Icon(Icons.search, color: AppColors.primaryPurple),
              title: const Text('Buscar Usuário por Email'),
              subtitle: const Text('Encontrar e modificar dados de usuário'),
              trailing: const Icon(Icons.arrow_forward),
              onTap: () => _searchUserByEmail(context),
            ),
          ),

          const SizedBox(height: 8),

          Card(
            child: ListTile(
              leading: const Icon(Icons.notifications, color: Colors.orange),
              title: const Text('Enviar Notificação Manual'),
              subtitle: const Text('Enviar push notification para usuários'),
              trailing: const Icon(Icons.arrow_forward),
              onTap: () => _sendManualNotification(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionCard(
    BuildContext context,
    String title,
    IconData icon,
    Color color,
    VoidCallback onTap,
  ) {
    return SizedBox(
      width: 200,
      child: Card(
        elevation: 2,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: color, size: 32),
                ),
                const SizedBox(height: 12),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
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
                DropdownMenuItem(value: 'premium', child: Text('Premium')),
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
