import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';

class AdminOverviewWidget extends StatefulWidget {
  const AdminOverviewWidget({super.key});

  @override
  State<AdminOverviewWidget> createState() => _AdminOverviewWidgetState();
}

class _AdminOverviewWidgetState extends State<AdminOverviewWidget> {
  int? _selectedYear;
  int? _selectedMonth;

  final List<int> _years = List.generate(5, (index) => DateTime.now().year - index);
  
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final cardColor = cs.surface;
    final textColor = cs.onSurface;
    final subTextColor = cs.onSurface.withValues(alpha: 0.6);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Filtros
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: cardColor,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: cs.onSurface.withValues(alpha: 0.1)),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<int?>(
                      value: _selectedMonth,
                      isExpanded: true,
                      dropdownColor: cardColor,
                      icon: Icon(Icons.calendar_month, color: cs.primary, size: 20),
                      hint: Text('Mês: Todos', style: TextStyle(color: textColor, fontSize: 14)),
                      items: [
                        DropdownMenuItem<int?>(value: null, child: Text('Mês: Todos', style: TextStyle(color: textColor, fontSize: 14))),
                        ...List.generate(12, (index) => DropdownMenuItem(
                          value: index + 1,
                          child: Text('Mês: ${index + 1}', style: TextStyle(color: textColor, fontSize: 14)),
                        )),
                      ],
                      onChanged: (val) => setState(() => _selectedMonth = val),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: cardColor,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: cs.onSurface.withValues(alpha: 0.1)),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<int?>(
                      value: _selectedYear,
                      isExpanded: true,
                      dropdownColor: cardColor,
                      icon: Icon(Icons.calendar_today, color: cs.primary, size: 20),
                      hint: Text('Ano: Todos', style: TextStyle(color: textColor, fontSize: 14)),
                      items: [
                        DropdownMenuItem<int?>(value: null, child: Text('Ano: Todos', style: TextStyle(color: textColor, fontSize: 14))),
                        ..._years.map((year) => DropdownMenuItem(
                          value: year,
                          child: Text('Ano: $year', style: TextStyle(color: textColor, fontSize: 14)),
                        )),
                      ],
                      onChanged: (val) => setState(() => _selectedYear = val),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          // Stats Row
          FutureBuilder<List<List<Map<String, dynamic>>>>(
            future: _getStats(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Center(child: Text('Erro ao carregar estatísticas: ${snapshot.error}'));
              }

              final usersList = snapshot.data![0];
              final shopsList = snapshot.data![1];
              final appointmentsList = snapshot.data![2];

              final totalUsers = usersList.length;
              final totalShops = shopsList.length;
              final totalAppointments = appointmentsList.length;

              double appointmentRevenue = 0;
              for (var row in appointmentsList) {
                final valor = row['paid_value'] ?? row['valor_pago'];
                if (valor != null) {
                  appointmentRevenue += double.tryParse(valor.toString()) ?? 0;
                }
              }

              // Developer Revenue Calculation (Active Subscriptions)
              double devMonthlyRevenue = 0;
              for (var row in shopsList) {
                final plan = (row['plan_id'] ?? row['plan'] ?? 'free').toString().toLowerCase();
                final sub = row['subscription'] as Map<String, dynamic>?;
                final trialActive = row['trial_active'] == true;

                if (plan != 'free' && sub != null && sub['status'] == 'active' && !trialActive) {
                  switch (plan) {
                    case 'start': devMonthlyRevenue += 29.90; break;
                    case 'plus': devMonthlyRevenue += 59.90; break;
                    case 'pro': devMonthlyRevenue += 99.90; break;
                  }
                }
              }

              return Column(
                children: [
                  LayoutBuilder(builder: (context, constraints) {
                    final cols = constraints.maxWidth > 1400 ? 5 : (constraints.maxWidth > 1000 ? 4 : (constraints.maxWidth > 600 ? 3 : 2));
                    return GridView.count(
                      crossAxisCount: cols,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      crossAxisSpacing: 16,
                      mainAxisSpacing: 16,
                      childAspectRatio: constraints.maxWidth > 1400 ? 2.0 : (constraints.maxWidth > 600 ? 1.6 : 1.2),
                      children: [
                        _buildPremiumStatCard(
                          'Usuários',
                          totalUsers.toString(),
                          Icons.people_alt_rounded,
                          const Color(0xFF4F8EF7),
                          '+8%',
                          cardColor,
                          textColor,
                          subTextColor,
                          cs,
                        ),
                        _buildPremiumStatCard(
                          'Negócios',
                          totalShops.toString(),
                          Icons.storefront_rounded,
                          const Color(0xFF7C5CFC),
                          '+12%',
                          cardColor,
                          textColor,
                          subTextColor,
                          cs,
                        ),
                        _buildPremiumStatCard(
                          'Agendamentos',
                          totalAppointments.toString(),
                          Icons.calendar_today_rounded,
                          const Color(0xFF22C55E),
                          '+4%',
                          cardColor,
                          textColor,
                          subTextColor,
                          cs,
                        ),
                        _buildPremiumStatCard(
                          'Movimentação',
                          'R\$${NumberFormat.compactCurrency(symbol: '', decimalDigits: 0).format(appointmentRevenue)}',
                          Icons.payments_rounded,
                          const Color(0xFFF59E0B),
                          '+15%',
                          cardColor,
                          textColor,
                          subTextColor,
                          cs,
                        ),
                        _buildPremiumStatCard(
                          'Recorrência Dev',
                          'R\$${devMonthlyRevenue.toStringAsFixed(0)}',
                          Icons.insights_rounded,
                          const Color(0xFFEE4444),
                          'Recorrência',
                          cardColor,
                          textColor,
                          subTextColor,
                          cs,
                        ),
                      ],
                    );
                  }),
                  const SizedBox(height: 24),
                  // Main Charts Row
                  LayoutBuilder(builder: (context, constraints) {
                    final isDesktop = constraints.maxWidth > 1000;
                    return Flex(
                      direction: isDesktop ? Axis.horizontal : Axis.vertical,
                      children: [
                        Expanded(
                          flex: isDesktop ? 3 : 0,
                          child: _buildRevenueChart(cardColor, textColor, subTextColor),
                        ),
                        if (isDesktop) const SizedBox(width: 16),
                        if (!isDesktop) const SizedBox(height: 16),
                        Expanded(
                          flex: isDesktop ? 2 : 0,
                          child: _buildPlanDonut(shopsList, cardColor, textColor, subTextColor),
                        ),
                      ],
                    );
                  }),
                  const SizedBox(height: 24),
                  _buildSubscriptionAnalytics(shopsList, cardColor, textColor, subTextColor, devMonthlyRevenue),
                ],
              );
            },
          ),

          const SizedBox(height: 32),
          Text(
            'Atividade Recente',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: textColor),
          ),
          const SizedBox(height: 16),
          _buildRecentActivityList(cardColor, textColor, subTextColor),
        ],
      ),
    );
  }

  Widget _buildPremiumStatCard(String title, String value, IconData icon, Color color, String trend, Color cardColor, Color textColor, Color subTextColor, ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.onSurface.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: cs.tertiary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(trend, style: TextStyle(color: cs.tertiary, fontSize: 10, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: TextStyle(color: subTextColor, fontSize: 11, fontWeight: FontWeight.w500)),
              const SizedBox(height: 2),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(value, style: TextStyle(color: textColor, fontSize: 20, fontWeight: FontWeight.w800)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRevenueChart(Color cardColor, Color textColor, Color subTextColor) {
    return Container(
      height: 350,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: textColor.withValues(alpha: 0.04)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Receita Mensal (Estimativa)',
                  style: TextStyle(color: textColor, fontSize: 16, fontWeight: FontWeight.bold)),
              Icon(Icons.more_horiz, color: subTextColor),
            ],
          ),
          const SizedBox(height: 24),
          Expanded(
            child: LineChart(
              LineChartData(
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (value) => FlLine(
                    color: textColor.withValues(alpha: 0.04),
                    strokeWidth: 1,
                  ),
                ),
                titlesData: FlTitlesData(
                  show: true,
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 35,
                      getTitlesWidget: (value, meta) => Text(
                        '${(value/1000).toStringAsFixed(0)}k',
                        style: TextStyle(color: subTextColor, fontSize: 10),
                      ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (value, meta) => Padding(
                        padding: const EdgeInsets.only(top: 8.0),
                        child: Text(
                          ['Jan', 'Mar', 'Mai', 'Jul', 'Set', 'Nov'][((value % 12) / 2).floor()],
                          style: TextStyle(color: subTextColor, fontSize: 10),
                        ),
                      ),
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
                    barWidth: 3,
                    isStrokeCapRound: true,
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(
                      show: true,
                      gradient: LinearGradient(
                        colors: [
                          const Color(0xFF4F8EF7).withValues(alpha: 0.2),
                          const Color(0xFF4F8EF7).withValues(alpha: 0),
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

  Widget _buildPlanDonut(List<Map<String, dynamic>> shops, Color cardColor, Color textColor, Color subTextColor) {
    Map<String, int> planCounts = {'free': 0, 'start': 0, 'plus': 0, 'pro': 0};
    for (var row in shops) {
      final plan = (row['plan_id'] ?? row['plan'] ?? 'free').toString().toLowerCase();
      if (planCounts.containsKey(plan)) {
        planCounts[plan] = planCounts[plan]! + 1;
      }
    }

    return Container(
      height: 350,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: textColor.withValues(alpha: 0.04)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Assinaturas por Plano',
              style: TextStyle(color: textColor, fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 24),
          Expanded(
            child: PieChart(
              PieChartData(
                sectionsSpace: 4,
                centerSpaceRadius: 50,
                sections: [
                  PieChartSectionData(
                      value: planCounts['free']!.toDouble(),
                      color: Colors.grey.withValues(alpha: 0.3),
                      radius: 15,
                      showTitle: false),
                  PieChartSectionData(
                      value: planCounts['start']!.toDouble(),
                      color: const Color(0xFF4F8EF7),
                      radius: 15,
                      showTitle: false),
                  PieChartSectionData(
                      value: planCounts['plus']!.toDouble(),
                      color: const Color(0xFF7C5CFC),
                      radius: 15,
                      showTitle: false),
                  PieChartSectionData(
                      value: planCounts['pro']!.toDouble(),
                      color: const Color(0xFF22C55E),
                      radius: 15,
                      showTitle: false),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          _buildLegend('Free', planCounts['free']!, Colors.grey, subTextColor, textColor),
          _buildLegend('Start', planCounts['start']!, const Color(0xFF4F8EF7), subTextColor, textColor),
          _buildLegend('Plus', planCounts['plus']!, const Color(0xFF7C5CFC), subTextColor, textColor),
          _buildLegend('Pro', planCounts['pro']!, const Color(0xFF22C55E), subTextColor, textColor),
        ],
      ),
    );
  }

  Widget _buildLegend(String label, int count, Color color, Color subTextColor, Color textColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
              const SizedBox(width: 8),
              Text(label, style: TextStyle(color: subTextColor, fontSize: 11)),
            ],
          ),
          Text(count.toString(), style: TextStyle(color: textColor, fontSize: 11, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildRecentActivityList(Color cardColor, Color textColor, Color subTextColor) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: Supabase.instance.client
          .from('appointments')
          .select()
          .order('created_at', ascending: false)
          .limit(6),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox();
        final docs = snapshot.data!;
        return Column(
          children: docs.map((data) {
            final servico = data['service_name'] ?? data['servico_nome'] ?? 'Serviço';
            final cliente = data['client_name'] ?? data['client_nome'] ?? 'Cliente';
            final status = (data['status'] ?? 'pendente').toString().toLowerCase();
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: cardColor,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: textColor.withValues(alpha: 0.02)),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 16,
                    backgroundColor: _getStatusColor(status).withValues(alpha: 0.1),
                    child: Icon(_getStatusIcon(status), color: _getStatusColor(status), size: 16),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(servico, style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 13)),
                        Text('Cliente: $cliente', style: TextStyle(color: subTextColor, fontSize: 11)),
                      ],
                    ),
                  ),
                  Text(status.toUpperCase(),
                      style: TextStyle(color: _getStatusColor(status), fontSize: 9, fontWeight: FontWeight.bold)),
                ],
              ),
            );
          }).toList(),
        );
      },
    );
  }

  Widget _buildSubscriptionAnalytics(List<Map<String, dynamic>> shops, Color cardColor, Color textColor, Color subTextColor, double devRevenue) {
    Map<String, Map<String, dynamic>> stats = {
      'free': {'name': 'Free', 'paidCount': 0, 'manualCount': 0, 'price': 0.0},
      'start': {'name': 'Start', 'paidCount': 0, 'manualCount': 0, 'price': 29.90},
      'plus': {'name': 'Plus', 'paidCount': 0, 'manualCount': 0, 'price': 59.90},
      'pro': {'name': 'Pro', 'paidCount': 0, 'manualCount': 0, 'price': 99.90},
    };

    for (var row in shops) {
      final plan = (row['plan_id'] ?? row['plan'] ?? 'free').toString().toLowerCase();
      final sub = row['subscription'] as Map<String, dynamic>?;
      final trialActive = row['trial_active'] == true;

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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(child: Text('Receita de Assinaturas (DEV)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: textColor))),
            const SizedBox(width: 8),
            Text('Estimativa: R\$${devRevenue.toStringAsFixed(2)}',
                style: const TextStyle(color: Color(0xFF22C55E), fontWeight: FontWeight.bold)),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: textColor.withValues(alpha: 0.04)),
          ),
          child: Column(
            children: [
              _buildPlanRow('PLANO', 'TOTAL', 'PAGOS', 'MANUAL', subTextColor, textColor, isHeader: true),
              Divider(height: 24, color: textColor.withValues(alpha: 0.1)),
              ...stats.values.map((s) => _buildPlanRow(
                    s['name'],
                    (s['paidCount'] + s['manualCount']).toString(),
                    s['paidCount'].toString(),
                    s['manualCount'].toString(),
                    subTextColor, 
                    textColor,
                  )),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPlanRow(String plan, String total, String paid, String manual, Color subTextColor, Color textColor, {bool isHeader = false}) {
    final style = TextStyle(
      fontWeight: isHeader ? FontWeight.bold : FontWeight.normal,
      fontSize: isHeader ? 10 : 12,
      color: isHeader ? subTextColor : textColor.withValues(alpha: 0.8),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
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

  Future<List<List<Map<String, dynamic>>>> _getStats() async {
    final supabase = Supabase.instance.client;
    
    var usersQuery = supabase.from('users').select();
    var shopsQuery = supabase.from('shops').select();
    var appointmentsQuery = supabase.from('appointments').select();
    
    if (_selectedYear != null || _selectedMonth != null) {
      final now = DateTime.now();
      final year = _selectedYear ?? now.year;
      // Se tiver ano mas não mês, pegamos o ano todo. Se tiver mês mas não ano, assumimos o ano atual ou o selecionado.
      final startMonth = _selectedMonth ?? 1;
      final endMonth = _selectedMonth ?? 12;
      
      final startDate = DateTime(year, startMonth, 1).toIso8601String();
      final endDate = DateTime(year, endMonth + 1, 1).toIso8601String();
      
      usersQuery = usersQuery.gte('created_at', startDate).lt('created_at', endDate);
      shopsQuery = shopsQuery.gte('created_at', startDate).lt('created_at', endDate);
      appointmentsQuery = appointmentsQuery.gte('created_at', startDate).lt('created_at', endDate);
    }
    
    final results = await Future.wait([
      usersQuery,
      shopsQuery,
      appointmentsQuery,
    ]);
    return [
      List<Map<String, dynamic>>.from(results[0]),
      List<Map<String, dynamic>>.from(results[1]),
      List<Map<String, dynamic>>.from(results[2]),
    ];
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
