import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';
import 'dart:io' if (dart.library.html) 'package:flutter_application_1/core/utils/io_stub.dart' as io;
import 'package:path_provider/path_provider.dart';
import '../../support/admin_tickets_page.dart';

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
            // --- Painel de Tickets ---
            _buildTicketsBanner(context),
            const SizedBox(height: 32),

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
  
  Widget _buildTicketsBanner(BuildContext context) {
    return InkWell(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminTicketsPage())),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF4F8EF7), Color(0xFF7C5CFC)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF4F8EF7).withValues(alpha: 0.3),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(Icons.confirmation_number_rounded, color: Colors.white, size: 32),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Painel de Tickets',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Gerenciar tickets de suporte, SLA, relatórios e fila de atendimento.',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 13),
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 24),
          ],
        ),
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
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => AlertDialog(
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
                value: selectedPlan,
                decoration: const InputDecoration(labelText: 'Novo Plano'),
                items: const [
                  DropdownMenuItem(value: 'free', child: Text('Free')),
                  DropdownMenuItem(value: 'start', child: Text('Start')),
                  DropdownMenuItem(value: 'plus', child: Text('Plus')),
                  DropdownMenuItem(value: 'pro', child: Text('Pro')),
                ],
                onChanged: (value) {
                  if (value != null) setModalState(() => selectedPlan = value);
                },
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

                try {
                  final supabase = Supabase.instance.client;
                  final res = await supabase
                      .from('users')
                      .select()
                      .eq('email', email)
                      .maybeSingle();

                  if (res == null) {
                    if (ctx.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Usuário não encontrado')),
                      );
                    }
                    return;
                  }

                  await supabase.from('users').update({
                    'plan': selectedPlan,
                    'role': 'business', // Ensuring they are business if they have a plan
                    'plano_expira': DateTime.now().add(const Duration(days: 365)).toIso8601String(),
                  }).eq('id', res['id']);

                  if (ctx.mounted) Navigator.pop(ctx);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Plano alterado para $selectedPlan!')),
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Erro ao alterar plano: $e')),
                    );
                  }
                }
              },
              child: const Text('Aplicar'),
            ),
          ],
        ),
      ),
    );
  }

  void _exportUsers(BuildContext context) async {
    try {
      final supabase = Supabase.instance.client;
      final users = await supabase.from('users').select();

      List<List<dynamic>> rows = [
        ['Nome', 'Email', 'Telefone', 'Tipo', 'Plano', 'Data Cadastro']
      ];

      for (var data in users) {
        rows.add([
          data['name'] ?? data['nome'] ?? '',
          data['email'] ?? '',
          data['phone'] ?? data['telefone'] ?? '',
          data['role'] ?? data['tipo'] ?? '',
          data['plan'] ?? data['plano'] ?? 'free',
          (data['created_at'] ?? data['criado_em'])?.toString() ?? '',
        ]);
      }

      final buffer = StringBuffer();
      for (var row in rows) {
        buffer.writeln(row.map((e) {
          final str = e.toString().replaceAll('"', '""');
          return '"$str"';
        }).join(','));
      }

      if (kIsWeb) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Exportação não disponível na Web por este método.')),
          );
        }
        return;
      }

      final directory = await getApplicationDocumentsDirectory();
      final file = io.File(
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
      final supabase = Supabase.instance.client;
      final shops = await supabase.from('shops').select();

      List<List<dynamic>> rows = [
        ['Nome', 'Categoria', 'Telefone', 'Plano', 'Boost Ativo']
      ];

      for (var data in shops) {
        final boostExpiresStr = data['boost_expires_at'] as String?;
        bool isBoosted = false;
        if (boostExpiresStr != null) {
          final expiresAt = DateTime.tryParse(boostExpiresStr);
          isBoosted = expiresAt != null && expiresAt.isAfter(DateTime.now());
        }

        rows.add([
          data['name'] ?? data['nome'] ?? '',
          data['categoria'] ?? '',
          data['phone'] ?? data['telefone'] ?? '',
          data['plan_id'] ?? data['plan'] ?? 'free',
          isBoosted ? 'Sim' : 'Não',
        ]);
      }

      final buffer = StringBuffer();
      for (var row in rows) {
        buffer.writeln(row.map((e) {
          final str = e.toString().replaceAll('"', '""');
          return '"$str"';
        }).join(','));
      }

      if (kIsWeb) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Exportação não disponível na Web por este método.')),
          );
        }
        return;
      }

      final directory = await getApplicationDocumentsDirectory();
      final file = io.File(
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
    final supabase = Supabase.instance.client;
    final results = await Future.wait([
      supabase.from('users').count(CountOption.exact),
      supabase.from('shops').count(CountOption.exact),
      supabase.from('appointments').count(CountOption.exact),
    ]);

    final totalUsers = results[0];
    final totalShops = results[1];
    final totalAppts = results[2];

    if (context.mounted) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Estatísticas Gerais'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Total de usuários: $totalUsers'),
              Text('Total de negócios: $totalShops'),
              Text('Total de agendamentos: $totalAppts'),
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
              if (email.isEmpty) return;

              final res = await Supabase.instance.client
                  .from('users')
                  .select()
                  .eq('email', email)
                  .maybeSingle();

              if (ctx.mounted) Navigator.pop(ctx);

              if (res == null) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Usuário não encontrado')),
                  );
                }
              } else {
                if (context.mounted) {
                  showDialog(
                    context: context,
                    builder: (c) => AlertDialog(
                      title: const Text('Usuário Encontrado'),
                      content: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Nome: ${res['name'] ?? res['nome'] ?? 'N/A'}'),
                          Text('Email: ${res['email'] ?? 'N/A'}'),
                          Text('Tipo: ${res['role'] ?? res['tipo'] ?? 'cliente'}'),
                          Text('Plano: ${res['plan'] ?? res['plano'] ?? 'free'}'),
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
      const SnackBar(content: Text('Funcionalidade de notificação em desenvolvimento')),
    );
  }
}
