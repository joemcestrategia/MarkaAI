import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:markaai/core/theme/app_colors.dart';

// ─────────────────────────────────────────────────────────────────────────────
// MODELOS INTERNOS
// ─────────────────────────────────────────────────────────────────────────────

class _UsageRecord {
  final String couponCode;
  final String couponId;
  final double discountPercent;
  final DateTime usedAt;
  final String clientName;
  final String serviceName;
  final double appointmentTotal;
  final double discountValue;

  const _UsageRecord({
    required this.couponCode,
    required this.couponId,
    required this.discountPercent,
    required this.usedAt,
    required this.clientName,
    required this.serviceName,
    required this.appointmentTotal,
    required this.discountValue,
  });
}

class _AnalyticsData {
  final List<_UsageRecord> records;
  final List<Map<String, dynamic>> coupons;

  const _AnalyticsData({required this.records, required this.coupons});

  int get totalUsos => records.length;

  double get totalDesconto =>
      records.fold(0.0, (sum, r) => sum + r.discountValue);

  String get cupomMaisUsado {
    if (records.isEmpty) return '—';
    final counts = <String, int>{};
    for (final r in records) {
      counts[r.couponCode] = (counts[r.couponCode] ?? 0) + 1;
    }
    return counts.entries
        .reduce((a, b) => a.value >= b.value ? a : b)
        .key;
  }

  int get clientesUnicos =>
      records.map((r) => r.clientName).toSet().length;

  /// Usos por dia (chave = 'yyyy-MM-dd')
  Map<String, int> get usosPorDia {
    final map = <String, int>{};
    for (final r in records) {
      final key = DateFormat('yyyy-MM-dd').format(r.usedAt);
      map[key] = (map[key] ?? 0) + 1;
    }
    return map;
  }

  /// Top cupons por número de usos
  List<MapEntry<String, int>> get topCupons {
    final counts = <String, int>{};
    for (final r in records) {
      counts[r.couponCode] = (counts[r.couponCode] ?? 0) + 1;
    }
    return counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
  }

  /// Faturamento total gerado (soma dos total_price dos agendamentos)
  double get totalFaturamento =>
      records.fold(0.0, (sum, r) => sum + r.appointmentTotal);

  /// Faturamento agrupado por código de cupom
  Map<String, double> get faturamentoPorCupom {
    final map = <String, double>{};
    for (final r in records) {
      map[r.couponCode] = (map[r.couponCode] ?? 0) + r.appointmentTotal;
    }
    return map;
  }

  /// Desconto agrupado por código de cupom
  Map<String, double> get descontoPorCupom {
    final map = <String, double>{};
    for (final r in records) {
      map[r.couponCode] = (map[r.couponCode] ?? 0) + r.discountValue;
    }
    return map;
  }

  /// Usos agrupados por código de cupom
  Map<String, int> get usosPorCupom {
    final counts = <String, int>{};
    for (final r in records) {
      counts[r.couponCode] = (counts[r.couponCode] ?? 0) + 1;
    }
    return counts;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// WIDGET PRINCIPAL
// ─────────────────────────────────────────────────────────────────────────────

class CouponAnalyticsTab extends StatefulWidget {
  final String shopId;
  const CouponAnalyticsTab({super.key, required this.shopId});

  @override
  State<CouponAnalyticsTab> createState() => _CouponAnalyticsTabState();
}

class _CouponAnalyticsTabState extends State<CouponAnalyticsTab>
    with AutomaticKeepAliveClientMixin {
  // ── Estado ────────────────────────────────────────────────────────────────
  _AnalyticsData? _data;
  bool _isLoading = false;
  String? _error;

  // ── Filtros ───────────────────────────────────────────────────────────────
  DateTime _startDate = DateTime.now().subtract(const Duration(days: 30));
  DateTime _endDate = DateTime.now();
  String? _selectedCouponId; // null = todos

  // ── Auxiliares ────────────────────────────────────────────────────────────
  final _currencyFmt = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
  final _dateFmt = DateFormat('dd/MM/yyyy');
  final _supabase = Supabase.instance.client;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // CARGA DE DADOS (somente SELECT)
  // ─────────────────────────────────────────────────────────────────────────
  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // 1. Busca todos os cupons da loja
      final couponsRaw = await _supabase
          .from('coupons')
          .select('id, code, description, discount_percent, usage_count, max_usage')
          .eq('shop_id', widget.shopId)
          .order('code');

      final coupons = List<Map<String, dynamic>>.from(couponsRaw);

      // Mapa couponId → dados do cupom (para join em memória)
      final couponMap = <String, Map<String, dynamic>>{
        for (final c in coupons) c['id'].toString(): c,
      };

      // 2. Monta filtro de IDs de cupons da loja (necessário para policy RLS)
      final shopCouponIds = couponMap.keys.toList();
      if (shopCouponIds.isEmpty) {
        if (mounted) {
          setState(() {
            _data = _AnalyticsData(records: [], coupons: coupons);
            _isLoading = false;
          });
        }
        return;
      }

      // 3. Busca usos no período filtrado
      var usageQuery = _supabase
          .from('coupon_usage')
          .select('id, coupon_id, user_id, appointment_id, used_at')
          .gte('used_at', _startDate.toIso8601String())
          .lte('used_at', DateTime(_endDate.year, _endDate.month, _endDate.day, 23, 59, 59).toIso8601String());

      // Filtra por cupom específico se selecionado
      if (_selectedCouponId != null) {
        usageQuery = usageQuery.eq('coupon_id', _selectedCouponId!);
      } else {
        usageQuery = usageQuery.inFilter('coupon_id', shopCouponIds);
      }

      final usageRaw = await usageQuery.order('used_at', ascending: false);
      final usages = List<Map<String, dynamic>>.from(usageRaw);

      if (usages.isEmpty) {
        if (mounted) {
          setState(() {
            _data = _AnalyticsData(records: [], coupons: coupons);
            _isLoading = false;
          });
        }
        return;
      }

      // 4. Busca dados dos clientes (users) e agendamentos em paralelo
      final userIds = usages.map((u) => u['user_id'].toString()).toSet().toList();
      final appointmentIds = usages
          .where((u) => u['appointment_id'] != null)
          .map((u) => u['appointment_id'].toString())
          .toSet()
          .toList();

      final futures = await Future.wait([
        // Nomes dos clientes
        userIds.isEmpty
            ? Future.value(<dynamic>[])
            : _supabase
                .from('users')
                .select('id, name')
                .inFilter('id', userIds),
        // Valores dos agendamentos
        appointmentIds.isEmpty
            ? Future.value(<dynamic>[])
            : _supabase
                .from('appointments')
                .select('id, total_price, discount_amount, service_name, client_name')
                .inFilter('id', appointmentIds),
      ]);

      final usersRaw = List<Map<String, dynamic>>.from(futures[0]);
      final appointmentsRaw = List<Map<String, dynamic>>.from(futures[1]);

      final userNameMap = <String, String>{
        for (final u in usersRaw)
          u['id'].toString(): (u['name'] ?? 'Cliente').toString(),
      };
      final appointmentValueMap = <String, Map<String, dynamic>>{
        for (final a in appointmentsRaw) a['id'].toString(): a,
      };

      // 5. Monta os registros de uso
      final records = <_UsageRecord>[];
      for (final u in usages) {
        final couponId = u['coupon_id'].toString();
        final coupon = couponMap[couponId];
        if (coupon == null) continue; // cupom de outra loja (não deve acontecer)

        final discountPercent =
            (coupon['discount_percent'] as num?)?.toDouble() ?? 0.0;
        final apptId = u['appointment_id']?.toString();
        final apptData = apptId != null ? appointmentValueMap[apptId] : null;

        double appointmentTotal = 0.0;
        double discountValue = 0.0;
        String serviceName = 'Serviço';

        if (apptData != null) {
          appointmentTotal =
              (apptData['total_price'] as num?)?.toDouble() ?? 0.0;
          // Prioriza o campo discount_amount se preenchido, senão calcula
          final storedDiscount =
              (apptData['discount_amount'] as num?)?.toDouble() ?? 0.0;
          discountValue = storedDiscount > 0
              ? storedDiscount
              : appointmentTotal * discountPercent / 100;
          
          serviceName = (apptData['service_name'] ?? apptData['servico_nome'] ?? 'Serviço').toString().trim();
          if (serviceName.toLowerCase() == 'null' || serviceName.isEmpty) {
            serviceName = 'Serviço';
          }
        } else {
          // Agendamento deletado ou sem vinculação — estima pelo ticket médio
          discountValue = 0.0;
        }

        final apptClientName = apptData?['client_name']?.toString();
        final mappedClientName = userNameMap[u['user_id']?.toString()];
        String clientName = 'Cliente';
        if (apptClientName != null && apptClientName.trim().isNotEmpty && apptClientName.trim().toLowerCase() != 'null') {
          clientName = apptClientName.trim();
        } else if (mappedClientName != null && mappedClientName.trim().isNotEmpty && mappedClientName.trim().toLowerCase() != 'null') {
          clientName = mappedClientName.trim();
        }

        // Evita exibir um email gigantesco na tabela
        if (clientName.contains('@')) {
          clientName = clientName.split('@').first;
          // Deixa a primeira letra maiúscula
          if (clientName.isNotEmpty) {
            clientName = clientName[0].toUpperCase() + clientName.substring(1);
          }
        }

        records.add(_UsageRecord(
          couponCode: (coupon['code'] ?? '').toString(),
          couponId: couponId,
          discountPercent: discountPercent,
          usedAt: DateTime.parse(u['used_at'].toString()).toLocal(),
          clientName: clientName,
          serviceName: serviceName,
          appointmentTotal: appointmentTotal,
          discountValue: discountValue,
        ));
      }

      if (mounted) {
        setState(() {
          _data = _AnalyticsData(records: records, coupons: coupons);
          _isLoading = false;
        });
      }
    } catch (e, st) {
      debugPrint('Erro ao carregar análise de cupons: $e\n$st');
      if (mounted) {
        setState(() {
          _error = 'Erro ao carregar dados: $e';
          _isLoading = false;
        });
      }
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // BUILD PRINCIPAL
  // ─────────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    super.build(context);

    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: AppColors.primaryPurple),
            SizedBox(height: 16),
            Text('Carregando análise...', style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }

    if (_error != null) {
      return _buildErrorState();
    }

    return RefreshIndicator(
      color: AppColors.primaryPurple,
      onRefresh: _loadData,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildFilters(),
          const SizedBox(height: 20),
          if (_data == null || _data!.records.isEmpty)
            _buildEmptyState()
          else ...[
            _buildKpiCards(),
            const SizedBox(height: 24),
            _buildLineChartSection(),
            const SizedBox(height: 24),
            _buildBarChartSection(),
            const SizedBox(height: 24),
            _buildCouponSummaryTable(),
            const SizedBox(height: 24),
            _buildUsageTable(),
            const SizedBox(height: 24),
          ],
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // FILTROS
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildFilters() {
    final coupons = _data?.coupons ?? [];

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey[200]!),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'FILTROS',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: Colors.grey,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 12),
            // Linha 1: Datas
            Row(
              children: [
                Expanded(
                  child: _buildDateField(
                    label: 'De',
                    date: _startDate,
                    onTap: () => _pickDate(isStart: true),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildDateField(
                    label: 'Até',
                    date: _endDate,
                    onTap: () => _pickDate(isStart: false),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Linha 2: Dropdown de cupom
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey[200]!),
              ),
              child: DropdownButton<String?>(
                value: _selectedCouponId,
                isExpanded: true,
                underline: const SizedBox(),
                hint: const Text('Todos os cupons'),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('Todos os cupons'),
                  ),
                  ...coupons.map((c) => DropdownMenuItem<String?>(
                        value: c['id'].toString(),
                        child: Text(
                          c['code']?.toString() ?? '',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      )),
                ],
                onChanged: (val) => setState(() => _selectedCouponId = val),
              ),
            ),
            const SizedBox(height: 12),
            // Botão de aplicar
            SizedBox(
              width: double.infinity,
              height: 46,
              child: ElevatedButton.icon(
                onPressed: _loadData,
                icon: const Icon(Icons.search_rounded, size: 18),
                label: const Text('APLICAR FILTRO',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryPurple,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDateField({
    required String label,
    required DateTime date,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.grey[50],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey[200]!),
        ),
        child: Row(
          children: [
            Icon(Icons.calendar_today, size: 16, color: AppColors.primaryPurple),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(fontSize: 10, color: Colors.grey)),
                Text(
                  _dateFmt.format(date),
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 14),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickDate({required bool isStart}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: isStart ? _startDate : _endDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.light(
            primary: AppColors.primaryPurple,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null && mounted) {
      setState(() {
        if (isStart) {
          _startDate = picked;
          if (_startDate.isAfter(_endDate)) _endDate = _startDate;
        } else {
          _endDate = picked;
          if (_endDate.isBefore(_startDate)) _startDate = _endDate;
        }
      });
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // KPI CARDS
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildKpiCards() {
    final d = _data!;
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: 1.6,
      children: [
        _buildKpiCard(
          icon: Icons.confirmation_number_rounded,
          color: AppColors.primaryPurple,
          label: 'Total de Usos',
          value: d.totalUsos.toString(),
        ),
        _buildKpiCard(
          icon: Icons.attach_money_rounded,
          color: Colors.green[700]!,
          label: 'Faturamento Gerado',
          value: _currencyFmt.format(d.totalFaturamento),
          isSmallValue: true,
        ),
        _buildKpiCard(
          icon: Icons.discount_rounded,
          color: Colors.orange[700]!,
          label: 'Desconto Concedido',
          value: _currencyFmt.format(d.totalDesconto),
          isSmallValue: true,
        ),
        _buildKpiCard(
          icon: Icons.people_alt_rounded,
          color: Colors.blue[700]!,
          label: 'Clientes Únicos',
          value: d.clientesUnicos.toString(),
        ),
      ],
    );
  }

  Widget _buildKpiCard({
    required IconData icon,
    required Color color,
    required String label,
    required String value,
    bool isSmallValue = false,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: isSmallValue ? 14 : 20,
                  color: Colors.black87,
                ),
              ),
              Text(
                label,
                style: const TextStyle(fontSize: 10, color: Colors.grey),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // GRÁFICO DE LINHA — Usos ao longo do tempo
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildLineChartSection() {
    final d = _data!;
    final usosPorDia = d.usosPorDia;

    if (usosPorDia.isEmpty) return const SizedBox();

    // Ordena as datas
    final sortedKeys = usosPorDia.keys.toList()..sort();
    final spots = sortedKeys.asMap().entries.map((e) {
      return FlSpot(e.key.toDouble(), usosPorDia[e.value]!.toDouble());
    }).toList();

    final maxY = (usosPorDia.values.reduce((a, b) => a > b ? a : b) + 1)
        .toDouble();

    return _buildSection(
      title: 'Usos ao Longo do Tempo',
      icon: Icons.show_chart_rounded,
      child: SizedBox(
        height: 180,
        child: LineChart(
          LineChartData(
            gridData: FlGridData(
              show: true,
              drawVerticalLine: false,
              getDrawingHorizontalLine: (v) => FlLine(
                color: Colors.grey[200]!,
                strokeWidth: 1,
              ),
            ),
            titlesData: FlTitlesData(
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 28,
                  getTitlesWidget: (v, m) => Text(
                    v.toInt().toString(),
                    style: const TextStyle(fontSize: 10, color: Colors.grey),
                  ),
                ),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  interval: sortedKeys.length > 10
                      ? (sortedKeys.length / 5).ceilToDouble()
                      : 1,
                  getTitlesWidget: (v, m) {
                    final idx = v.toInt();
                    if (idx < 0 || idx >= sortedKeys.length) {
                      return const SizedBox();
                    }
                    final date = DateTime.parse(sortedKeys[idx]);
                    return Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        DateFormat('dd/MM').format(date),
                        style: const TextStyle(
                            fontSize: 9, color: Colors.grey),
                      ),
                    );
                  },
                ),
              ),
              rightTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false)),
              topTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false)),
            ),
            borderData: FlBorderData(show: false),
            minY: 0,
            maxY: maxY,
            lineBarsData: [
              LineChartBarData(
                spots: spots,
                isCurved: true,
                curveSmoothness: 0.35,
                color: AppColors.primaryPurple,
                barWidth: 3,
                dotData: FlDotData(
                  show: spots.length <= 15,
                  getDotPainter: (s, p, bar, i) => FlDotCirclePainter(
                    radius: 4,
                    color: AppColors.primaryPurple,
                    strokeColor: Colors.white,
                    strokeWidth: 2,
                  ),
                ),
                belowBarData: BarAreaData(
                  show: true,
                  color: AppColors.primaryPurple.withValues(alpha: 0.08),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // GRÁFICO DE BARRAS — Top cupons por usos
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildBarChartSection() {
    if (_selectedCouponId != null) return const SizedBox();

    final d = _data!;
    final top = d.topCupons.take(8).toList();
    if (top.isEmpty) return const SizedBox();

    final maxVal =
        top.map((e) => e.value).reduce((a, b) => a > b ? a : b).toDouble();

    return _buildSection(
      title: 'Top Cupons por Usos',
      icon: Icons.bar_chart_rounded,
      child: SizedBox(
        height: (top.length * 46.0).clamp(120.0, 380.0),
        child: BarChart(
          BarChartData(
            alignment: BarChartAlignment.center,
            barTouchData: BarTouchData(
              touchTooltipData: BarTouchTooltipData(
                getTooltipItem: (group, gIdx, rod, rIdx) => BarTooltipItem(
                  '${top[group.x.toInt()].key}\n',
                  const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 12),
                  children: [
                    TextSpan(
                      text: '${rod.toY.toInt()} uso(s)',
                      style: const TextStyle(
                          color: Colors.white70, fontSize: 11),
                    ),
                  ],
                ),
              ),
            ),
            titlesData: FlTitlesData(
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 72,
                  getTitlesWidget: (v, m) {
                    final idx = v.toInt();
                    if (idx < 0 || idx >= top.length) {
                      return const SizedBox();
                    }
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Text(
                        top[idx].key,
                        style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87),
                        textAlign: TextAlign.right,
                        overflow: TextOverflow.ellipsis,
                      ),
                    );
                  },
                ),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  getTitlesWidget: (v, m) => Text(
                    v.toInt().toString(),
                    style: const TextStyle(fontSize: 10, color: Colors.grey),
                  ),
                ),
              ),
              rightTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false)),
              topTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false)),
            ),
            gridData: FlGridData(
              show: true,
              drawHorizontalLine: false,
              getDrawingVerticalLine: (v) =>
                  FlLine(color: Colors.grey[200]!, strokeWidth: 1),
            ),
            borderData: FlBorderData(show: false),
            maxY: maxVal + 1,
            barGroups: top.asMap().entries.map((e) {
              final pct = maxVal > 0 ? e.value.value / maxVal : 0.0;
              final color = Color.lerp(
                  AppColors.primaryPurple.withValues(alpha: 0.5),
                  AppColors.primaryPurple,
                  pct)!;
              return BarChartGroupData(
                x: e.key,
                barRods: [
                  BarChartRodData(
                    toY: e.value.value.toDouble(),
                    color: color,
                    width: 22,
                    borderRadius: const BorderRadius.horizontal(
                        right: Radius.circular(6)),
                  ),
                ],
              );
            }).toList(),
          ),
          swapAnimationDuration: const Duration(milliseconds: 400),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // RESUMO POR CUPOM — Faturamento e Desconto
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildCouponSummaryTable() {
    final d = _data!;
    if (d.records.isEmpty) return const SizedBox();

    final usos = d.usosPorCupom;
    final faturamento = d.faturamentoPorCupom;
    final desconto = d.descontoPorCupom;

    // Ordenado por usos (decrescente)
    final codes = usos.keys.toList()
      ..sort((a, b) => (usos[b] ?? 0).compareTo(usos[a] ?? 0));

    return _buildSection(
      title: 'Resumo por Cupom',
      icon: Icons.receipt_long_rounded,
      child: Column(
        children: [
          // Cabeçalho
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.primaryPurple.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Row(
              children: [
                Expanded(
                  flex: 2,
                  child: Text('Cupom',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: AppColors.primaryPurple)),
                ),
                Expanded(
                  child: Text('Usos',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: AppColors.primaryPurple)),
                ),
                Expanded(
                  flex: 2,
                  child: Text('Faturamento',
                      textAlign: TextAlign.end,
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: AppColors.primaryPurple)),
                ),
                Expanded(
                  flex: 2,
                  child: Text('Desconto',
                      textAlign: TextAlign.end,
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: AppColors.primaryPurple)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          ...codes.asMap().entries.map((e) {
            final code = e.value;
            final isOdd = e.key.isOdd;
            final qtd = usos[code] ?? 0;
            final fat = faturamento[code] ?? 0.0;
            final desc = desconto[code] ?? 0.0;

            return Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
              decoration: BoxDecoration(
                color: isOdd ? Colors.grey[50] : Colors.white,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  // Código do cupom
                  Expanded(
                    flex: 2,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.primaryPurple.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(7),
                      ),
                      child: Text(
                        code,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: AppColors.primaryPurple,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  // Usos
                  Expanded(
                    child: Text(
                      qtd.toString(),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87),
                    ),
                  ),
                  // Faturamento gerado
                  Expanded(
                    flex: 2,
                    child: Text(
                      fat > 0 ? _currencyFmt.format(fat) : '—',
                      textAlign: TextAlign.end,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Colors.green[700],
                      ),
                    ),
                  ),
                  // Desconto concedido
                  Expanded(
                    flex: 2,
                    child: Text(
                      desc > 0 ? _currencyFmt.format(desc) : '—',
                      textAlign: TextAlign.end,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Colors.red[700],
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // TABELA DE USOS
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildUsageTable() {
    final records = _data!.records;
    if (records.isEmpty) return const SizedBox();

    return _buildSection(
      title: 'Detalhes de Uso',
      icon: Icons.table_rows_rounded,
      child: Column(
        children: [
          // Cabeçalho
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.primaryPurple.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Row(
              children: [
                Expanded(
                    flex: 2,
                    child: Text('Data',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: AppColors.primaryPurple))),
                Expanded(
                    flex: 2,
                    child: Text('Cupom',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: AppColors.primaryPurple))),
                Expanded(
                    flex: 3,
                    child: Text('Cliente / Serviço',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: AppColors.primaryPurple))),
                Expanded(
                    flex: 2,
                    child: Text('Desc.',
                        textAlign: TextAlign.end,
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: AppColors.primaryPurple))),
              ],
            ),
          ),
          const SizedBox(height: 4),
          // Linhas (máximo 50 para performance)
          ...records.take(50).toList().asMap().entries.map((e) {
            final r = e.value;
            final isOdd = e.key.isOdd;
            return Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: isOdd ? Colors.grey[50] : Colors.white,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          DateFormat('dd/MM/yy').format(r.usedAt),
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black87),
                        ),
                        Text(
                          DateFormat('HH:mm').format(r.usedAt),
                          style: const TextStyle(fontSize: 10, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.primaryPurple
                                .withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            r.couponCode,
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: AppColors.primaryPurple,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    flex: 3,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          r.clientName,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 11, color: Colors.black87, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          r.serviceName,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 9, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(
                      r.discountValue > 0
                          ? _currencyFmt.format(r.discountValue)
                          : '—',
                      textAlign: TextAlign.end,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Colors.red[700],
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
          if (records.length > 50)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Exibindo 50 de ${records.length} registros.',
                style: const TextStyle(fontSize: 11, color: Colors.grey),
              ),
            ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // ESTRUTURA VISUAL DOS CARDS DE SEÇÃO
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildSection({
    required String title,
    required IconData icon,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: AppColors.primaryPurple),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // ESTADOS ESPECIAIS
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 48),
        child: Column(
          children: [
            Icon(Icons.bar_chart_rounded, size: 72, color: Colors.grey[300]),
            const SizedBox(height: 16),
            const Text(
              'Nenhum uso de cupom encontrado',
              style: TextStyle(
                  fontWeight: FontWeight.bold, color: Colors.black54),
            ),
            const SizedBox(height: 8),
            const Text(
              'Ajuste o período ou selecione outro cupom.',
              style: TextStyle(fontSize: 13, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.wifi_off_rounded, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            const Text(
              'Não foi possível carregar os dados',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              _error ?? '',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _loadData,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Tentar novamente'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryPurple,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
