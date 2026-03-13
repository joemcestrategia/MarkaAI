import 'dart:async';
import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../core/services/session_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/services/plan_features_service.dart';
import '../../core/constants/plan_features.dart';
import '../../widgets/upgrade_modal.dart';

class FinancialDashboardPage extends StatefulWidget {
  const FinancialDashboardPage({super.key});

  @override
  State<FinancialDashboardPage> createState() => _FinancialDashboardPageState();
}

class _FinancialDashboardPageState extends State<FinancialDashboardPage> {
  String? _shopId;
  bool _isLoading = true;
  late PlanFeatures _currentFeatures = planFeaturesConfig[PlanKey.free]!;

  // Filtros e Estado
  int? _selectedMonth;
  int _selectedYear = DateTime.now().year;

  // Cache de Dados Analíticos
  double _totalReceita = 0.0;
  double _totalDespesa = 0.0;
  double _totalComissao = 0.0;
  double _lucroLiquido = 0.0;
  int _totalAtendimentos = 0;
  int _totalCancelamentos = 0;
  double _ticketMedio = 0.0;

  // Eficiência Operacional
  int _horasTrabalhadasMin = 0;
  int _horasPotenciaisMin = 0;
  double _valorPorHora = 0.0;

  Map<String, double> _paymentMethods = {};
  Map<String, double> _topServices = {};
  List<FlSpot> _revenueSpots = [];
  List<FlSpot> _appointmentSpots = [];

  // Listas auxiliares
  final List<String> _months = [
    'Jan', 'Fev', 'Mar', 'Abr', 'Mai', 'Jun',
    'Jul', 'Ago', 'Set', 'Out', 'Nov', 'Dez'
  ];
  List<int> _availableYears = [];

  @override
  void initState() {
    super.initState();
    final currentYear = DateTime.now().year;
    _availableYears = List.generate(
        math.max(1, currentYear - 2022 + 1), (i) => currentYear - i);
    _selectedMonth = DateTime.now().month;
    _loadShopId();
  }

  Future<void> _loadShopId() async {
    try {
      _shopId = await SessionService.getShopId();

      if (_shopId == null || _shopId!.isEmpty) {
        final user = FirebaseAuth.instance.currentUser;
        if (user != null) {
          final doc = await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .get();

          if (doc.exists) {
            _shopId = doc.data()?['shopId'] as String?;
            if (_shopId != null) {
              await SessionService.saveShopId(_shopId!);
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Erro crítico ao carregar shopId: $e');
    }

    if (mounted) {
      setState(() => _isLoading = false);
      if (_shopId != null) _refresh();
    }
  }

  Future<void> _refresh() async {
    if (_shopId == null) return;
    setState(() => _isLoading = true);

    try {
      final start = _selectedMonth == null
          ? DateTime(_selectedYear, 1, 1)
          : DateTime(_selectedYear, _selectedMonth!, 1);
      final end = _selectedMonth == null
          ? DateTime(_selectedYear + 1, 1, 1).subtract(const Duration(seconds: 1))
          : DateTime(_selectedYear, _selectedMonth! + 1, 0, 23, 59, 59);

      // 1. Buscar Atendimentos
      final appointments = await FirebaseFirestore.instance
          .collection('appointments')
          .where('shopId', isEqualTo: _shopId)
          .where('data_agendamento', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
          .where('data_agendamento', isLessThanOrEqualTo: Timestamp.fromDate(end))
          .get();

      // 2. Buscar Pagamentos diretos / Despesas
      final transactions = await FirebaseFirestore.instance
          .collection('financial_transactions')
          .where('shopId', isEqualTo: _shopId)
          .where('data', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
          .where('data', isLessThanOrEqualTo: Timestamp.fromDate(end))
          .get();

      // 3. Buscar Funcionários (para comissões e horários)
      final employees = await FirebaseFirestore.instance
          .collection('employees')
          .where('shopId', isEqualTo: _shopId)
          .get();

      _calculateMetrics(appointments.docs, transactions.docs, employees.docs);
    } catch (e) {
      debugPrint('Erro ao atualizar dashboard: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _calculateMetrics(List<QueryDocumentSnapshot> appts,
      List<QueryDocumentSnapshot> trans, List<QueryDocumentSnapshot> emps) {
    double totalRevenue = 0;
    double totalExpense = 0;
    double totalCommission = 0;
    int completedAppointments = 0;
    int cancelledAppointments = 0;
    int workedMinutes = 0;

    Map<String, double> payments = {'PIX': 0, 'Cartão': 0, 'Dinheiro': 0};
    Map<String, double> servicesMap = {};
    Map<int, double> dailyRevenue = {};
    Map<int, int> dailyAppts = {};

    // Mapa de comissões por funcionário ID
    Map<String, double> empCommissions = {};
    for (var doc in emps) {
      final d = doc.data() as Map<String, dynamic>;
      empCommissions[doc.id] =
          double.tryParse(d['comissao_percent']?.toString() ?? '0') ?? 0;
    }

    for (var doc in appts) {
      final data = doc.data() as Map<String, dynamic>;
      final status = (data['status'] ?? '').toString().toLowerCase();
      final value =
          double.tryParse(data['valor_total']?.toString() ?? '0') ?? 0;
      final service = data['servico_nome'] ?? 'Outros';
      final date = (data['data_agendamento'] as Timestamp).toDate();
      final empId = data['professionalId'] ?? data['employeeId'];
      final duration =
          int.tryParse(data['duracao_min']?.toString() ?? '30') ?? 30;

      if (status == 'concluido' || status == 'finalizado' || status == 'pago') {
        completedAppointments++;
        totalRevenue += value;
        workedMinutes += duration;
        servicesMap[service] = (servicesMap[service] ?? 0) + value;

        // Cálculo de Comissão
        if (empId != null && empCommissions.containsKey(empId)) {
          double perc = empCommissions[empId]!;
          totalCommission += (value * perc / 100);
        }

        // Distribuição de Pagamento
        final method = data['forma_pagamento'] ?? 'Dinheiro';
        if (method.toString().toLowerCase().contains('pix')) {
          payments['PIX'] = (payments['PIX'] ?? 0) + value;
        } else if (method.toString().toLowerCase().contains('cart')) {
          payments['Cartão'] = (payments['Cartão'] ?? 0) + value;
        } else {
          payments['Dinheiro'] = (payments['Dinheiro'] ?? 0) + value;
        }

        final key = _selectedMonth == null ? date.month : date.day;
        dailyRevenue[key] = (dailyRevenue[key] ?? 0) + value;
        dailyAppts[key] = (dailyAppts[key] ?? 0) + 1;
      } else if (status == 'cancelado') {
        cancelledAppointments++;
      }
    }

    // Transações financeiras extras
    for (var doc in trans) {
      final data = doc.data() as Map<String, dynamic>;
      final val = (data['valor'] as num?)?.toDouble() ?? 0;
      if (val < 0) totalExpense += val.abs();
    }

    // Horas Potenciais (Capacidade total)
    int potentialMinutes = 0;
    int diasNoPeriodo = 0;
    if (_selectedMonth != null) {
      // Se mês selecionado, calculamos os dias úteis ou todos os dias do mês
      final daysInMonth = DateTime(_selectedYear, _selectedMonth! + 1, 0).day;
      diasNoPeriodo = daysInMonth;
    } else {
      diasNoPeriodo = 365; // Simplificação para o ano
    }

    for (var doc in emps) {
      final d = doc.data() as Map<String, dynamic>;
      final start = d['horario_inicio']?.toString() ?? '08:00';
      final end = d['horario_fim']?.toString() ?? '18:00';
      final diasTrab = (d['dias_trabalho'] as List?)?.length ?? 6;

      try {
        final sParts = start.split(':');
        final eParts = end.split(':');
        final sMin = int.parse(sParts[0]) * 60 + int.parse(sParts[1]);
        final eMin = int.parse(eParts[0]) * 60 + int.parse(eParts[1]);
        int jornadaDiaria = eMin - sMin;

        if (_selectedMonth != null) {
          // Aproximação: (jornada * dias_na_semana / 7) * dias_no_mês
          potentialMinutes +=
              ((jornadaDiaria * diasTrab / 7) * diasNoPeriodo).toInt();
        } else {
          potentialMinutes += (jornadaDiaria * diasTrab * 52); // Aproximação ano
        }
      } catch (_) {}
    }

    final sortedServices = servicesMap.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    _topServices = Map.fromEntries(sortedServices.take(5));
    _totalReceita = totalRevenue;
    _totalDespesa = totalExpense;
    _totalComissao = totalCommission;
    _lucroLiquido = totalRevenue - totalExpense - totalCommission;
    _totalAtendimentos = completedAppointments;
    _totalCancelamentos = cancelledAppointments;
    _ticketMedio =
        completedAppointments > 0 ? totalRevenue / completedAppointments : 0;
    _paymentMethods = payments;

    _horasTrabalhadasMin = workedMinutes;
    _horasPotenciaisMin = potentialMinutes;
    double horasTrab = workedMinutes / 60.0;
    _valorPorHora = horasTrab > 0 ? totalRevenue / horasTrab : 0;

    _revenueSpots = dailyRevenue.entries
        .map((e) => FlSpot(e.key.toDouble(), e.value))
        .toList()
      ..sort((a, b) => a.x.compareTo(b.x));
    _appointmentSpots = dailyAppts.entries
        .map((e) => FlSpot(e.key.toDouble(), e.value.toDouble()))
        .toList()
      ..sort((a, b) => a.x.compareTo(b.x));
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading && _totalAtendimentos == 0) {
      return const Scaffold(
          body: Center(child: CircularProgressIndicator(color: AppColors.primaryPurple)));
    }

    if (_shopId == null) {
      return Scaffold(
          body: Center(
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: const [
        Icon(Icons.error_outline, size: 60, color: Colors.red),
        SizedBox(height: 16),
        Text('Erro ao carregar dados da loja')
      ])));
    }

    final isMobile = MediaQuery.of(context).size.width < 800;

    return StreamBuilder<PlanFeatures>(
        stream: PlanFeaturesService.streamFeaturesByShopId(_shopId!),
        builder: (context, planSnapshot) {
          if (planSnapshot.hasData) {
            _currentFeatures = planSnapshot.data!;
            if (!_currentFeatures.financialDashboard) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) {
                  UpgradeModal.show(context,
                      featureName: "Dashboard Financeiro", requiredPlan: "Plus");
                  Navigator.pop(context);
                }
              });
            }
          }

          return Scaffold(
            backgroundColor: const Color(0xFFF8F9FD),
            body: RefreshIndicator(
              onRefresh: _refresh,
              color: AppColors.primaryPurple,
              child: CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(child: _buildHeader(isMobile)),
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    sliver: SliverToBoxAdapter(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _sectionTitle("Resumo Financeiro"),
                          _buildFinancialSummary(isMobile),
                          const SizedBox(height: 24),
                          _sectionTitle("Desempenho de Vendas"),
                          _buildSalesPerformance(isMobile),
                          const SizedBox(height: 24),
                          _sectionTitle("Eficiência Operacional"),
                          _buildOperationalEfficiency(isMobile),
                          const SizedBox(height: 24),
                        ],
                      ),
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    sliver: SliverToBoxAdapter(child: _buildMainChart()),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                    sliver: SliverToBoxAdapter(child: _buildInsightsRow(isMobile)),
                  ),
                ],
              ),
            ),
          );
        });
  }

  Widget _buildHeader(bool isMobile) {
    return Container(
      padding: EdgeInsets.fromLTRB(20, isMobile ? 40 : 20, 20, 20),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Insights Financeiros',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF1A1F36))),
                Text('Acompanhe a performance do seu negócio',
                    style: TextStyle(fontSize: 14, color: Colors.grey[600])),
              ],
            ),
          ),
          _dropdown<int?>(_selectedMonth, [
            const DropdownMenuItem(value: null, child: Text('Ano Todo')),
            ...List.generate(12, (i) => DropdownMenuItem(value: i + 1, child: Text(_months[i])))
          ], (v) => setState(() { _selectedMonth = v; _refresh(); })),
          const SizedBox(width: 8),
          _dropdown<int>(_selectedYear,
              _availableYears.map((y) => DropdownMenuItem(value: y, child: Text(y.toString()))).toList(),
              (v) => setState(() { if (v != null) { _selectedYear = v; _refresh(); } })),
        ],
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, left: 4),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: Colors.grey[600],
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _buildFinancialSummary(bool isMobile) {
    return _buildOptimizedGrid(
      isMobile: isMobile,
      children: [
        _MetricCard(
          title: 'Faturamento',
          value: NumberFormat.simpleCurrency(locale: 'pt_BR').format(_totalReceita),
          icon: Icons.payments_outlined,
          color: Colors.blue,
        ),
        _MetricCard(
          title: 'Despesas',
          value: NumberFormat.simpleCurrency(locale: 'pt_BR').format(_totalDespesa),
          icon: Icons.money_off_outlined,
          color: Colors.red,
        ),
        _MetricCard(
          title: 'Comissões',
          value: NumberFormat.simpleCurrency(locale: 'pt_BR').format(_totalComissao),
          icon: Icons.person_outline,
          color: Colors.orange,
        ),
        _MetricCard(
          title: 'Lucro Líquido',
          value: NumberFormat.simpleCurrency(locale: 'pt_BR').format(_lucroLiquido),
          icon: Icons.account_balance_wallet_outlined,
          color: Colors.green,
        ),
      ],
    );
  }

  Widget _buildSalesPerformance(bool isMobile) {
    return _buildOptimizedGrid(
      isMobile: isMobile,
      children: [
        _MetricCard(
          title: 'Agendamentos',
          value: _totalAtendimentos.toString(),
          icon: Icons.event_available_outlined,
          color: Colors.purple,
        ),
        _MetricCard(
          title: 'Ticket Médio',
          value: NumberFormat.simpleCurrency(locale: 'pt_BR').format(_ticketMedio),
          icon: Icons.trending_up,
          color: Colors.teal,
        ),
        _MetricCard(
          title: 'Cancelamentos',
          value: _totalCancelamentos.toString(),
          icon: Icons.event_busy_outlined,
          color: Colors.redAccent,
        ),
      ],
    );
  }

  Widget _buildOperationalEfficiency(bool isMobile) {
    return _buildOptimizedGrid(
      isMobile: isMobile,
      children: [
        _MetricCard(
          title: 'Horas Trabalhadas',
          value: '${(_horasTrabalhadasMin / 60).toStringAsFixed(1)}h',
          icon: Icons.timer_outlined,
          color: Colors.indigo,
        ),
        _MetricCard(
          title: 'Horas Ociosas',
          value: '${(math.max(0, _horasPotenciaisMin - _horasTrabalhadasMin) / 60).toStringAsFixed(1)}h',
          icon: Icons.hourglass_empty_rounded,
          color: Colors.blueGrey,
        ),
        _MetricCard(
          title: 'Valor por Hora',
          value: NumberFormat.simpleCurrency(locale: 'pt_BR').format(_valorPorHora),
          icon: Icons.speed_rounded,
          color: Colors.deepPurple,
        ),
      ],
    );
  }

  Widget _buildOptimizedGrid({required bool isMobile, required List<Widget> children}) {
    return GridView.count(
      crossAxisCount: isMobile ? 2 : 4,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: isMobile ? 1.4 : 1.6,
      children: children,
    );
  }

  Widget _buildMainChart() {
    return _DashboardContainer(
      title: 'Fluxo de Receita e Agendamentos',
      subtitle: _selectedMonth == null ? 'Visão Mensal' : 'Visão Diária',
      child: SizedBox(
        height: 300,
        child: _revenueSpots.isEmpty
            ? const Center(child: Text('Sem dados para exibir no gráfico'))
            : LineChart(
                LineChartData(
                  gridData: FlGridData(show: true, drawVerticalLine: false),
                  titlesData: FlTitlesData(
                    rightTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 30,
                        getTitlesWidget: (v, _) => Text(v.toInt().toString(), style: const TextStyle(fontSize: 10, color: Colors.purple)),
                      ),
                    ),
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (v, _) {
                          final i = v.toInt();
                          if (_selectedMonth == null) {
                            if (i >= 1 && i <= 12) return Text(_months[i - 1], style: const TextStyle(fontSize: 10));
                          } else {
                            if (i % 5 == 0 || i == 1) return Text(i.toString(), style: const TextStyle(fontSize: 10));
                          }
                          return const SizedBox();
                        },
                      ),
                    ),
                  ),
                  borderData: FlBorderData(show: false),
                  lineBarsData: [
                    LineChartBarData(
                      spots: _revenueSpots,
                      isCurved: true,
                      color: AppColors.primaryPurple,
                      barWidth: 3,
                      isStrokeCapRound: true,
                      dotData: const FlDotData(show: false),
                      belowBarData: BarAreaData(show: true, color: AppColors.primaryPurple.withValues(alpha: 0.1)),
                    ),
                    LineChartBarData(
                      spots: _appointmentSpots,
                      isCurved: true,
                      color: Colors.purple.withValues(alpha: 0.5),
                      barWidth: 2,
                      dashArray: [5, 5],
                      dotData: const FlDotData(show: false),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildInsightsRow(bool isMobile) {
    final children = [
      Expanded(
        flex: isMobile ? 0 : 1,
        child: _DashboardContainer(
          title: 'Serviços mais Rentáveis',
          child: Column(
            children: _topServices.entries.map((e) {
              final percent = _totalReceita > 0 ? e.value / _totalReceita : 0.0;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(e.key, style: const TextStyle(fontWeight: FontWeight.w500)),
                        Text(NumberFormat.simpleCurrency(locale: 'pt_BR').format(e.value)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    LinearProgressIndicator(
                      value: percent,
                      backgroundColor: Colors.grey[200],
                      color: AppColors.primaryPurple,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ),
      ),
      if (!isMobile) const SizedBox(width: 16),
      Expanded(
        flex: isMobile ? 0 : 1,
        child: _DashboardContainer(
          title: 'Formas de Pagamento',
          child: SizedBox(
            height: 200,
            child: PieChart(
              PieChartData(
                sectionsSpace: 2,
                centerSpaceRadius: 40,
                sections: _paymentMethods.entries.map((e) {
                  final color = e.key == 'PIX' ? Colors.teal : e.key == 'Cartão' ? Colors.blue : Colors.orange;
                  return PieChartSectionData(
                    value: e.value,
                    title: '${(e.value / (_totalReceita > 0 ? _totalReceita : 1) * 100).toStringAsFixed(0)}%',
                    color: color,
                    radius: 50,
                    titleStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
                  );
                }).toList(),
              ),
            ),
          ),
        ),
      ),
    ];

    return isMobile ? Column(children: children.map((e) => e is Expanded ? e.child : e).toList()) : Row(children: children);
  }

  Widget _dropdown<T>(T value, List<DropdownMenuItem<T>> items, Function(T?) onChange) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey[300]!)),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          items: items,
          onChanged: onChange,
          style: const TextStyle(fontSize: 13, color: Colors.black, fontWeight: FontWeight.w500),
          icon: const Icon(Icons.keyboard_arrow_down, size: 18),
        ),
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;

  const _MetricCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8)),
            child: Icon(icon, color: color, size: 20),
          ),
          const Spacer(),
          Text(title,
              style: TextStyle(fontSize: 11, color: Colors.grey[600]),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value,
                style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1A1F36))),
          ),
        ],
      ),
    );
  }
}

class _DashboardContainer extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget child;

  const _DashboardContainer({required this.title, this.subtitle, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1A1F36))),
          if (subtitle != null) Text(subtitle!, style: TextStyle(fontSize: 12, color: Colors.grey[500])),
          const SizedBox(height: 20),
          child,
        ],
      ),
    );
  }
}
