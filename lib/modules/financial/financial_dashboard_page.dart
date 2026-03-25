import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;
import 'dart:math' as math;
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../core/services/session_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/services/plan_features_service.dart';
import '../../core/constants/plan_features.dart';
import '../../widgets/upgrade_modal.dart';
import '../../core/services/auth_service.dart';
import '../../core/services/shop_data_cache_service.dart';

// ─────────────────────────────────────────────
// MODELO DE DADOS DO PERÍODO (auxilia comparação)
// ─────────────────────────────────────────────
class _PeriodMetrics {
  final double receita;
  final double despesa;
  final double comissao;
  final int atendimentos;
  final int cancelamentos;
  final double ticketMedio;

  const _PeriodMetrics({
    this.receita = 0,
    this.despesa = 0,
    this.comissao = 0,
    this.atendimentos = 0,
    this.cancelamentos = 0,
    this.ticketMedio = 0,
  });
}

// ─────────────────────────────────────────────
// SLOT DE PRODUTIVIDADE POR PERÍODO
// receita e minutos trabalhados acumulados por
// chave (mês 1–12 na visão anual, semana 1–5
// na visão mensal).
// ─────────────────────────────────────────────
class _HourlySlot {
  double receita;
  int minutos;
  _HourlySlot({this.receita = 0, this.minutos = 0});

  /// Valor gerado por hora neste slot.
  double get valorPorHora => minutos > 0 ? receita / (minutos / 60.0) : 0.0;
}

// ─────────────────────────────────────────────
// MÉTRICAS INDIVIDUAIS POR PROFISSIONAL
// ─────────────────────────────────────────────
class _ProfessionalEfficiency {
  final String id;
  final String nome;
  double receita = 0;
  int minutosTrabalhados = 0;
  int minutosPotenciais = 0;

  _ProfessionalEfficiency({required this.id, required this.nome});

  double get valorPorHora => minutosTrabalhados > 0 
      ? receita / (minutosTrabalhados / 60.0) 
      : 0.0;
  
  double get faturamentoPotencial => minutosPotenciais > 0 
      ? (valorPorHora > 0 ? valorPorHora : 0) * (minutosPotenciais / 60.0)
      : 0.0;

  double get taxaOcupacao => minutosPotenciais > 0 
      ? (minutosTrabalhados / minutosPotenciais) * 100 
      : 0.0;
}

// ─────────────────────────────────────────────
// PÁGINA PRINCIPAL
// ─────────────────────────────────────────────
class FinancialDashboardPage extends StatefulWidget {
  const FinancialDashboardPage({super.key});

  @override
  State<FinancialDashboardPage> createState() => _FinancialDashboardPageState();
}

class _FinancialDashboardPageState extends State<FinancialDashboardPage> {
  String? _shopId;
  bool _isLoading = true;
  late PlanFeatures _currentFeatures = planFeaturesConfig[PlanKey.free]!;

  // ── Filtros ──────────────────────────────────
  int? _selectedMonth;
  int _selectedYear = DateTime.now().year;

  // ── Meta Mensal ──────────────────────────────
  double _metaMensal = 0.0;
  final _metaController = TextEditingController();

  // ── Período Atual ────────────────────────────
  double _totalReceita = 0.0;
  double _totalDespesa = 0.0;
  double _totalComissao = 0.0;
  double _lucroLiquido = 0.0;
  int _totalAtendimentos = 0;
  int _totalCancelamentos = 0;
  double _ticketMedio = 0.0;
  double _margemLiquida = 0.0; // NOVO

  // ── Eficiência Operacional ────────────────────
  int _horasTrabalhadasMin = 0;
  int _horasPotenciaisMin = 0;
  double _valorPorHora = 0;
  double _faturamentoPotencial = 0.0;
  double _taxaOcupacao = 0.0;

  // ── Produtividade granular por período ────────
  // Chave: mês (1–12) em visão anual; semana do mês (1–5) em visão mensal.
  Map<int, _HourlySlot> _hourlyByPeriod = {};
  double _valorPorHoraPico = 0;
  double _valorPorHoraVale = 0;
  int _periodoMaisProdutivo = 0;

  // ── Top Profissionais e Eficiência ───────────
  Map<String, double> _topProfissionais = {};
  List<_ProfessionalEfficiency> _professionalEfficiency = [];

  // ── Comparativo período anterior ──────────────
  _PeriodMetrics? _prevPeriod; // NOVO

  // ── Distribuições ─────────────────────────────
  Map<String, double> _paymentMethods = {};
  Map<String, double> _topServices = {};
  List<FlSpot> _revenueSpots = [];
  List<FlSpot> _appointmentSpots = [];

  // ── Auxiliares ────────────────────────────────
  final List<String> _months = [
    'Jan',
    'Fev',
    'Mar',
    'Abr',
    'Mai',
    'Jun',
    'Jul',
    'Ago',
    'Set',
    'Out',
    'Nov',
    'Dez',
  ];
  List<int> _availableYears = [];
  int? _touchedIndex; // para o PieChart

  // ─────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    // FIX: garante pelo menos o ano corrente na lista
    final startYear = math.min(now.year, 2023);
    _availableYears =
        List.generate(now.year - startYear + 1, (i) => now.year - i);
    _selectedMonth = now.month;
    _loadShopId();
  }

  @override
  void dispose() {
    _metaController.dispose();
    super.dispose();
  }

  // ─────────────────────────────────────────────
  // CARREGAMENTO
  // ─────────────────────────────────────────────
  Future<void> _loadShopId() async {
    try {
      _shopId = await SessionService.getShopId();
      if (_shopId == null || _shopId!.isEmpty) {
        final user = AuthService().currentUser;
        if (user != null) {
          final supabase = sb.Supabase.instance.client;
            final doc = await supabase
              .from('users')
              .select('shop_id')
              .eq('id', user.id)
              .maybeSingle();
          if (doc != null) {
            _shopId = doc['shop_id'] as String?;
            if (_shopId != null) await SessionService.saveShopId(_shopId!);
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

  // ─────────────────────────────────────────────
  // DATAS DO PERÍODO
  // ─────────────────────────────────────────────

  /// Retorna [início, fim] do período selecionado.
  (DateTime, DateTime) _currentRange() {
    if (_selectedMonth == null) {
      return (
        DateTime(_selectedYear, 1, 1),
        DateTime(_selectedYear, 12, 31, 23, 59, 59),
      );
    }
    // FIX: usa lastDayOfMonth em vez de "month+1, day 0"
    final lastDay = DateTime(_selectedYear, _selectedMonth! + 1, 0).day;
    return (
      DateTime(_selectedYear, _selectedMonth!, 1),
      DateTime(_selectedYear, _selectedMonth!, lastDay, 23, 59, 59),
    );
  }

  /// Retorna [início, fim] do período ANTERIOR para comparativo.
  (DateTime, DateTime) _previousRange() {
    if (_selectedMonth == null) {
      return (
        DateTime(_selectedYear - 1, 1, 1),
        DateTime(_selectedYear - 1, 12, 31, 23, 59, 59),
      );
    }
    final prevMonth = _selectedMonth! == 1 ? 12 : _selectedMonth! - 1;
    final prevYear = _selectedMonth! == 1 ? _selectedYear - 1 : _selectedYear;
    final lastDay = DateTime(prevYear, prevMonth + 1, 0).day;
    return (
      DateTime(prevYear, prevMonth, 1),
      DateTime(prevYear, prevMonth, lastDay, 23, 59, 59),
    );
  }

  // ── PERSISTÊNCIA DE META ───────────────────────
  Future<void> _loadMonthlyGoal() async {
    if (_shopId == null || _selectedMonth == null) {
      if (mounted) {
        setState(() {
          _metaMensal = 0;
          _metaController.text = '';
        });
      }
      return;
    }

    final goalId = "${_selectedYear}_$_selectedMonth";
    try {
      final supabase = sb.Supabase.instance.client;
      final doc = await supabase
          .from('financial_goals')
          .select()
          .eq('shop_id', _shopId!)
          .eq('goal_id', goalId)
          .maybeSingle();

      if (doc != null) {
        final val = _toDouble(doc['value']);
        if (mounted) {
          setState(() {
            _metaMensal = val;
            _metaController.text = val > 0 ? val.toStringAsFixed(0) : '';
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _metaMensal = 0;
            _metaController.text = '';
          });
        }
      }
    } catch (e) {
      debugPrint('Erro ao carregar meta: $e');
    }
  }

  Future<void> _saveMonthlyGoal(double value, {bool applyToYear = false}) async {
    if (_shopId == null) return;
    
    try {
      final supabase = sb.Supabase.instance.client;
      final List<Map<String, dynamic>> goalsToUpsert = [];

      if (applyToYear) {
        for (int m = 1; m <= 12; m++) {
          final goalId = "${_selectedYear}_$m";
          goalsToUpsert.add({
            'shopId': _shopId,
            'goal_id': goalId,
            'value': value,
            'updatedAt': DateTime.now().toIso8601String(),
            'year': _selectedYear,
            'month': m,
          });
        }
      } else {
        if (_selectedMonth == null) return;
        final goalId = "${_selectedYear}_$_selectedMonth";
        goalsToUpsert.add({
          'shopId': _shopId,
          'goal_id': goalId,
          'value': value,
          'updatedAt': DateTime.now().toIso8601String(),
          'year': _selectedYear,
          'month': _selectedMonth,
        });
      }

      await supabase.from('financial_goals').upsert(goalsToUpsert);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(applyToYear 
              ? 'Meta aplicada a todos os meses de $_selectedYear!' 
              : 'Meta salva com sucesso!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      debugPrint('Erro ao salvar meta: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Erro ao salvar meta. Tente novamente.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // ─────────────────────────────────────────────
  // REFRESH PRINCIPAL
  // ─────────────────────────────────────────────
  Future<void> _refresh() async {
    if (_shopId == null) return;
    if (mounted) setState(() => _isLoading = true);

    try {
      final (start, end) = _currentRange();
      final (prevStart, prevEnd) = _previousRange();

      // Busca paralela do período atual e do anterior
      final results = await Future.wait([
        _fetchAppointments(start, end),
        _fetchTransactions(start, end),
        _fetchEmployees(),
        _fetchAppointments(prevStart, prevEnd),
        _fetchTransactions(prevStart, prevEnd),
      ]);

      final currentAppts = results[0];
      final currentTrans = results[1];
      final employees = results[2];
      final prevAppts = results[3];
      final prevTrans = results[4];

      // Busca a meta do mês no Firestore
      await _loadMonthlyGoal();

      _calculateMetrics(currentAppts, currentTrans, employees);
      _calculatePreviousPeriod(prevAppts, prevTrans);
    } catch (e) {
      debugPrint('Erro ao atualizar dashboard financeiro: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<List<Map<String, dynamic>>> _fetchAppointments(
      DateTime start, DateTime end) async {
    final supabase = sb.Supabase.instance.client;
    final res = await supabase
        .from('appointments')
        .select()
        .eq('shop_id', _shopId!)
        .gte('scheduled_at', start.toIso8601String())
        .lte('scheduled_at', end.toIso8601String());
    return List<Map<String, dynamic>>.from(res);
  }

  Future<List<Map<String, dynamic>>> _fetchTransactions(
      DateTime start, DateTime end) async {
    final supabase = sb.Supabase.instance.client;
    final res = await supabase
        .from('financial_transactions')
        .select()
        .eq('shop_id', _shopId!)
        .gte('data', start.toIso8601String())
        .lte('data', end.toIso8601String());
    return List<Map<String, dynamic>>.from(res);
  }

  Future<List<Map<String, dynamic>>> _fetchEmployees() async {
    final supabase = sb.Supabase.instance.client;
    final res = await supabase
        .from('employees')
        .select()
        .eq('shop_id', _shopId!);
    return List<Map<String, dynamic>>.from(res);
  }

  // ─────────────────────────────────────────────
  // CÁLCULO DO PERÍODO ANTERIOR (para delta %)
  // ─────────────────────────────────────────────
  void _calculatePreviousPeriod(
      List<Map<String, dynamic>> appts, List<Map<String, dynamic>> trans) {
    double rev = 0, exp = 0, com = 0;
    int completed = 0, cancelled = 0;

    for (var d in appts) {
      final status = (d['status'] ?? '').toString().toLowerCase();
      final value = _getAppointmentValue(d);
      if (_isCompleted(status)) {
        completed++;
        rev += value;
        final comPct = _toDouble(d['commission_percent']);
        if (comPct > 0) com += value * comPct / 100;
      } else if (status == 'cancelado') {
        cancelled++;
      }
    }
    for (var d in trans) {
      final val = (d['valor'] as num?)?.toDouble() ?? 0;
      if (val < 0 && (d['tipo'] ?? '') != 'comissao') exp += val.abs();
    }

    _prevPeriod = _PeriodMetrics(
      receita: rev,
      despesa: exp,
      comissao: com,
      atendimentos: completed,
      cancelamentos: cancelled,
      ticketMedio: completed > 0 ? rev / completed : 0,
    );
  }

  // ─────────────────────────────────────────────
  // CÁLCULO PRINCIPAL
  // ─────────────────────────────────────────────
  void _calculateMetrics(
    List<Map<String, dynamic>> appts,
    List<Map<String, dynamic>> trans,
    List<Map<String, dynamic>> emps,
  ) {
    double totalRevenue = 0;
    double totalExpense = 0;
    double totalCommission = 0;
    int completed = 0;
    int cancelled = 0;
    int workedMinutes = 0;

    Map<String, double> payments = {'PIX': 0, 'Cartão': 0, 'Dinheiro': 0};
    Map<String, double> servicesMap = {};
    Map<String, double> profissionaisMap = {};
    Map<int, double> dailyRevenue = {};
    Map<int, int> dailyAppts = {};
    Map<int, _HourlySlot> hourlySlots = {};

    Map<String, double> empCommissions = {};
    Map<String, String> empNames = {};
    Map<String, _ProfessionalEfficiency> profEffMap = {};
    for (var d in emps) {
      final id = d['id'].toString();
      final name = (d['name'] ?? d['nome'] ?? 'Profissional').toString();
      empCommissions[id] = _toDouble(d['commission_percent']);
      empNames[id] = name;
      profEffMap[id] = _ProfessionalEfficiency(id: id, nome: name);
    }

    for (var data in appts) {
      final status = (data['status'] ?? '').toString().toLowerCase();

      if (data['scheduled_at'] == null) continue;

      final value = _getAppointmentValue(data);
      final service = (data['service_name'] ?? 'Outros').toString();
      final date = DateTime.parse(data['scheduled_at'].toString());
      final empId = data['professional_id']?.toString();
      final duration = int.tryParse(
              (data['duration_min'] ?? '30').toString()) ??
          30;

      if (_isCompleted(status)) {
        completed++;
        totalRevenue += value;
        workedMinutes += duration;
        servicesMap[service] = (servicesMap[service] ?? 0) + value;

        if (empId != null) {
          if (!profEffMap.containsKey(empId)) {
            final nome = data['professional_name'] ?? 'Profissional';
            profEffMap[empId] = _ProfessionalEfficiency(id: empId, nome: nome);
          }
          profEffMap[empId]!..receita += value..minutosTrabalhados += duration;
        }

        if (empId != null && empCommissions.containsKey(empId)) {
          final com = value * empCommissions[empId]! / 100;
          totalCommission += com;
          final nome = empNames[empId] ?? 'Profissional';
          profissionaisMap[nome] = (profissionaisMap[nome] ?? 0) + value;
        } else if (empId != null) {
          final nome = empNames[empId] ?? 'Profissional';
          profissionaisMap[nome] = (profissionaisMap[nome] ?? 0) + value;
        }

        final method =
            (data['payment_method'] ?? 'Dinheiro').toString().toLowerCase();
        if (method.contains('pix')) {
          payments['PIX'] = (payments['PIX'] ?? 0) + value;
        } else if (method.contains('cart') ||
            method.contains('cred') ||
            method.contains('deb')) {
          payments['Cartão'] = (payments['Cartão'] ?? 0) + value;
        } else {
          payments['Dinheiro'] = (payments['Dinheiro'] ?? 0) + value;
        }

        final key = _selectedMonth == null ? date.month : date.day;
        dailyRevenue[key] = (dailyRevenue[key] ?? 0) + value;
        dailyAppts[key] = (dailyAppts[key] ?? 0) + 1;

        final slotKey = _selectedMonth == null
            ? date.month
            : ((date.day - 1) ~/ 7) + 1; 
        hourlySlots.putIfAbsent(slotKey, _HourlySlot.new)
          ..receita += value
          ..minutos += duration;
      } else if (status == 'cancelado') {
        cancelled++;
      }
    }

    // ── Transações extras (despesas) ──────────────
    // FIX: exclui registros do tipo 'comissao' para evitar dupla contagem
    for (var d in trans) {
      final val = (d['valor'] as num?)?.toDouble() ?? 0;
      final tipo = (d['tipo'] ?? '').toString().toLowerCase();
      if (val < 0 && tipo != 'comissao') totalExpense += val.abs();
    }

    int potentialMinutes = 0;
    for (var d in emps) {
      final id = d['id'].toString();
      final startStr = d['start_time']?.toString() ?? '08:00';
      final endStr = d['end_time']?.toString() ?? '18:00';
      final List diasTrabList =
          (d['work_days'] as List?) ?? [1, 2, 3, 4, 5, 6];

      try {
        final sParts = startStr.split(':');
        final eParts = endStr.split(':');
        final sMin = int.parse(sParts[0]) * 60 + int.parse(sParts[1]);
        final eMin = int.parse(eParts[0]) * 60 + int.parse(eParts[1]);
        final jornadaDiaria = eMin - sMin;
        if (jornadaDiaria <= 0) continue;

        int profPotentialMin = 0;
        final profId = id;

        if (_selectedMonth != null) {
          final firstDay = DateTime(_selectedYear, _selectedMonth!, 1);
          final lastDay = DateTime(_selectedYear, _selectedMonth! + 1, 0);
          for (int i = 0; i < lastDay.day; i++) {
            final day = firstDay.add(Duration(days: i));
            final wday = day.weekday == 7 ? 0 : day.weekday;
            if (diasTrabList.contains(day.weekday) ||
                diasTrabList.contains(wday)) {
              potentialMinutes += jornadaDiaria;
              profPotentialMin += jornadaDiaria;
            }
          }
        } else {
          final firstDay = DateTime(_selectedYear, 1, 1);
          final lastDay = DateTime(_selectedYear, 12, 31);
          for (int i = 0; i <= lastDay.difference(firstDay).inDays; i++) {
            final day = firstDay.add(Duration(days: i));
            final wday = day.weekday == 7 ? 0 : day.weekday;
            if (diasTrabList.contains(day.weekday) ||
                diasTrabList.contains(wday)) {
              potentialMinutes += jornadaDiaria;
              profPotentialMin += jornadaDiaria;
            }
          }
        }
        
        if (profEffMap.containsKey(profId)) {
          profEffMap[profId]!.minutosPotenciais = profPotentialMin;
        }
      } catch (_) {}
    }

    // ── Métricas derivadas ────────────────────────
    final horasTrab = workedMinutes / 60.0;
    final horasPot = potentialMinutes / 60.0;
    final ticketMedio = completed > 0 ? totalRevenue / completed : 0.0;

    // FIX: faturamento potencial baseado em projeção linear de ocupação
    // Se ocupação for X%, potencial seria receita / X%
    double faturamentoPotencial = 0.0;
    if (potentialMinutes > 0 && workedMinutes > 0) {
      final ocupacao = workedMinutes / potentialMinutes; // 0.0–1.0
      faturamentoPotencial = ocupacao > 0 ? totalRevenue / ocupacao : 0.0;
    }

    // ── Top listas ────────────────────────────────
    final sortedServices = (servicesMap.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value)))
        .take(5);

    final sortedProfissionais = (profissionaisMap.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value)))
        .take(5);

    // ── Atribuição ao estado ──────────────────────
    _topServices = Map.fromEntries(sortedServices);
    _topProfissionais = Map.fromEntries(sortedProfissionais);
    _totalReceita = totalRevenue;
    _totalDespesa = totalExpense;
    _totalComissao = totalCommission;
    _lucroLiquido = totalRevenue - totalExpense - totalCommission;
    _margemLiquida =
        totalRevenue > 0 ? ((_lucroLiquido / totalRevenue) * 100) : 0.0;
    _totalAtendimentos = completed;
    _totalCancelamentos = cancelled;
    _ticketMedio = ticketMedio;
    _paymentMethods = Map.from(payments)
      ..removeWhere((_, v) => v == 0); // remove formas com R$ 0

    _horasTrabalhadasMin = workedMinutes;
    _horasPotenciaisMin = potentialMinutes;
    _valorPorHora = horasTrab > 0 ? totalRevenue / horasTrab : 0;
    _faturamentoPotencial = faturamentoPotencial;
    _taxaOcupacao =
        horasPot > 0 ? math.min(100.0, (horasTrab / horasPot) * 100) : 0;

    // ── Eficiência da Equipe ──────────────────────
    _professionalEfficiency = profEffMap.values.toList()
      ..sort((a, b) => b.receita.compareTo(a.receita));

    // ── Produtividade granular ────────────────────
    _hourlyByPeriod = hourlySlots;
    final slotsComDados =
        hourlySlots.entries.where((e) => e.value.minutos > 0).toList();
    if (slotsComDados.isNotEmpty) {
      slotsComDados
          .sort((a, b) => b.value.valorPorHora.compareTo(a.value.valorPorHora));
      _valorPorHoraPico = slotsComDados.first.value.valorPorHora;
      _periodoMaisProdutivo = slotsComDados.first.key;
      _valorPorHoraVale = slotsComDados.last.value.valorPorHora;
    } else {
      _valorPorHoraPico = _valorPorHoraVale = 0;
      _periodoMaisProdutivo = 0;
    }

    _revenueSpots = (dailyRevenue.entries
        .map((e) => FlSpot(e.key.toDouble(), e.value))
        .toList()
      ..sort((a, b) => a.x.compareTo(b.x)));
    _appointmentSpots = (dailyAppts.entries
        .map((e) => FlSpot(e.key.toDouble(), e.value.toDouble()))
        .toList()
      ..sort((a, b) => a.x.compareTo(b.x)));
  }

  // ─────────────────────────────────────────────
  // HELPERS
  // ─────────────────────────────────────────────
  double _toDouble(dynamic v) => double.tryParse(v?.toString() ?? '0') ?? 0.0;

  double _getAppointmentValue(Map<String, dynamic> data) {
    return double.tryParse(data['total_value']?.toString() ??
            data['total_price']?.toString() ??
            data['valor_total']?.toString() ??
            data['price']?.toString() ??
            data['valor']?.toString() ??
            "0") ??
        0.0;
  }

  bool _isCompleted(String status) =>
      status == 'concluido' ||
      status == 'finalizado' ||
      status == 'pago' ||
      status == 'completed' ||
      status == 'efetuado';

  /// Retorna delta percentual entre [current] e [prev].
  /// Positivo = crescimento, negativo = queda.
  double? _delta(double current, double prev) {
    if (prev == 0) return null;
    return ((current - prev) / prev) * 100;
  }

  String _fmtCurrency(double v) =>
      NumberFormat.simpleCurrency(locale: 'pt_BR').format(v);

  // ─────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    if (_isLoading && _totalAtendimentos == 0 && _totalReceita == 0) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(color: AppColors.primaryPurple),
        ),
      );
    }

    if (_shopId == null) {
      return Scaffold(
        body: Center(
          child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: const [
                Icon(Icons.error_outline, size: 60, color: Colors.red),
                SizedBox(height: 16),
                Text('Erro ao carregar dados da loja'),
              ]),
        ),
      );
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
                    featureName: 'Dashboard Financeiro', requiredPlan: 'Plus');
                Navigator.pop(context);
              }
            });
          }
        }

        return Scaffold(
          backgroundColor: const Color(0xFFF4F6FB),
          body: RefreshIndicator(
            onRefresh: _refresh,
            color: AppColors.primaryPurple,
            child: CustomScrollView(
              slivers: [
                // ── Header ──────────────────────────
                SliverToBoxAdapter(child: _buildHeader(isMobile)),

                // ── Progresso da Meta ────────────────
                if (_selectedMonth != null && _metaMensal > 0)
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                    sliver: SliverToBoxAdapter(child: _buildGoalProgress()),
                  ),

                // ── Resumo Financeiro ────────────────
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  sliver: SliverToBoxAdapter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _sectionTitle('Resumo Financeiro'),
                        _buildFinancialSummary(isMobile),
                        const SizedBox(height: 24),
                        _sectionTitle('Desempenho de Vendas'),
                        _buildSalesPerformance(isMobile),
                        const SizedBox(height: 24),
                        _sectionTitle('Eficiência Operacional'),
                        _buildOperationalEfficiency(isMobile),
                        const SizedBox(height: 24),
                        _sectionTitle('Eficiência da Equipe'),
                        _buildProfessionalEfficiency(isMobile),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ),

                // ── Gráfico Principal ────────────────
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  sliver: SliverToBoxAdapter(child: _buildMainChart()),
                ),

                // ── Gráfico Valor/Hora por Período ───
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  sliver: SliverToBoxAdapter(child: _buildHourlyRateChart()),
                ),

                // ── Linha de Insights ────────────────
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                  sliver: SliverToBoxAdapter(
                    child: _buildInsightsRow(isMobile),
                  ),
                ),
              ],
            ),
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: _showTransactionDialog,
            backgroundColor: AppColors.primaryPurple,
            foregroundColor: Colors.white,
            icon: const Icon(Icons.add_chart_rounded),
            label: const Text('Novo Lançamento', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        );
      },
    );
  }

  // ─────────────────────────────────────────────
  // HEADER
  // ─────────────────────────────────────────────
  Widget _buildHeader(bool isMobile) {
    return Container(
      padding: EdgeInsets.fromLTRB(20, isMobile ? 40 : 20, 20, 16),
      child: Row(
        children: [
          // ── Botão de Meta ──────────────────────
          if (_selectedMonth != null) Tooltip(
            message: 'Definir meta mensal',
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => _showGoalDialog(),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey[300]!),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.flag_outlined,
                        size: 16,
                        color: _metaMensal > 0
                            ? AppColors.primaryPurple
                            : Colors.grey[500]),
                    const SizedBox(width: 6),
                    Text(
                      _metaMensal > 0
                          ? _fmtCurrency(_metaMensal)
                          : 'Definir meta',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: _metaMensal > 0
                            ? AppColors.primaryPurple
                            : Colors.grey[500],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const Spacer(),
          // ── Filtros de data ────────────────────
          _dropdown<int?>(
            _selectedMonth,
            [
              const DropdownMenuItem(value: null, child: Text('Ano Todo')),
              ...List.generate(
                  12,
                  (i) =>
                      DropdownMenuItem(value: i + 1, child: Text(_months[i]))),
            ],
            (v) => setState(() {
              _selectedMonth = v;
              _refresh();
            }),
          ),
          const SizedBox(width: 8),
          _dropdown<int>(
            _selectedYear,
            _availableYears
                .map((y) =>
                    DropdownMenuItem(value: y, child: Text(y.toString())))
                .toList(),
            (v) => setState(() {
              if (v != null) {
                _selectedYear = v;
                _refresh();
              }
            }),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────
  // BARRA DE PROGRESSO DA META
  // ─────────────────────────────────────────────
  Widget _buildGoalProgress() {
    final progress = math.min(1.0, _totalReceita / _metaMensal);
    final pct = (progress * 100).toStringAsFixed(1);
    final faltam = _metaMensal - _totalReceita;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '🎯 Meta do período',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: Colors.grey[800],
                ),
              ),
              Text(
                '$pct%',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color:
                      progress >= 1.0 ? Colors.green : AppColors.primaryPurple,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 10,
              backgroundColor: Colors.grey[200],
              color: progress >= 1.0 ? Colors.green : AppColors.primaryPurple,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            faltam > 0
                ? 'Faltam ${_fmtCurrency(faltam)} para atingir a meta'
                : '✅ Meta atingida! Faturamento ${_fmtCurrency(-faltam)} acima',
            style: TextStyle(
              fontSize: 12,
              color: faltam > 0 ? Colors.grey[500] : Colors.green,
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────
  // SEÇÃO: RESUMO FINANCEIRO
  // ─────────────────────────────────────────────
  Widget _buildFinancialSummary(bool isMobile) {
    final prev = _prevPeriod;
    return _buildOptimizedGrid(
      isMobile: isMobile,
      children: [
        _MetricCard(
          title: 'Faturamento',
          value: _fmtCurrency(_totalReceita),
          icon: Icons.payments_outlined,
          color: Colors.blue,
          delta: prev != null ? _delta(_totalReceita, prev.receita) : null,
        ),
        _MetricCard(
          title: 'Despesas',
          value: _fmtCurrency(_totalDespesa),
          icon: Icons.money_off_outlined,
          color: Colors.red,
          delta: prev != null ? _delta(_totalDespesa, prev.despesa) : null,
          invertDelta: true, // para despesas, subir é ruim
        ),
        _MetricCard(
          title: 'Comissões',
          value: _fmtCurrency(_totalComissao),
          icon: Icons.person_outline,
          color: Colors.orange,
          delta: prev != null ? _delta(_totalComissao, prev.comissao) : null,
        ),
        _MetricCard(
          title: 'Lucro Líquido',
          value: _fmtCurrency(_lucroLiquido),
          icon: Icons.account_balance_wallet_outlined,
          color: _lucroLiquido >= 0 ? Colors.green : Colors.red,
          subtitle: 'Margem: ${_margemLiquida.toStringAsFixed(1)}%',
          delta: prev != null
              ? _delta(
                  _lucroLiquido, prev.receita - prev.despesa - prev.comissao)
              : null,
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────
  // SEÇÃO: DESEMPENHO DE VENDAS
  // ─────────────────────────────────────────────
  Widget _buildSalesPerformance(bool isMobile) {
    final prev = _prevPeriod;
    final totalAppts = _totalAtendimentos + _totalCancelamentos;
    final cancelRate =
        totalAppts > 0 ? (_totalCancelamentos / totalAppts * 100) : 0.0;

    return _buildOptimizedGrid(
      isMobile: isMobile,
      children: [
        _MetricCard(
          title: 'Agendamentos',
          value: _totalAtendimentos.toString(),
          icon: Icons.event_available_outlined,
          color: Colors.purple,
          delta: prev != null
              ? _delta(
                  _totalAtendimentos.toDouble(), prev.atendimentos.toDouble())
              : null,
        ),
        _MetricCard(
          title: 'Ticket Médio',
          value: _fmtCurrency(_ticketMedio),
          icon: Icons.trending_up,
          color: Colors.teal,
          delta: prev != null ? _delta(_ticketMedio, prev.ticketMedio) : null,
        ),
        _MetricCard(
          title: 'Cancelamentos',
          value: _totalCancelamentos.toString(),
          icon: Icons.event_busy_outlined,
          color: Colors.redAccent,
          // NOVO: exibe taxa de cancelamento %
          subtitle:
              totalAppts > 0 ? 'Taxa: ${cancelRate.toStringAsFixed(1)}%' : null,
          delta: prev != null
              ? _delta(
                  _totalCancelamentos.toDouble(), prev.cancelamentos.toDouble())
              : null,
          invertDelta: true,
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────
  // SEÇÃO: EFICIÊNCIA OPERACIONAL
  // ─────────────────────────────────────────────
  Widget _buildOperationalEfficiency(bool isMobile) {
    final totalHours = _horasPotenciaisMin / 60.0;
    final workedHours = _horasTrabalhadasMin / 60.0;
    final idleHours = math.max(0.0, totalHours - workedHours);

    return Column(
      children: [
        // Barra de ocupação visual (NOVO)
        Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Taxa de Ocupação',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey[700],
                    ),
                  ),
                  _OccupancyBadge(rate: _taxaOcupacao),
                ],
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: _taxaOcupacao / 100,
                  minHeight: 12,
                  backgroundColor: Colors.grey[200],
                  color: _taxaOcupacao >= 80
                      ? Colors.green
                      : _taxaOcupacao >= 50
                          ? Colors.orange
                          : Colors.red,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 16,
                runSpacing: 8,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _LegendDot(color: AppColors.primaryPurple),
                      const SizedBox(width: 4),
                      Text('Trabalhado: ${workedHours.toStringAsFixed(1)}h',
                          style: const TextStyle(fontSize: 11)),
                    ],
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _LegendDot(color: Colors.grey[300]!),
                      const SizedBox(width: 4),
                      Text('Ocioso: ${idleHours.toStringAsFixed(1)}h',
                          style: const TextStyle(fontSize: 11)),
                    ],
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _LegendDot(color: Colors.blue[200]!),
                      const SizedBox(width: 4),
                      Text('Total: ${totalHours.toStringAsFixed(1)}h',
                          style: const TextStyle(fontSize: 11)),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),

        _buildOptimizedGrid(
          isMobile: isMobile,
          children: [
            _MetricCard(
              title: 'Horas Trabalhadas',
              value: '${workedHours.toStringAsFixed(1)}h',
              icon: Icons.timer_outlined,
              color: Colors.green,
              subtitle: 'De ${totalHours.toStringAsFixed(1)}h disponíveis',
            ),
            _MetricCard(
              title: 'Horas Ociosas',
              value: '${idleHours.toStringAsFixed(1)}h',
              icon: Icons.hourglass_empty_rounded,
              color: Colors.orange,
              subtitle: 'Potencial não aproveitado',
            ),
            _MetricCard(
              title: 'Valor por Hora',
              value: _fmtCurrency(_valorPorHora),
              icon: Icons.speed_rounded,
              color: Colors.deepPurple,
              subtitle: _valorPorHoraPico > 0
                  ? 'Pico: ${_fmtCurrency(_valorPorHoraPico)}'
                  : 'Produtividade média',
            ),
            _MetricCard(
              title: 'Faturamento Potencial',
              value: _fmtCurrency(_faturamentoPotencial),
              icon: Icons.trending_up_rounded,
              color: Colors.teal,
              // NOVO: mostra quanto pode crescer em %
              subtitle: _totalReceita > 0 &&
                      _faturamentoPotencial > _totalReceita
                  ? '+${((_faturamentoPotencial / _totalReceita - 1) * 100).toStringAsFixed(0)}% de crescimento'
                  : 'Projeção a 100%',
            ),
          ],
        ),
      ],
    );
  }
  Widget _buildProfessionalEfficiency(bool isMobile) {
    if (_professionalEfficiency.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Text('Sem dados de equipe no período',
              style: TextStyle(color: Colors.grey[400])),
        ),
      );
    }

    return Column(
      children: _professionalEfficiency.map((prof) {
        final workedHours = prof.minutosTrabalhados / 60.0;
        final occupation = prof.taxaOcupacao;

        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: AppColors.primaryPurple.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Text(
                            prof.nome.isNotEmpty ? prof.nome[0].toUpperCase() : '?',
                            style: const TextStyle(
                                color: AppColors.primaryPurple,
                                fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        prof.nome,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  _OccupancyBadge(rate: occupation),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: occupation / 100,
                  minHeight: 8,
                  backgroundColor: Colors.grey[100],
                  color: occupation >= 80
                      ? Colors.green
                      : occupation >= 50
                          ? Colors.orange
                          : Colors.red,
                ),
              ),
              const SizedBox(height: 10),
              _buildOptimizedGrid(
                isMobile: isMobile,
                crossAxisCount: isMobile ? 2 : 4,
                children: [
                  _MetricCard(
                    title: 'Receita/Hora',
                    value: _fmtCurrency(prof.valorPorHora),
                    icon: Icons.speed_rounded,
                    color: Colors.deepPurple,
                  ),
                  _MetricCard(
                    title: 'Ocupação',
                    value: '${occupation.toStringAsFixed(0)}%',
                    icon: Icons.pie_chart_outline,
                    color: Colors.teal,
                  ),
                  _MetricCard(
                    title: 'Trabalhado',
                    value: '${workedHours.toStringAsFixed(1)}h',
                    icon: Icons.timer_outlined,
                    color: Colors.blue,
                  ),
                  _MetricCard(
                    title: 'Potencial',
                    value: _fmtCurrency(prof.faturamentoPotencial),
                    icon: Icons.trending_up,
                    color: Colors.green,
                  ),
                ],
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  // Widget auxiliar para métricas pequenas na lista da equipe

  // ─────────────────────────────────────────────
  // GRID GENÉRICO
  // ─────────────────────────────────────────────
  Widget _buildOptimizedGrid({
    required bool isMobile,
    required List<Widget> children,
    int? crossAxisCount,
  }) {
    return GridView.count(
      crossAxisCount: crossAxisCount ?? (isMobile ? 2 : 4),
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: isMobile ? 1.7 : 2.0,
      children: children,
    );
  }

  // ─────────────────────────────────────────────
  // GRÁFICO PRINCIPAL
  // ─────────────────────────────────────────────
  Widget _buildMainChart() {
    return _DashboardContainer(
      title: 'Fluxo de Receita e Agendamentos',
      subtitle: _selectedMonth == null ? 'Visão Mensal' : 'Visão Diária',
      child: Column(
        children: [
          // NOVO: legenda do gráfico
          Wrap(
            spacing: 16,
            runSpacing: 8,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _LegendDot(color: AppColors.primaryPurple),
                  const SizedBox(width: 4),
                  const Text('Receita (R\$)', style: TextStyle(fontSize: 11)),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _LegendDot(
                      color: Colors.purple.withValues(alpha: 0.5), isDashed: true),
                  const SizedBox(width: 4),
                  const Text('Agendamentos', style: TextStyle(fontSize: 11)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 280,
            child: _revenueSpots.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.bar_chart,
                            size: 48, color: Colors.grey[300]),
                        const SizedBox(height: 8),
                        Text('Sem dados para exibir',
                            style: TextStyle(color: Colors.grey[500])),
                      ],
                    ),
                  )
                : LineChart(
                    LineChartData(
                      lineTouchData: LineTouchData(
                        touchTooltipData: LineTouchTooltipData(
                          getTooltipItems: (touchedSpots) {
                            return touchedSpots.map((spot) {
                              final isRevenue = spot.barIndex == 0;
                              final label = isRevenue
                                  ? _fmtCurrency(spot.y)
                                  : '${spot.y.toInt()} agend.';
                              return LineTooltipItem(
                                label,
                                TextStyle(
                                  color: isRevenue
                                      ? AppColors.primaryPurple
                                      : Colors.purple,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              );
                            }).toList();
                          },
                        ),
                      ),
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
                            reservedSize: 56,
                            getTitlesWidget: (v, _) => Text(
                              v >= 1000
                                  ? 'R\$${(v / 1000).toStringAsFixed(0)}k'
                                  : 'R\$${v.toInt()}',
                              style: TextStyle(
                                  fontSize: 10, color: Colors.grey[500]),
                            ),
                          ),
                        ),
                        rightTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 28,
                            getTitlesWidget: (v, _) => Text(
                              v.toInt().toString(),
                              style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.purple.withValues(alpha: 0.6)),
                            ),
                          ),
                        ),
                        topTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false)),
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            getTitlesWidget: (v, _) {
                              final i = v.toInt();
                              if (_selectedMonth == null) {
                                if (i >= 1 && i <= 12) {
                                  return Text(_months[i - 1],
                                      style: const TextStyle(fontSize: 10));
                                }
                              } else {
                                if (i == 1 || i % 5 == 0) {
                                  return Text(i.toString(),
                                      style: const TextStyle(fontSize: 10));
                                }
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
                          belowBarData: BarAreaData(
                            show: true,
                            color:
                                AppColors.primaryPurple.withValues(alpha: 0.08),
                          ),
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
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────
  // GRÁFICO DE VALOR POR HORA (granular por período)
  // ─────────────────────────────────────────────
  // Visão anual  → barra por mês (Jan–Dez)
  // Visão mensal → barra por semana (Sem 1–5)
  // Cada barra representa: Σ receita do período / Σ horas trabalhadas do período
  // As horas são a soma das durações reais dos serviços concluídos (não horas
  // potenciais), então o valor reflete a produtividade real por hora ocupada.
  // ─────────────────────────────────────────────
  Widget _buildHourlyRateChart() {
    if (_hourlyByPeriod.isEmpty) return const SizedBox();

    final isAnnual = _selectedMonth == null;
    final maxKey = isAnnual ? 12 : 5;

    // Monta a lista ordenada cobrindo todos os slots do período
    // (mesmo os sem dados, para manter o eixo X contínuo)
    final allBars = List.generate(maxKey, (i) {
      final key = i + 1;
      final slot = _hourlyByPeriod[key];
      return BarChartGroupData(
        x: key,
        barRods: [
          BarChartRodData(
            toY: slot?.valorPorHora ?? 0,
            width: isAnnual ? 18 : 28,
            borderRadius: BorderRadius.circular(6),
            // Destaca o período mais produtivo
            color: (slot != null && key == _periodoMaisProdutivo)
                ? Colors.deepPurple
                : AppColors.primaryPurple.withValues(alpha: 0.65),
            backDrawRodData: BackgroundBarChartRodData(
              show: true,
              toY: _valorPorHoraPico * 1.15,
              color: Colors.grey[100],
            ),
          ),
        ],
      );
    });

    // Rótulo do eixo X
    String xLabel(int x) {
      if (isAnnual) return _months[x - 1];
      return "R\$ $x";
    }

    // Subtítulo dinâmico
    String subtitle = isAnnual
        ? 'Receita ÷ horas de serviço por mês'
        : 'Receita ÷ horas de serviço por semana';

    return _DashboardContainer(
      title: 'Valor Gerado por Hora Trabalhada',
      subtitle: subtitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Destaque do pico ──────────────────────
          if (_valorPorHoraPico > 0) ...[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildChip(
                  '↑ Pico: ${_fmtCurrency(_valorPorHoraPico)}/h',
                  Colors.deepPurple,
                ),
                _buildChip(
                  '↓ Vale: ${_fmtCurrency(_valorPorHoraVale)}/h',
                  Colors.orange,
                ),
                _buildChip(
                  'Média: ${_fmtCurrency(_valorPorHora)}/h',
                  Colors.teal,
                ),
              ],
            ),
            const SizedBox(height: 16),
          ],
          SizedBox(
            height: 220,
            child: BarChart(
              BarChartData(
                maxY: _valorPorHoraPico > 0 ? _valorPorHoraPico * 1.15 : 10,
                barTouchData: BarTouchData(
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipItem: (group, groupIndex, rod, rodIndex) {
                      final slot = _hourlyByPeriod[group.x];
                      if (slot == null || slot.minutos == 0) return null;
                      final horas = (slot.minutos / 60.0).toStringAsFixed(1);
                      return BarTooltipItem(
                        '${xLabel(group.x)}\n'
                        '${_fmtCurrency(rod.toY)}/h\n'
                        '${_fmtCurrency(slot.receita)} em ${horas}h',
                        const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      );
                    },
                  ),
                ),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 52,
                      getTitlesWidget: (v, _) => Text(
                        v >= 1000
                            ? 'R\$${(v / 1000).toStringAsFixed(0)}k'
                            : 'R\$${v.toInt()}',
                        style: TextStyle(fontSize: 9, color: Colors.grey[500]),
                      ),
                    ),
                  ),
                  rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (v, _) => Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          xLabel(v.toInt()),
                          style:
                              TextStyle(fontSize: 10, color: Colors.grey[600]),
                        ),
                      ),
                    ),
                  ),
                ),
                borderData: FlBorderData(show: false),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (v) =>
                      FlLine(color: Colors.grey[200]!, strokeWidth: 1),
                ),
                barGroups: allBars,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style:
            TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color),
      ),
    );
  }

  // ─────────────────────────────────────────────
  // INSIGHTS ROW (Serviços, Pagamentos, Profissionais)
  // ─────────────────────────────────────────────
  Widget _buildInsightsRow(bool isMobile) {
    final paymentWidget = _DashboardContainer(
      title: 'Formas de Pagamento',
      child: _paymentMethods.isEmpty
          ? SizedBox(
              height: 180,
              child: Center(
                child: Text('Sem dados',
                    style: TextStyle(color: Colors.grey[400])),
              ),
            )
          : SizedBox(
              height: 200,
              child: Row(
                children: [
                  Expanded(
                    child: PieChart(
                      PieChartData(
                        sectionsSpace: 2,
                        centerSpaceRadius: 36,
                        pieTouchData: PieTouchData(
                          touchCallback: (event, response) {
                            setState(() {
                              _touchedIndex =
                                  response?.touchedSection?.touchedSectionIndex;
                            });
                          },
                        ),
                        sections: _buildPieSections(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: _paymentMethods.entries.map((e) {
                      final color = _paymentColor(e.key);
                      final pct = _totalReceita > 0
                          ? (e.value / _totalReceita * 100)
                          : 0.0;
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            _LegendDot(color: color),
                            const SizedBox(width: 6),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(e.key,
                                    style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600)),
                                Text(
                                  '${pct.toStringAsFixed(1)}%  •  ${_fmtCurrency(e.value)}',
                                  style: TextStyle(
                                      fontSize: 11, color: Colors.grey[500]),
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
    );

    final servicesWidget = _DashboardContainer(
      title: 'Serviços mais Rentáveis',
      child: _topServices.isEmpty
          ? Center(
              child:
                  Text('Sem dados', style: TextStyle(color: Colors.grey[400])))
          : Column(
              children: _topServices.entries.map((e) {
                final percent =
                    _totalReceita > 0 ? e.value / _totalReceita : 0.0;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(e.key,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w500, fontSize: 13)),
                          ),
                          const SizedBox(width: 8),
                          Text(_fmtCurrency(e.value),
                              style: const TextStyle(
                                  fontSize: 13, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: percent,
                                minHeight: 6,
                                backgroundColor: Colors.grey[200],
                                color: AppColors.primaryPurple,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '${(percent * 100).toStringAsFixed(0)}%',
                            style: TextStyle(
                                fontSize: 11, color: Colors.grey[500]),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
    );

    // NOVO: Top Profissionais
    final profissionaisWidget = _DashboardContainer(
      title: 'Top Profissionais',
      child: _topProfissionais.isEmpty
          ? Center(
              child:
                  Text('Sem dados', style: TextStyle(color: Colors.grey[400])))
          : Column(
              children: _topProfissionais.entries.map((e) {
                final percent =
                    _totalReceita > 0 ? e.value / _totalReceita : 0.0;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: AppColors.primaryPurple
                                  .withValues(alpha: 0.1),
                              shape: BoxShape.circle,
                            ),
                            child: Center(
                              child: Text(
                                e.key.isNotEmpty ? e.key[0].toUpperCase() : '?',
                                style: TextStyle(
                                    color: AppColors.primaryPurple,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(e.key,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 13)),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(4),
                                  child: LinearProgressIndicator(
                                    value: percent,
                                    minHeight: 5,
                                    backgroundColor: Colors.grey[200],
                                    color: Colors.teal,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(_fmtCurrency(e.value),
                              style: const TextStyle(
                                  fontSize: 12, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
    );

    if (isMobile) {
      return Column(children: [
        servicesWidget,
        const SizedBox(height: 16),
        paymentWidget,
        const SizedBox(height: 16),
        profissionaisWidget,
      ]);
    }

    return Column(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: servicesWidget),
            const SizedBox(width: 16),
            Expanded(child: paymentWidget),
          ],
        ),
        const SizedBox(height: 16),
        profissionaisWidget,
      ],
    );
  }

  List<PieChartSectionData> _buildPieSections() {
    int i = 0;
    return _paymentMethods.entries.map((e) {
      final isTouched = i == _touchedIndex;
      final radius = isTouched ? 58.0 : 50.0;
      final pct = _totalReceita > 0 ? e.value / _totalReceita * 100 : 0.0;
      i++;
      return PieChartSectionData(
        value: e.value,
        title: pct >= 10 ? '${pct.toStringAsFixed(0)}%' : '',
        color: _paymentColor(e.key),
        radius: radius,
        titleStyle: const TextStyle(
            fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
      );
    }).toList();
  }

  Color _paymentColor(String method) {
    switch (method) {
      case 'PIX':
        return Colors.teal;
      case 'Cartão':
        return Colors.blue;
      default:
        return Colors.orange;
    }
  }

  // ─────────────────────────────────────────────
  // DIALOG DE META
  // ─────────────────────────────────────────────
  void _showGoalDialog() {
    _metaController.text =
        _metaMensal > 0 ? _metaMensal.toStringAsFixed(0) : '';
    bool applyToYear = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.white,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
          contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primaryPurple.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.auto_graph_rounded,
                    color: AppColors.primaryPurple, size: 24),
              ),
              const SizedBox(width: 16),
              const Text('Meta Financeira',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Defina o objetivo de faturamento para manter seu negócio crescendo.',
                style: TextStyle(fontSize: 13, color: Colors.black54),
              ),
              const SizedBox(height: 24),
              TextField(
                controller: _metaController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                autofocus: true,
                style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primaryPurple),
                decoration: InputDecoration(
                  labelText: 'Valor da Meta',
                  prefixText: 'R\$ ',
                  prefixStyle: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: AppColors.primaryPurple),
                  labelStyle: const TextStyle(color: Colors.grey, fontSize: 14),
                  hintText: '0,00',
                  floatingLabelBehavior: FloatingLabelBehavior.always,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(color: Colors.grey.shade200),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(color: Colors.grey.shade200),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide:
                        const BorderSide(color: AppColors.primaryPurple, width: 2),
                  ),
                  filled: true,
                  fillColor: Colors.grey.shade50,
                ),
              ),
              const SizedBox(height: 12),
              Material(
                color: applyToYear
                    ? AppColors.primaryPurple.withValues(alpha: 0.05)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
                child: CheckboxListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                  title: Text('Replicar para todos os meses de $_selectedYear',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight:
                              applyToYear ? FontWeight.bold : FontWeight.normal,
                          color: applyToYear
                              ? AppColors.primaryPurple
                              : Colors.black87)),
                  value: applyToYear,
                  activeColor: AppColors.primaryPurple,
                  checkboxShape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4)),
                  onChanged: (val) {
                    setDialogState(() => applyToYear = val ?? false);
                  },
                  controlAffinity: ListTileControlAffinity.leading,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              style: TextButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
              child: const Text('Cancelar',
                  style: TextStyle(
                      color: Colors.grey, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(width: 4),
            ElevatedButton(
              onPressed: () {
                final v = double.tryParse(
                        _metaController.text.replaceAll(',', '.')) ??
                    0.0;
                setState(() => _metaMensal = v);
                _saveMonthlyGoal(v, applyToYear: applyToYear);
                Navigator.pop(ctx);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryPurple,
                foregroundColor: Colors.white,
                elevation: 0,
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              child: const Text('SALVAR META',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────
  // DIALOG DE NOVO LANÇAMENTO (DESPESA/RECEITA)
  // ─────────────────────────────────────────────
  void _showTransactionDialog() {
    final descController = TextEditingController();
    final valueController = TextEditingController();
    String tipo = 'despesa'; // padrão
    DateTime data = DateTime.now();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: (tipo == 'despesa' ? Colors.red : Colors.green).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  tipo == 'despesa' ? Icons.remove_circle_outline : Icons.add_circle_outline,
                  color: tipo == 'despesa' ? Colors.red : Colors.green,
                ),
              ),
              const SizedBox(width: 12),
              const Text('Novo Lançamento', style: TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Seletor de Tipo
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'despesa', label: Text('Despesa'), icon: Icon(Icons.trending_down, size: 16)),
                    ButtonSegment(value: 'receita', label: Text('Receita Extra'), icon: Icon(Icons.trending_up, size: 16)),
                  ],
                  selected: {tipo},
                  onSelectionChanged: (val) => setDialogState(() => tipo = val.first),
                  style: SegmentedButton.styleFrom(
                    selectedBackgroundColor: tipo == 'despesa' ? Colors.red[50] : Colors.green[50],
                    selectedForegroundColor: tipo == 'despesa' ? Colors.red : Colors.green,
                  ),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: descController,
                  decoration: InputDecoration(
                    labelText: 'Descrição',
                    hintText: 'Ex: Aluguel, Produtos, etc.',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    prefixIcon: const Icon(Icons.description_outlined),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: valueController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: 'Valor',
                    prefixText: 'R\$ ',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    prefixIcon: const Icon(Icons.payments_outlined),
                  ),
                ),
                const SizedBox(height: 16),
                // Seletor de Data
                InkWell(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: data,
                      firstDate: DateTime(2023),
                      lastDate: DateTime(2100),
                    );
                    if (picked != null) setDialogState(() => data = picked);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 15),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey[400]!),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.calendar_today_outlined, size: 20, color: Colors.grey),
                        const SizedBox(width: 12),
                        Text(DateFormat('dd/MM/yyyy').format(data)),
                        const Spacer(),
                        const Icon(Icons.arrow_drop_down),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('CANCELAR')),
            ElevatedButton(
              onPressed: () async {
                final double v = double.tryParse(valueController.text.replaceAll(',', '.')) ?? 0.0;
                if (v <= 0 || descController.text.isEmpty) return;

                final finalValue = tipo == 'despesa' ? -v : v;

                try {
                  await sb.Supabase.instance.client.from('financial_transactions').insert({
                    'shop_id': _shopId,
                    'descricao': descController.text.trim(),
                    'valor': finalValue,
                    'tipo': tipo,
                    'data': data.toIso8601String(),
                    'created_at': DateTime.now().toIso8601String(),
                  });
                  if (_shopId != null) {
                    ShopDataCacheService().invalidate(_shopId!, 'financial');
                  }
                  if (mounted) {
                    Navigator.pop(ctx);
                    _refresh();
                  }
                } catch (e) {
                  debugPrint('Erro ao salvar lançamento: $e');
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: tipo == 'despesa' ? Colors.red : Colors.green,
                foregroundColor: Colors.white,
              ),
              child: const Text('SALVAR LANÇAMENTO'),
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────
  // HELPERS DE BUILD
  // ─────────────────────────────────────────────
  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, left: 4),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: Colors.grey[500],
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _dropdown<T>(
      T value, List<DropdownMenuItem<T>> items, Function(T?) onChange) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          items: items,
          onChanged: onChange,
          style: const TextStyle(
              fontSize: 13, color: Colors.black, fontWeight: FontWeight.w500),
          icon: const Icon(Icons.keyboard_arrow_down, size: 18),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// WIDGETS AUXILIARES
// ─────────────────────────────────────────────

class _LegendDot extends StatelessWidget {
  final Color color;
  final bool isDashed;
  const _LegendDot({required this.color, this.isDashed = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        color: isDashed ? Colors.transparent : color,
        shape: BoxShape.circle,
        border: isDashed ? Border.all(color: color, width: 2) : null,
      ),
    );
  }
}

class _OccupancyBadge extends StatelessWidget {
  final double rate;
  const _OccupancyBadge({required this.rate});

  @override
  Widget build(BuildContext context) {
    final color = rate >= 80
        ? Colors.green
        : rate >= 50
            ? Colors.orange
            : Colors.red;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        '${rate.toStringAsFixed(1)}%',
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    );
  }
}

/// Card de métrica com suporte a delta % vs período anterior.
class _MetricCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;
  final String? subtitle;
  final double? delta;

  /// Se true, delta positivo é exibido como ruim (vermelho)
  final bool invertDelta;

  const _MetricCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
    this.subtitle,
    this.delta,
    this.invertDelta = false,
  });

  @override
  Widget build(BuildContext context) {
    Widget? deltaWidget;
    if (delta != null) {
      final isPositive = delta! >= 0;
      final isGood = invertDelta ? !isPositive : isPositive;
      deltaWidget = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isPositive ? Icons.arrow_upward : Icons.arrow_downward,
            size: 10,
            color: isGood ? Colors.green : Colors.red,
          ),
          const SizedBox(width: 2),
          Text(
            '${delta!.abs().toStringAsFixed(1)}%',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: isGood ? Colors.green : Colors.red,
            ),
          ),
        ],
      );
    }

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(icon, color: color, size: 14),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    title,
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey[600],
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87),
            ),
          ),
          const SizedBox(height: 2),
          Row(
            children: [
              if (subtitle != null)
                Expanded(
                  child: Text(
                    subtitle!,
                    style: TextStyle(fontSize: 10, color: Colors.grey[500]),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              if (deltaWidget != null) deltaWidget,
            ],
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

  const _DashboardContainer({
    required this.title,
    this.subtitle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1A1F36))),
          if (subtitle != null)
            Text(subtitle!,
                style: TextStyle(fontSize: 12, color: Colors.grey[500])),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}
