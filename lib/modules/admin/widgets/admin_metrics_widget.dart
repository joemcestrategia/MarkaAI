import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:markaai/core/theme/app_colors.dart';
import 'package:markaai/core/utils/format_utils.dart';
import 'package:markaai/modules/admin/services/admin_service.dart';

class AdminMetricsWidget extends StatefulWidget {
  const AdminMetricsWidget({super.key});

  @override
  State<AdminMetricsWidget> createState() => _AdminMetricsWidgetState();
}

class _AdminMetricsWidgetState extends State<AdminMetricsWidget> {
  final _adminService = AdminService();
  bool _loading = true;
  Map<String, dynamic>? _metrics;
  List<Map<String, dynamic>> _growthData = [];
  Map<String, dynamic>? _appointmentMetrics;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        _adminService.getRevenueMetrics(),
        _adminService.getGrowthDaily(days: 30),
        _adminService.getAppointmentMetrics(),
      ]);
      setState(() {
        _metrics = results[0] as Map<String, dynamic>;
        _growthData = results[1] as List<Map<String, dynamic>>;
        _appointmentMetrics = results[2] as Map<String, dynamic>;
        _loading = false;
      });
    } catch (e) {
      debugPrint('Erro ao carregar métricas: $e');
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_metrics == null) {
      return const Center(child: Text('Erro ao carregar dados'));
    }

    final mrr = (_metrics!['mrr'] as num).toDouble();
    final totalShops = _metrics!['total_shops'] as int;
    final activeShops = _metrics!['active_shops_30d'] as int;
    final arr = mrr * 12;
    
    // Contagem de planos
    final countFree = _metrics!['count_free'] as int;
    final countStart = _metrics!['count_start'] as int;
    final countPlus = _metrics!['count_plus'] as int;
    final countPro = _metrics!['count_pro'] as int;
    final paidShops = countStart + countPlus + countPro;
    final arpu = paidShops > 0 ? mrr / paidShops : 0.0;

    final totalAppointments = _appointmentMetrics?['total_appointments'] as int? ?? 0;
    final totalVolume = (_appointmentMetrics?['total_volume'] as num?)?.toDouble() ?? 0.0;
    final activeShopsAppt = _appointmentMetrics?['active_shops'] as int? ?? 0;
    final activeClients = _appointmentMetrics?['active_clients'] as int? ?? 0;
    final avgDaily = (_appointmentMetrics?['avg_daily_appointments'] as num?)?.toDouble() ?? 0.0;
    final avgMonthly = (_appointmentMetrics?['avg_monthly_appointments'] as num?)?.toDouble() ?? 0.0;

    return SafeArea(
      child: RefreshIndicator(
        onRefresh: _loadData,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Row 1: KPI Cards
              LayoutBuilder(
                builder: (context, constraints) {
                  final isWide = constraints.maxWidth > 900;
                  final isMedium = constraints.maxWidth > 600;
                  final theme = Theme.of(context);
                  
                  if (isWide) {
                    return Row(
                      children: [
                        Expanded(child: _buildKPI('MRR Atual', FormatUtils.formatMoney(mrr), '+12.5%', Icons.payments_outlined, theme.colorScheme.primary)),
                        const SizedBox(width: 16),
                        Expanded(child: _buildKPI('Tenants', '$totalShops total', '$paidShops pagos', Icons.store_outlined, theme.colorScheme.tertiary)),
                        const SizedBox(width: 16),
                        Expanded(child: _buildKPI('ARR Estimado', FormatUtils.formatMoney(arr), 'ARPU: ${FormatUtils.formatMoney(arpu)}', Icons.trending_up_rounded, Colors.green)),
                      ],
                    );
                  } else if (isMedium) {
                    return Column(
                      children: [
                        Row(
                          children: [
                            Expanded(child: _buildKPI('MRR Atual', FormatUtils.formatMoney(mrr), '+12.5%', Icons.payments_outlined, theme.colorScheme.primary)),
                            const SizedBox(width: 16),
                            Expanded(child: _buildKPI('Tenants', '$totalShops total', '$paidShops pagos', Icons.store_outlined, theme.colorScheme.tertiary)),
                          ],
                        ),
                        const SizedBox(height: 16),
                        _buildKPI('ARR Estimado', FormatUtils.formatMoney(arr), 'ARPU: ${FormatUtils.formatMoney(arpu)}', Icons.trending_up_rounded, Colors.green),
                      ],
                    );
                  } else {
                    return Column(
                      children: [
                        _buildKPI('MRR Atual', FormatUtils.formatMoney(mrr), '+12.5%', Icons.payments_outlined, theme.colorScheme.primary),
                        const SizedBox(height: 16),
                        _buildKPI('Tenants', '$totalShops total', '$paidShops pagos', Icons.store_outlined, theme.colorScheme.tertiary),
                        const SizedBox(height: 16),
                        _buildKPI('ARR Estimado', FormatUtils.formatMoney(arr), 'ARPU: ${FormatUtils.formatMoney(arpu)}', Icons.trending_up_rounded, Colors.green),
                      ],
                    );
                  }
                }
              ),
              const SizedBox(height: 24),
              
              // Row 1.5: Schedule KPIs
              Text('Métricas de Agendamento', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurface)),
              const SizedBox(height: 16),
              LayoutBuilder(
                builder: (context, constraints) {
                  final isWide = constraints.maxWidth > 900;
                  final isMedium = constraints.maxWidth > 600;
                  final theme = Theme.of(context);
                  
                  if (isWide) {
                    return Row(
                      children: [
                        Expanded(child: _buildKPI('Total Agendado', '$totalAppointments', 'Média: ${avgDaily.toStringAsFixed(1)}/dia', Icons.calendar_month_outlined, theme.colorScheme.primary)),
                        const SizedBox(width: 16),
                        Expanded(child: _buildKPI('Volume Total', FormatUtils.formatMoney(totalVolume), 'Média: ${avgMonthly.toStringAsFixed(1)}/mês', Icons.attach_money_rounded, Colors.green)),
                        const SizedBox(width: 16),
                        Expanded(child: _buildKPI('Ativos', '$activeShopsAppt lojas', '$activeClients clientes', Icons.people_alt_outlined, theme.colorScheme.tertiary)),
                      ],
                    );
                  } else if (isMedium) {
                    return Column(
                      children: [
                        Row(
                          children: [
                            Expanded(child: _buildKPI('Total Agendado', '$totalAppointments', 'Média: ${avgDaily.toStringAsFixed(1)}/dia', Icons.calendar_month_outlined, theme.colorScheme.primary)),
                            const SizedBox(width: 16),
                            Expanded(child: _buildKPI('Volume Total', FormatUtils.formatMoney(totalVolume), 'Média: ${avgMonthly.toStringAsFixed(1)}/mês', Icons.attach_money_rounded, Colors.green)),
                          ],
                        ),
                        const SizedBox(height: 16),
                        _buildKPI('Ativos', '$activeShopsAppt lojas', '$activeClients clientes', Icons.people_alt_outlined, theme.colorScheme.tertiary),
                      ],
                    );
                  } else {
                    return Column(
                      children: [
                        _buildKPI('Total Agendado', '$totalAppointments', 'Média: ${avgDaily.toStringAsFixed(1)}/dia', Icons.calendar_month_outlined, theme.colorScheme.primary),
                        const SizedBox(height: 16),
                        _buildKPI('Volume Total', FormatUtils.formatMoney(totalVolume), 'Média: ${avgMonthly.toStringAsFixed(1)}/mês', Icons.attach_money_rounded, Colors.green),
                        const SizedBox(height: 16),
                        _buildKPI('Ativos', '$activeShopsAppt lojas', '$activeClients clientes', Icons.people_alt_outlined, theme.colorScheme.tertiary),
                      ],
                    );
                  }
                }
              ),
              const SizedBox(height: 24),

              // Row 2: Charts & Distribution
              LayoutBuilder(
                builder: (context, constraints) {
                  final isWide = constraints.maxWidth > 800;
                  
                  if (isWide) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 2,
                          child: _buildSectionCard(
                            title: 'Crescimento (30 dias)',
                            child: SizedBox(height: 250, child: _buildLineChart()),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            children: [
                              _buildSectionCard(title: 'Distribuição de Planos', child: _buildPlanDistribution(free: countFree, start: countStart, plus: countPlus, pro: countPro, total: totalShops)),
                              const SizedBox(height: 16),
                              _buildSectionCard(title: 'Lojas Ativas (30d)', child: _buildActiveShopsCircle(activeShops, totalShops)),
                            ],
                          ),
                        ),
                      ],
                    );
                  } else {
                    return Column(
                      children: [
                        _buildSectionCard(
                          title: 'Crescimento (30 dias)',
                          child: SizedBox(height: 250, child: _buildLineChart()),
                        ),
                        const SizedBox(height: 16),
                        _buildSectionCard(title: 'Distribuição de Planos', child: _buildPlanDistribution(free: countFree, start: countStart, plus: countPlus, pro: countPro, total: totalShops)),
                        const SizedBox(height: 16),
                        _buildSectionCard(title: 'Lojas Ativas (30d)', child: _buildActiveShopsCircle(activeShops, totalShops)),
                      ],
                    );
                  }
                }
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildKPI(String title, String value, String subtitle, IconData icon, Color color) {
    return _buildKPICard(title: title, value: value, subtitle: subtitle, icon: icon, color: color);
  }

  Widget _buildKPICard({
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color color,
  }) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.onSurface.withValues(alpha: 0.1)),
        boxShadow: [
          if (theme.brightness == Brightness.light)
            BoxShadow(
              color: cs.onSurface.withValues(alpha: 0.02),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(child: Text(title, style: TextStyle(fontSize: 12, color: cs.onSurface.withValues(alpha: 0.5), fontWeight: FontWeight.w500), overflow: TextOverflow.ellipsis)),
              Icon(icon, color: color.withValues(alpha: 0.8), size: 16),
            ],
          ),
          const SizedBox(height: 8),
          Text(value, 
               overflow: TextOverflow.ellipsis,
               maxLines: 1,
               style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: cs.onSurface, letterSpacing: -0.5)),
          const SizedBox(height: 2),
          Text(subtitle, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _buildSectionCard({required String title, required Widget child}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isDark ? AppColors.darkBorder : AppColors.border.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 20),
          child,
        ],
      ),
    );
  }

  Widget _buildPlanDistribution({
    required int free,
    required int start,
    required int plus,
    required int pro,
    required int total,
  }) {
    if (total == 0) return const SizedBox.shrink();

    return Column(
      children: [
        _buildProgressBar('Pro', pro, total, Colors.purple),
        const SizedBox(height: 12),
        _buildProgressBar('Plus', plus, total, Colors.blue),
        const SizedBox(height: 12),
        _buildProgressBar('Start', start, total, AppColors.gold),
        const SizedBox(height: 12),
        _buildProgressBar('Free', free, total, Colors.grey),
      ],
    );
  }

  Widget _buildProgressBar(String label, int value, int total, Color color) {
    final percent = value / total;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(fontSize: 12)),
            Text('$value (${(percent * 100).toStringAsFixed(0)}%)', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: percent,
            backgroundColor: color.withValues(alpha: 0.1),
            valueColor: AlwaysStoppedAnimation<Color>(color),
            minHeight: 8,
          ),
        ),
      ],
    );
  }

  Widget _buildActiveShopsCircle(int active, int total) {
    final percent = total > 0 ? active / total : 0.0;
    return Center(
      child: Column(
        children: [
          SizedBox(
            height: 100,
            width: 100,
            child: Stack(
              children: [
                Center(
                  child: CircularProgressIndicator(
                    value: percent,
                    strokeWidth: 10,
                    backgroundColor: Colors.grey.withValues(alpha: 0.1),
                    valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primaryPurple),
                  ),
                ),
                Center(
                  child: Text(
                    '${(percent * 100).toStringAsFixed(0)}%',
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text('$active de $total lojas', style: const TextStyle(fontSize: 14, color: Colors.grey)),
        ],
      ),
    );
  }

  Widget _buildLineChart() {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    if (_growthData.isEmpty) return Center(child: Text('Sem dados', style: TextStyle(color: cs.onSurface)));

    final spots = _growthData.asMap().entries.map((entry) {
      return FlSpot(entry.key.toDouble(), (entry.value['novos_shops'] as num).toDouble());
    }).toList().reversed.toList();

    return LineChart(
      LineChartData(
        gridData: const FlGridData(show: false),
        titlesData: const FlTitlesData(show: false),
        borderData: FlBorderData(show: false),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            color: cs.primary,
            barWidth: 3,
            isStrokeCapRound: true,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              color: cs.primary.withValues(alpha: 0.1),
            ),
          ),
        ],
      ),
    );
  }
}
