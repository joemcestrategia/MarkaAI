import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';

class AdminOverviewWidget extends StatelessWidget {
  const AdminOverviewWidget({super.key});

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
            // Stats Row
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

                double totalRevenue = 0;
                for (var doc in appointmentsSnap.docs) {
                  final data = doc.data() as Map<String, dynamic>;
                  final valor = data['valor_pago'];
                  if (valor != null) {
                    totalRevenue += double.tryParse(valor.toString()) ?? 0;
                  }
                }

                return Column(
                  children: [
                    LayoutBuilder(builder: (context, constraints) {
                      final cols = constraints.maxWidth > 1200 ? 4 : (constraints.maxWidth > 700 ? 2 : 1);
                      return GridView.count(
                        crossAxisCount: cols,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        crossAxisSpacing: 24,
                        mainAxisSpacing: 24,
                        childAspectRatio: 1.8,
                        children: [
                          _buildPremiumStatCard(
                            'Usuários Ativos',
                            totalUsers.toString(),
                            Icons.people_alt_rounded,
                            const Color(0xFF4F8EF7),
                            '+8.2%',
                          ),
                          _buildPremiumStatCard(
                            'Negócios (Lojas)',
                            totalShops.toString(),
                            Icons.storefront_rounded,
                            const Color(0xFF7C5CFC),
                            '+12.4%',
                          ),
                          _buildPremiumStatCard(
                            'Agendamentos',
                            totalAppointments.toString(),
                            Icons.calendar_today_rounded,
                            const Color(0xFF22C55E),
                            '+4.1%',
                          ),
                          _buildPremiumStatCard(
                            'Receita Estimada',
                            'R\$ ${NumberFormat.currency(symbol: '', decimalDigits: 0).format(totalRevenue)}',
                            Icons.payments_rounded,
                            const Color(0xFFF59E0B),
                            '+15.8%',
                          ),
                        ],
                      );
                    }),
                    const SizedBox(height: 32),
                    // Main Charts Row
                    LayoutBuilder(builder: (context, constraints) {
                      final isDesktop = constraints.maxWidth > 1000;
                      return Flex(
                        direction: isDesktop ? Axis.horizontal : Axis.vertical,
                        children: [
                          Expanded(
                            flex: isDesktop ? 3 : 0,
                            child: _buildRevenueChart(),
                          ),
                          if (isDesktop) const SizedBox(width: 24),
                          if (!isDesktop) const SizedBox(height: 24),
                          Expanded(
                            flex: isDesktop ? 2 : 0,
                            child: _buildPlanDonut(shopsSnap.docs),
                          ),
                        ],
                      );
                    }),
                    const SizedBox(height: 32),
                    _buildSubscriptionAnalytics(shopsSnap.docs),
                  ],
                );
              },
            ),

            const SizedBox(height: 32),
            const Text(
              'Atividade Recente',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            const SizedBox(height: 16),
            _buildRecentActivityList(),
          ],
        ),
      ),
    );
  }

  Widget _buildPremiumStatCard(String title, String value, IconData icon, Color color, String trend) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1D27),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.04)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 24),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.arrow_upward, color: Colors.green, size: 10),
                    const SizedBox(width: 4),
                    Text(trend, style: const TextStyle(color: Colors.green, fontSize: 10, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: TextStyle(color: Colors.grey[500], fontSize: 13, fontWeight: FontWeight.w500)),
              const SizedBox(height: 4),
              Text(value, style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w800)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRevenueChart() {
    return Container(
      height: 400,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1D27),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.04)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Receita Mensal (Estimativa)',
                  style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
              Icon(Icons.more_horiz, color: Colors.grey),
            ],
          ),
          const SizedBox(height: 32),
          Expanded(
            child: LineChart(
              LineChartData(
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (value) => FlLine(
                    color: Colors.white.withOpacity(0.04),
                    strokeWidth: 1,
                  ),
                ),
                titlesData: const FlTitlesData(
                  show: true,
                  rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 40,
                      interval: 20000,
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                    ),
                  ),
                ),
                borderData: FlBorderData(show: false),
                lineBarsData: [
                  LineChartBarData(
                    spots: const [
                      FlSpot(0, 10000),
                      FlSpot(2, 25000),
                      FlSpot(4, 22000),
                      FlSpot(6, 45000),
                      FlSpot(8, 55000),
                      FlSpot(10, 78000),
                      FlSpot(11, 85000),
                    ],
                    isCurved: true,
                    color: const Color(0xFF4F8EF7),
                    barWidth: 4,
                    isStrokeCapRound: true,
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(
                      show: true,
                      gradient: LinearGradient(
                        colors: [
                          const Color(0xFF4F8EF7).withOpacity(0.3),
                          const Color(0xFF4F8EF7).withOpacity(0),
                        ],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlanDonut(List<QueryDocumentSnapshot> shops) {
    Map<String, int> planCounts = {'free': 0, 'start': 0, 'plus': 0, 'pro': 0};
    for (var doc in shops) {
      final data = doc.data() as Map<String, dynamic>;
      final plan = (data['plan'] ?? 'free').toString().toLowerCase();
      if (planCounts.containsKey(plan)) {
        planCounts[plan] = planCounts[plan]! + 1;
      }
    }

    return Container(
      height: 400,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1D27),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.04)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Assinaturas por Plano',
              style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 32),
          Expanded(
            child: PieChart(
              PieChartData(
                sectionsSpace: 8,
                centerSpaceRadius: 60,
                sections: [
                  PieChartSectionData(
                      value: planCounts['free']!.toDouble(),
                      color: Colors.grey.withOpacity(0.4),
                      radius: 20,
                      showTitle: false),
                  PieChartSectionData(
                      value: planCounts['start']!.toDouble(),
                      color: const Color(0xFF4F8EF7),
                      radius: 20,
                      showTitle: false),
                  PieChartSectionData(
                      value: planCounts['plus']!.toDouble(),
                      color: const Color(0xFF7C5CFC),
                      radius: 20,
                      showTitle: false),
                  PieChartSectionData(
                      value: planCounts['pro']!.toDouble(),
                      color: const Color(0xFF22C55E),
                      radius: 20,
                      showTitle: false),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          _buildLegend('Trial/Free', planCounts['free']!, Colors.grey),
          _buildLegend('Start', planCounts['start']!, const Color(0xFF4F8EF7)),
          _buildLegend('Plus', planCounts['plus']!, const Color(0xFF7C5CFC)),
          _buildLegend('Pro', planCounts['pro']!, const Color(0xFF22C55E)),
        ],
      ),
    );
  }

  Widget _buildLegend(String label, int count, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
              const SizedBox(width: 12),
              Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
            ],
          ),
          Text(count.toString(), style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildRecentActivityList() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('appointments').orderBy('criado_em', descending: true).limit(6).snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox();
        final docs = snapshot.data!.docs;
        return Column(
          children: docs.map((doc) {
            final data = doc.data() as Map<String, dynamic>;
            final servico = data['servico_nome'] ?? 'Serviço';
            final cliente = data['client_nome'] ?? 'Cliente';
            final status = (data['status'] ?? 'pendente').toString().toLowerCase();
            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1D27),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withOpacity(0.02)),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: _getStatusColor(status).withOpacity(0.1),
                    child: Icon(_getStatusIcon(status), color: _getStatusColor(status), size: 20),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(servico, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        Text('Cliente: $cliente', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                      ],
                    ),
                  ),
                  Text(status.toUpperCase(),
                      style: TextStyle(color: _getStatusColor(status), fontSize: 10, fontWeight: FontWeight.bold)),
                ],
              ),
            );
          }).toList(),
        );
      },
    );
  }

  Widget _buildSubscriptionAnalytics(List<QueryDocumentSnapshot> shops) {
    Map<String, Map<String, dynamic>> stats = {
      'free': {'name': 'Free', 'paidCount': 0, 'manualCount': 0, 'price': 0.0},
      'start': {'name': 'Start', 'paidCount': 0, 'manualCount': 0, 'price': 29.90},
      'plus': {'name': 'Plus', 'paidCount': 0, 'manualCount': 0, 'price': 59.90},
      'pro': {'name': 'Pro', 'paidCount': 0, 'manualCount': 0, 'price': 99.90},
    };

    for (var doc in shops) {
      final data = doc.data() as Map<String, dynamic>;
      final plan = (data['plan'] ?? 'free').toString().toLowerCase();
      final sub = data['subscription'] as Map<String, dynamic>?;
      final trialActive = data['trial_active'] == true;

      if (!stats.containsKey(plan)) continue;
      bool isPaid = sub != null && sub['status'] == 'active' && !trialActive;
      if (plan == 'free') {
        stats['free']!['manualCount']++;
      } else {
        if (isPaid) {
          stats[plan]!['paidCount']++;
        } else {
          stats[plan]!['manualCount']++;
        }
      }
    }

    double totalPaidRevenue = 0;
    stats.forEach((key, val) => totalPaidRevenue += (val['paidCount'] as int) * (val['price'] as double));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Receita de Assinaturas', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
            Text('Faturamento: R\$ ${totalPaidRevenue.toStringAsFixed(2)}',
                style: const TextStyle(color: Color(0xFF22C55E), fontWeight: FontWeight.bold)),
          ],
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: const Color(0xFF1A1D27),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withOpacity(0.04)),
          ),
          child: Column(
            children: [
              _buildPlanRow('PLANO', 'TOTAL', 'PAGOS', 'MANUAL', isHeader: true),
              const Divider(color: Colors.white10),
              ...stats.values.map((s) => _buildPlanRow(
                    s['name'],
                    (s['paidCount'] + s['manualCount']).toString(),
                    s['paidCount'].toString(),
                    s['manualCount'].toString(),
                  )),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPlanRow(String plan, String total, String paid, String manual, {bool isHeader = false}) {
    final style = TextStyle(
      fontWeight: isHeader ? FontWeight.bold : FontWeight.normal,
      fontSize: isHeader ? 11 : 13,
      color: isHeader ? Colors.grey : Colors.white70,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Expanded(flex: 2, child: Text(plan, style: style)),
          Expanded(child: Text(total, textAlign: TextAlign.center, style: style)),
          Expanded(
              child: Text(paid,
                  textAlign: TextAlign.center,
                  style: style.copyWith(color: isHeader ? null : const Color(0xFF22C55E)))),
          Expanded(
              child: Text(manual,
                  textAlign: TextAlign.center,
                  style: style.copyWith(color: isHeader ? null : const Color(0xFFF59E0B)))),
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

  Color _getStatusColor(String status) {
    if (status.contains('confirmado') || status.contains('concluido')) return Colors.green;
    if (status.contains('cancelado')) return Colors.red;
    return Colors.orange;
  }

  IconData _getStatusIcon(String status) {
    if (status.contains('confirmado')) return Icons.check_circle_outline;
    if (status.contains('concluido')) return Icons.done_all;
    if (status.contains('cancelado')) return Icons.cancel_outlined;
    return Icons.schedule;
  }
}
