import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';
import 'dart:io' if (dart.library.html) 'package:markaai/core/utils/io_stub.dart' as io;
import 'package:path_provider/path_provider.dart';
import '../../support/admin_tickets_page.dart';

class AdminSupportWidget extends StatelessWidget {
  const AdminSupportWidget({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final textColor = cs.onSurface;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildTicketsBanner(context),
          const SizedBox(height: 32),
          Text(
            'Ações Rápidas de Suporte',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: textColor),
          ),
          const SizedBox(height: 8),
          Text(
            'Gerenciamento manual, exportação de dados e utilitários administrativos.',
            style: TextStyle(color: textColor.withValues(alpha: 0.6), fontSize: 14),
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
          Text(
            'Ferramentas de Intervenção',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: textColor),
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
    );
  }

  Widget _buildListItem(BuildContext context, String title, String sub, IconData icon, Color color, VoidCallback onTap) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.onSurface.withValues(alpha: 0.1)),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
        leading: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
          child: Icon(icon, color: color),
        ),
        title: Text(title, style: TextStyle(color: cs.onSurface, fontWeight: FontWeight.bold)),
        subtitle: Text(sub, style: TextStyle(color: cs.onSurface.withValues(alpha: 0.6), fontSize: 12)),
        trailing: Icon(Icons.chevron_right_rounded, color: cs.onSurface.withValues(alpha: 0.3)),
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
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: cs.onSurface.withValues(alpha: 0.1)),
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
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: cs.onSurface, fontWeight: FontWeight.bold, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  void _showSubscriptionOverride(BuildContext context) async {
    final emailController = TextEditingController();
    String? selectedPlan = 'pro';

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
                if (email.isEmpty) return;

                try {
                  final supabase = Supabase.instance.client;
                  final res = await supabase.from('users').select().eq('email', email).maybeSingle();

                  if (res == null) return;

                  await supabase.from('users').update({
                    'plan': selectedPlan,
                    'role': 'business',
                    'plano_expira': DateTime.now().add(const Duration(days: 365)).toIso8601String(),
                  }).eq('id', res['id']);

                  if (ctx.mounted) Navigator.pop(ctx);
                } catch (e) {
                  debugPrint('Erro: $e');
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
      final buffer = StringBuffer();
      buffer.writeln('Nome,Email,Telefone,Tipo,Plano,Data Cadastro');
      for (var data in users) {
        buffer.writeln('${data['name']},${data['email']},${data['phone']},${data['role']},${data['plan']},${data['created_at']}');
      }

      if (kIsWeb) return;

      final directory = await getApplicationDocumentsDirectory();
      final file = io.File('${directory.path}/usuarios_${DateTime.now().millisecondsSinceEpoch}.csv');
      await file.writeAsString(buffer.toString());
    } catch (e) {
      debugPrint('Erro: $e');
    }
  }

  void _exportShops(BuildContext context) async {
    try {
      final supabase = Supabase.instance.client;
      final shops = await supabase.from('shops').select();
      final buffer = StringBuffer();
      buffer.writeln('Nome,Categoria,Telefone,Plano,Boost Ativo');
      for (var data in shops) {
        buffer.writeln('${data['name']},${data['categoria']},${data['phone']},${data['plan_id']},false');
      }

      if (kIsWeb) return;

      final directory = await getApplicationDocumentsDirectory();
      final file = io.File('${directory.path}/negocios_${DateTime.now().millisecondsSinceEpoch}.csv');
      await file.writeAsString(buffer.toString());
    } catch (e) {
      debugPrint('Erro: $e');
    }
  }

  void _showGeneralStats(BuildContext context) async {
    final supabase = Supabase.instance.client;
    final results = await Future.wait([
      supabase.from('users').count(CountOption.exact),
      supabase.from('shops').count(CountOption.exact),
      supabase.from('appointments').count(CountOption.exact),
    ]);

    if (context.mounted) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Estatísticas Gerais'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Total de usuários: ${results[0]}'),
              Text('Total de negócios: ${results[1]}'),
              Text('Total de agendamentos: ${results[2]}'),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Fechar')),
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
        content: TextField(controller: emailController, decoration: const InputDecoration(labelText: 'Email')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () async {
              final email = emailController.text.trim();
              if (email.isEmpty) return;
              final res = await Supabase.instance.client.from('users').select().eq('email', email).maybeSingle();
              if (ctx.mounted) Navigator.pop(ctx);
              if (res != null && context.mounted) {
                showDialog(
                  context: context,
                  builder: (c) => AlertDialog(
                    title: const Text('Usuário Encontrado'),
                    content: Text('Nome: ${res['name']}\nEmail: ${res['email']}\nPlano: ${res['plan']}'),
                    actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('Fechar'))],
                  ),
                );
              }
            },
            child: const Text('Buscar'),
          ),
        ],
      ),
    );
  }

  void _sendManualNotification(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Em desenvolvimento')));
  }
}
