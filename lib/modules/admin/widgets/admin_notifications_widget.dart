import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:markaai/core/theme/app_colors.dart';
import 'package:markaai/core/utils/format_utils.dart';

class AdminNotificationsWidget extends StatefulWidget {
  const AdminNotificationsWidget({super.key});

  @override
  State<AdminNotificationsWidget> createState() => _AdminNotificationsWidgetState();
}

class _AdminNotificationsWidgetState extends State<AdminNotificationsWidget> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final cardColor = cs.surface;
    final borderColor = cs.onSurface.withValues(alpha: 0.1);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildWhatsAppHealth(cardColor, borderColor),
          const SizedBox(height: 24),
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 12,
            children: [
              const Text('Comunicados In-App', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ElevatedButton.icon(
                onPressed: _showCreateAnnouncementDialog,
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Novo', style: TextStyle(fontSize: 13)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: cs.primary, 
                  foregroundColor: cs.onPrimary,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildAnnouncementsList(cardColor, borderColor),
        ],
      ),
    );
  }

  Widget _buildWhatsAppHealth(Color cardColor, Color borderColor) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.phone_android, color: Theme.of(context).colorScheme.tertiary, size: 20),
              const SizedBox(width: 12),
              const Expanded(child: Text('WhatsApp (Meta API)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14))),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: Theme.of(context).colorScheme.tertiary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
                child: Text('ONLINE', style: TextStyle(color: Theme.of(context).colorScheme.tertiary, fontWeight: FontWeight.bold, fontSize: 10)),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              _buildMetric('Enviadas (Hoje)', '1.240', Colors.blue),
              _buildMetric('Falhas', '2', Colors.red),
              _buildMetric('Templates', '12', Colors.purple),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMetric(String label, String value, Color color) {
    return Expanded(
      child: Column(
        children: [
          Text(value, style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: color)),
          Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        ],
      ),
    );
  }

  Widget _buildAnnouncementsList(Color cardColor, Color borderColor) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: Supabase.instance.client.from('admin_announcements').stream(primaryKey: ['id']).order('created_at'),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final announcements = snapshot.data!;

        if (announcements.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(40.0),
              child: Text('Nenhum comunicado ativo', style: TextStyle(color: Colors.grey.withValues(alpha: 0.5))),
            ),
          );
        }

        return Column(
          children: announcements.map((a) => Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: ListTile(
              leading: _getAnnouncementIcon(a['type']),
              title: Text(a['title']),
              subtitle: Text(a['body'], maxLines: 1, overflow: TextOverflow.ellipsis),
              trailing: Switch(
                value: a['is_active'],
                onChanged: (v) async {
                  await Supabase.instance.client.from('admin_announcements').update({'is_active': v}).eq('id', a['id']);
                },
              ),
            ),
          )).toList(),
        );
      },
    );
  }

  Widget _getAnnouncementIcon(String? type) {
    switch (type) {
      case 'warning': return const Icon(Icons.warning_amber, color: Colors.orange);
      case 'critical': return const Icon(Icons.error_outline, color: Colors.red);
      case 'success': return const Icon(Icons.check_circle_outline, color: Colors.green);
      default: return const Icon(Icons.info_outline, color: Colors.blue);
    }
  }

  void _showCreateAnnouncementDialog() {
    final titleController = TextEditingController();
    final bodyController = TextEditingController();
    String type = 'info';

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Novo Comunicado'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: titleController, decoration: const InputDecoration(labelText: 'Título')),
              const SizedBox(height: 12),
              TextField(controller: bodyController, decoration: const InputDecoration(labelText: 'Mensagem'), maxLines: 3),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: type,
                items: const [
                  DropdownMenuItem(value: 'info', child: Text('Informativo')),
                  DropdownMenuItem(value: 'warning', child: Text('Aviso')),
                  DropdownMenuItem(value: 'critical', child: Text('Crítico')),
                ],
                onChanged: (v) => setState(() => type = v!),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
            ElevatedButton(
              onPressed: () async {
                final admin = Supabase.instance.client.auth.currentUser;
                await Supabase.instance.client.from('admin_announcements').insert({
                  'title': titleController.text,
                  'body': bodyController.text,
                  'type': type,
                  'created_by': admin?.id,
                });
                if (context.mounted) Navigator.pop(context);
              },
              child: const Text('Publicar'),
            ),
          ],
        ),
      ),
    );
  }
}
