import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:markaai/core/theme/app_colors.dart';
import 'package:markaai/core/utils/format_utils.dart';

class AdminMonitoringWidget extends StatefulWidget {
  const AdminMonitoringWidget({super.key});

  @override
  State<AdminMonitoringWidget> createState() => _AdminMonitoringWidgetState();
}

class _AdminMonitoringWidgetState extends State<AdminMonitoringWidget> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final cardColor = cs.surface;
    final borderColor = cs.onSurface.withValues(alpha: 0.1);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Saúde das Edge Functions', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          _buildFunctionsGrid(cardColor, borderColor),
          const SizedBox(height: 32),
          const Text('Log de Auditoria Admin', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          _buildAuditLog(cardColor, borderColor),
        ],
      ),
    );
  }

  Widget _buildFunctionsGrid(Color cardColor, Color borderColor) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cols = constraints.maxWidth > 900 ? 3 : (constraints.maxWidth > 600 ? 2 : 1);
        return GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: cols,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
          childAspectRatio: 2.5,
          children: [
            _buildFunctionCard('stripe-webhook', 'Online', Colors.green, cardColor, borderColor),
            _buildFunctionCard('whatsapp-webhook', 'Online', Colors.green, cardColor, borderColor),
            _buildFunctionCard('reminders-cron', 'Executado há 5m', Colors.blue, cardColor, borderColor),
            _buildFunctionCard('emitir-nfse', 'Online', Colors.green, cardColor, borderColor),
            _buildFunctionCard('appointment-logic', 'Online', Colors.green, cardColor, borderColor),
          ],
        );
      },
    );
  }

  Widget _buildFunctionCard(String name, String status, Color color, Color cardColor, Color borderColor) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                Text(status, style: TextStyle(color: color, fontSize: 11)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAuditLog(Color cardColor, Color borderColor) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: Supabase.instance.client.from('admin_audit_log').stream(primaryKey: ['id']).order('created_at').limit(50),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final logs = snapshot.data!;

        return Container(
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: borderColor),
          ),
          child: logs.isEmpty 
            ? const Padding(padding: EdgeInsets.all(32), child: Center(child: Text('Nenhum log encontrado', style: TextStyle(color: Colors.grey))))
            : ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: logs.length,
                separatorBuilder: (context, index) => Divider(color: borderColor, height: 1),
                itemBuilder: (context, index) {
                  final log = logs[index];
                  return ListTile(
                    dense: true,
                    leading: const Icon(Icons.history_toggle_off, size: 18),
                    title: Text('${log['action']} em ${log['target_type']}'),
                    subtitle: Text(FormatUtils.formatDateTime(DateTime.parse(log['created_at']))),
                    trailing: Text(log['admin_id'].toString().substring(0, 5), style: const TextStyle(fontSize: 10, color: Colors.grey)),
                  );
                },
              ),
        );
      },
    );
  }
}
