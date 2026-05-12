import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:markaai/core/theme/app_colors.dart';
// import 'package:markaai/core/utils/format_utils.dart';

class AdminFinanceWidget extends StatefulWidget {
  const AdminFinanceWidget({super.key});

  @override
  State<AdminFinanceWidget> createState() => _AdminFinanceWidgetState();
}

class _AdminFinanceWidgetState extends State<AdminFinanceWidget> {
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
          const Text('Inadimplências e Pendências', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          _buildInadimplenciasTable(cardColor, borderColor),
          const SizedBox(height: 32),
          const Text('Histórico de Eventos Stripe', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          _buildStripeEventsList(cardColor, borderColor),
        ],
      ),
    );
  }

  Widget _buildInadimplenciasTable(Color cardColor, Color borderColor) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: Supabase.instance.client
          .from('shops')
          .stream(primaryKey: ['id']),
          // .filter('subscription->>status', 'in', '("past_due", "canceled", "unpaid")'), // Erro: .filter não existe no stream builder
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final shops = snapshot.data!;

        if (shops.isEmpty) {
          return Container(
            width: double.infinity,
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: cardColor,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: borderColor),
            ),
            child: const Column(
              children: [
                Icon(Icons.check_circle_outline, color: Colors.green, size: 48),
                SizedBox(height: 16),
                Text('Nenhuma inadimplência encontrada', style: TextStyle(color: Colors.grey)),
              ],
            ),
          );
        }

        return Container(
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: borderColor),
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columns: const [
                DataColumn(label: Text('Loja')),
                DataColumn(label: Text('Plano')),
                DataColumn(label: Text('Status')),
                DataColumn(label: Text('Ação')),
              ],
              rows: shops.map((shop) {
                final sub = shop['subscription'] as Map<String, dynamic>?;
                return DataRow(cells: [
                  DataCell(Text(shop['name'] ?? 'N/A')),
                  DataCell(Text(sub?['plano']?.toUpperCase() ?? 'N/A')),
                  DataCell(Text(sub?['status'] ?? 'N/A', style: TextStyle(color: Theme.of(context).colorScheme.error))),
                  DataCell(
                    IconButton(
                      icon: Icon(Icons.open_in_new, size: 18, color: Theme.of(context).colorScheme.primary),
                      onPressed: () {
                        // TODO: Abrir detalhes
                      },
                    ),
                  ),
                ]);
              }).toList(),
            ),
          ),
        );
      },
    );
  }

  Widget _buildStripeEventsList(Color cardColor, Color borderColor) {
    return Container(
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
      ),
      child: const Center(
        child: Padding(
          padding: EdgeInsets.all(32.0),
          child: Column(
            children: [
              Icon(Icons.history, color: Colors.grey, size: 48),
              SizedBox(height: 16),
              Text('Log de eventos Stripe sincronizando...', style: TextStyle(color: Colors.grey)),
            ],
          ),
        ),
      ),
    );
  }
}
