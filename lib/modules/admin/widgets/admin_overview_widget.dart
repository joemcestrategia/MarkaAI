import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_colors.dart';

class AdminOverviewWidget extends StatelessWidget {
  const AdminOverviewWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Stats Cards
          StreamBuilder<List<QuerySnapshot>>(
            stream: _getStatsStream(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              final usersSnap = snapshot.data![0];
              final shopsSnap = snapshot.data![1];
              final appointmentsSnap = snapshot.data![2];

              final totalUsers = usersSnap.size;
              final totalShops = shopsSnap.size;
              final totalAppointments = appointmentsSnap.size;

              // Calculate revenue
              double totalRevenue = 0;
              for (var doc in appointmentsSnap.docs) {
                final data = doc.data() as Map<String, dynamic>;
                final valor = data['valor_pago'];
                if (valor != null) {
                  totalRevenue += double.tryParse(valor.toString()) ?? 0;
                }
              }

              // Count business owners vs clients
              int owners = 0;
              int clients = 0;
              for (var doc in usersSnap.docs) {
                final data = doc.data() as Map<String, dynamic>;
                final tipo = data['tipo'] ?? '';
                if (tipo == 'dono' || tipo == 'business') {
                  owners++;
                } else {
                  clients++;
                }
              }

              return Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _buildStatCard(
                          context,
                          'Usuários Totais',
                          totalUsers.toString(),
                          Icons.people,
                          AppColors.primaryPurple,
                          subtitle: '$clients clientes â€¢ $owners donos',
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _buildStatCard(
                          context,
                          'Negócios',
                          totalShops.toString(),
                          Icons.store,
                          Colors.blue,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: _buildStatCard(
                          context,
                          'Agendamentos',
                          totalAppointments.toString(),
                          Icons.calendar_today,
                          Colors.orange,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _buildStatCard(
                          context,
                          'Receita Total',
                          'R\$ ${NumberFormat.currency(symbol: '', decimalDigits: 2).format(totalRevenue)}',
                          Icons.attach_money,
                          Colors.green,
                        ),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),

          const SizedBox(height: 32),

          // Recent Activity
          const Text(
            'Atividade Recente',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),

          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('appointments')
                .orderBy('criado_em', descending: true)
                .limit(10)
                .snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              final appointments = snapshot.data!.docs;

              if (appointments.isEmpty) {
                return const Card(
                  child: Padding(
                    padding: EdgeInsets.all(32.0),
                    child: Center(
                      child: Text('Nenhum agendamento recente'),
                    ),
                  ),
                );
              }

              return Card(
                child: ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: appointments.length,
                  separatorBuilder: (context, index) =>
                      const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final doc = appointments[index];
                    final data = doc.data() as Map<String, dynamic>;

                    final clientName = data['client_nome'] ?? 'Cliente';
                    final serviceName =
                        data['servico_nome'] ?? data['servico'] ?? 'Serviço';
                    final status = data['status'] ?? 'pendente';
                    final timestamp = data['criado_em'] as Timestamp?;

                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor:
                            _getStatusColor(status).withValues(alpha: 0.1),
                        child: Icon(
                          _getStatusIcon(status),
                          color: _getStatusColor(status),
                          size: 20,
                        ),
                      ),
                      title: Text(serviceName),
                      subtitle: Text('Cliente: $clientName'),
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            status.toUpperCase(),
                            style: TextStyle(
                              color: _getStatusColor(status),
                              fontWeight: FontWeight.bold,
                              fontSize: 11,
                            ),
                          ),
                          if (timestamp != null)
                            Text(
                              _formatTimestamp(timestamp),
                              style: TextStyle(
                                color: Colors.grey[600],
                                fontSize: 11,
                              ),
                            ),
                        ],
                      ),
                    );
                  },
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Stream<List<QuerySnapshot>> _getStatsStream() async* {
    final results = await Future.wait([
      FirebaseFirestore.instance.collection('users').get(),
      FirebaseFirestore.instance.collection('shops').get(),
      FirebaseFirestore.instance.collection('appointments').get(),
    ]);
    yield results;
  }

  Widget _buildStatCard(
    BuildContext context,
    String title,
    String value,
    IconData icon,
    Color color, {
    String? subtitle,
  }) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: color, size: 24),
                ),
                const Spacer(),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 8),
              Text(
                subtitle,
                style: TextStyle(
                  color: Colors.grey[500],
                  fontSize: 12,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'confirmado':
      case 'concluido':
        return Colors.green;
      case 'cancelado':
        return Colors.red;
      case 'pendente':
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status.toLowerCase()) {
      case 'confirmado':
        return Icons.check_circle;
      case 'concluido':
        return Icons.done_all;
      case 'cancelado':
        return Icons.cancel;
      case 'pendente':
        return Icons.schedule;
      default:
        return Icons.help;
    }
  }

  String _formatTimestamp(Timestamp timestamp) {
    final date = timestamp.toDate();
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays == 0) {
      if (difference.inHours == 0) {
        return '${difference.inMinutes}m';
      }
      return '${difference.inHours}h';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}d';
    }
    return DateFormat('dd/MM').format(date);
  }
}
