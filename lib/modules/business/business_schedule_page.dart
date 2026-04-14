import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';
import 'dart:async';
import '../../core/theme/app_colors.dart';
import 'appointment_details_page.dart';
import 'transaction_details_page.dart';
import '../../core/services/brasilapi_service.dart';
import '../clients/client_details_page.dart';
import '../../core/utils/availability_utils.dart';
import '../../core/services/shop_data_cache_service.dart';
import '../../core/services/transaction_autocomplete_service.dart';

class BusinessSchedulePage extends StatefulWidget {
  final String shopId;
  const BusinessSchedulePage({super.key, required this.shopId});

  @override
  State<BusinessSchedulePage> createState() => _BusinessSchedulePageState();
}

class _BusinessSchedulePageState extends State<BusinessSchedulePage>
    with AutomaticKeepAliveClientMixin {
  // --- CALENDÁRIO ---
  DateTime _focusedDay = DateTime.now();
  DateTime _selectedDay = DateTime.now();
  CalendarFormat _calendarFormat = CalendarFormat.week;

  // Eventos por dia (para pontinho laranja)
  Map<DateTime, List<String>> _events = {};
  // Keys para cada cabeçalho de dia (permitir scroll até o header)
  final Map<DateTime, GlobalKey> _dayKeys = {};

  // Holidays state
  List<dynamic> _nationalHolidays = [];
  List<Map<String, dynamic>> _globalHolidays = [];

  // --- CONTROLE DE LISTA ---
  final ScrollController _scrollController = ScrollController();
  List<Map<String, dynamic>> _appointments = [];
  // Cache simples por id para acesso rápido e evitar duplicatas
  final Map<String, Map<String, dynamic>> _docCache = {};
  final Map<String, DateTime> _cacheAccess = {};
  final int _cacheMaxEntries = 300; // limite de entradas no cache
  final Duration _cacheTTL =
      const Duration(minutes: 5); // tempo antes de validar novamente
  Timer? _cacheRefreshTimer;
  Timer? _realtimeDebounceTimer;
  bool _isLoading = false;
  bool _hasMore = true;
  bool _hasMorePast =
      true; // indica se há mais documentos no passado para carregar
  Map<String, dynamic>? _lastDocument;
  Map<String, dynamic>? _firstDocument;
  final int _perPage = 20;
  Map<String, dynamic> _shopConfig = {};

  // --- LÃ“GICA DE VISUALIZAÇÃO ---
  bool _showOnlySelectedDay = true;
  Map<String, dynamic>? _selectedAppointment;
  // Quando true, a lista abaixo do calendário começa a partir de _startFromDate (inclusive)
  bool _startFromSelectedDay = false;
  DateTime? _startFromDate;
  DateTime? _weekEndDate;

  // removed tabs: schedule shows active appointments by default
  bool _isOpeningQuickEntry = false;

  late final Stream<List<Map<String, dynamic>>> _employeesStream;

  // --- RECEITA CACHEADA (substitui streams ilimitados) ---
  double _weeklyRevenue = 0.0;
  sb.RealtimeChannel? _scheduleRealtimeChannel;
  final Set<String> _loadedMonths = {};

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    // por padrão, começar a lista a partir da semana atual
    _startFromSelectedDay = true;
    final now = DateTime.now();
    final startOfWeek = now.subtract(Duration(days: now.weekday - 1));
    _startFromDate = DateTime(startOfWeek.year, startOfWeek.month, startOfWeek.day);
    final endOfWeek = startOfWeek.add(const Duration(days: 6));
    _weekEndDate = DateTime(endOfWeek.year, endOfWeek.month, endOfWeek.day, 23, 59, 59);

    _loadShopConfig();
    _loadMonthEvents();
    _loadInitialAppointments();
    _fetchHolidays(); // Added by user
    _scrollController.addListener(() {
      // Start loading earlier for smoother experience (preload next page)
      if (_scrollController.position.pixels >=
          _scrollController.position.maxScrollExtent * 0.7) {
        _loadMoreAppointments();
      }
      // If near top, try loading older (past) appointments
      if (_scrollController.position.pixels <=
          _scrollController.position.minScrollExtent + 150) {
        _loadMorePastAppointments();
      }
    });

    // 1. Inicializar Stream de Employees compartilhado
    _employeesStream = sb.Supabase.instance.client
        .from('employees')
        .stream(primaryKey: ['id'])
        .eq('shop_id', widget.shopId);

    // Start periodic cache refresh to validate stale entries
    _cacheRefreshTimer = Timer.periodic(const Duration(minutes: 10), (_) {
      if (!mounted) return;
      _refreshStaleCacheEntries();
    });
    _loadRevenueStats();
    _startRealtimeSubscription();
  }

  Future<void> _loadShopConfig() async {
    final doc = await sb.Supabase.instance.client
        .from('shops')
        .select('config')
        .eq('id', widget.shopId)
        .maybeSingle();
    if (doc != null && mounted) {
      final data = doc;
      setState(() {
        _shopConfig = data['config'] as Map<String, dynamic>? ?? {};
      });
    }
  }

  // Carregar eventos do mês para marcar no calendário
  Future<void> _loadMonthEvents() async {
    final monthKey = '${_focusedDay.year}-${_focusedDay.month}';
    if (_loadedMonths.contains(monthKey)) return;
    // Load a wider window (previous, current and next month) to ensure calendar markers are present
    final startOfMonth = DateTime(_focusedDay.year, _focusedDay.month, 1)
        .subtract(const Duration(days: 35));
    final endOfMonth =
        DateTime(_focusedDay.year, _focusedDay.month + 1, 0, 23, 59, 59)
            .add(const Duration(days: 35));

    try {
      final snapshot = await sb.Supabase.instance.client
          .from('appointments')
          .select('id, scheduled_at, status')
          .eq('shop_id', widget.shopId)
          .gte('scheduled_at', startOfMonth.toUtc().toIso8601String())
          .lte('scheduled_at', endOfMonth.toUtc().toIso8601String());

      final Map<DateTime, List<String>> events = {};
      for (var data in snapshot) {
        final dateStr = data['scheduled_at'] as String?;
        if (dateStr == null) continue;
        
        final status = (data['status'] ?? '').toString().toLowerCase();
        if (status == 'cancelado') continue;

        final date = DateTime.parse(dateStr);
        final dateKey = DateTime(date.year, date.month, date.day);
        events[dateKey] = (events[dateKey] ?? [])..add(data['id'].toString());
      }

      if (mounted) {
        setState(() {
          // Limpamos apenas os eventos que estão dentro do período que acabamos de carregar
          _events.removeWhere((date, _) =>
              date.isAfter(startOfMonth.subtract(const Duration(days: 1))) &&
              date.isBefore(endOfMonth.add(const Duration(days: 1))));

          _events.addAll(events);
        });
        _loadedMonths.add(monthKey);
      }
    } catch (e) {
      debugPrint('Erro ao carregar eventos: $e');
    }
  }

  // Event loader para o TableCalendar
  List<String> _getEventsForDay(DateTime day) {
    final dateKey = DateTime(day.year, day.month, day.day);
    return _events[dateKey] ?? [];
  }

  // 🔄 CARGA INICIAL: últimos 20 agendamentos da data atual para trás
  Future<void> _loadInitialAppointments() async {
    if (_isLoading) return;
    setState(() {
      _isLoading = true;
      _appointments = [];
      _lastDocument = null;
      _firstDocument = null;
      _hasMore = true;
      _hasMorePast = true;
    });

    try {
      final endOfToday = DateTime(
          DateTime.now().year, DateTime.now().month, DateTime.now().day, 23, 59, 59);

      final snapshot = await sb.Supabase.instance.client
          .from('appointments')
          .select('id, shop_id, professional_id, client_id, scheduled_at, duration_min, status, total_value, total_price, labor_value, valor_com_desconto, total_payable, discount_amount, paid_amount, remaining_amount, payment_method, payment_status, coupon_applied, coupon_code, coupon_discount_percent, birthday_discount_applied, birthday_discount_percent, metadata, service_id, client_name, client_phone, client_email, service_name, professional_name')
          .eq('shop_id', widget.shopId)
          .lte('scheduled_at', endOfToday.toUtc().toIso8601String())
          .order('scheduled_at', ascending: false)
          .limit(_perPage);

      if (mounted) {
        setState(() {
          final ordered = snapshot.reversed.toList();
          for (var d in ordered) {
            _addToCache(d);
            _appointments.add(d);
          }
          if (ordered.isNotEmpty) {
            _firstDocument = ordered.first;
            _lastDocument = ordered.last;
          }
          if (snapshot.length < _perPage) {
            _hasMore = false;
            _hasMorePast = false;
          }
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Erro ao carregar agendamentos iniciais: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // 🗓 CARGA POR MÊS: carrega todos os agendamentos do mês exibido no calendário
  Future<void> _loadAppointmentsForMonth(DateTime month) async {
    if (_isLoading) return;
    setState(() {
      _isLoading = true;
      _appointments = [];
      _lastDocument = null;
      _firstDocument = null;
      _hasMore = true;
      _hasMorePast = true;
      _startFromSelectedDay = false;
      _showOnlySelectedDay = false;
    });

    final startOfMonth = DateTime(month.year, month.month, 1);
    final endOfMonth = DateTime(month.year, month.month + 1, 0, 23, 59, 59);

    try {
      final snapshot = await sb.Supabase.instance.client
          .from('appointments')
          .select('id, shop_id, professional_id, client_id, scheduled_at, duration_min, status, total_value, total_price, labor_value, valor_com_desconto, total_payable, discount_amount, paid_amount, remaining_amount, payment_method, payment_status, coupon_applied, coupon_code, coupon_discount_percent, birthday_discount_applied, birthday_discount_percent, metadata, service_id, client_name, client_phone, client_email, service_name, professional_name')
          .eq('shop_id', widget.shopId)
          .gte('scheduled_at', startOfMonth.toUtc().toIso8601String())
          .lte('scheduled_at', endOfMonth.toUtc().toIso8601String())
          .order('scheduled_at', ascending: true)
          .limit(_perPage);

      if (mounted) {
        setState(() {
          for (var d in snapshot) {
            _addToCache(d);
            _appointments.add(d);
          }
          if (snapshot.isNotEmpty) {
            _firstDocument = snapshot.first;
            _lastDocument = snapshot.last;
          }
          if (snapshot.length < _perPage) _hasMore = false;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Erro ao carregar agendamentos do mês: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // 🔄 CARREGAMENTO PRINCIPAL
  Future<void> _loadAppointments() async {
    if (_isLoading) return;
    setState(() {
      _isLoading = true;
      _appointments = [];
      _lastDocument = null;
      _firstDocument = null;
      _hasMore = true;
      _hasMorePast = true;
    });

    try {
      final client = sb.Supabase.instance.client;
      var query = client.from('appointments').select('id, shop_id, professional_id, client_id, scheduled_at, duration_min, status, total_value, total_price, labor_value, valor_com_desconto, total_payable, discount_amount, paid_amount, remaining_amount, payment_method, payment_status, coupon_applied, coupon_code, coupon_discount_percent, birthday_discount_applied, birthday_discount_percent, metadata, service_id, client_name, client_phone, client_email, service_name, professional_name').eq('shop_id', widget.shopId);

      // Simple implementation: load first page
      if (_startFromSelectedDay && _startFromDate != null && _weekEndDate != null) {
        query = query
          .gte('scheduled_at', _startFromDate!.toUtc().toIso8601String())
          .lte('scheduled_at', _weekEndDate!.toUtc().toIso8601String());
      } else if (_showOnlySelectedDay) {
        final start = DateTime(_selectedDay.year, _selectedDay.month, _selectedDay.day).subtract(const Duration(days: 7));
        final end = DateTime(_selectedDay.year, _selectedDay.month, _selectedDay.day).add(const Duration(days: 14, hours: 23, minutes: 59, seconds: 59));
        query = query
          .gte('scheduled_at', start.toUtc().toIso8601String())
          .lte('scheduled_at', end.toUtc().toIso8601String());
      } else {
        final start = DateTime(2020, 1, 1);
        query = query.gte('scheduled_at', start.toUtc().toIso8601String());
      }

      final snapshot = await query.order('scheduled_at', ascending: true).limit(_perPage);

      if (mounted) {
        setState(() {
          if (snapshot.isNotEmpty) {
            _firstDocument = snapshot.first;
            _lastDocument = snapshot.last;
            _appointments = [];
            for (var d in snapshot) {
              _addToCache(d);
              _appointments.add(d);
            }
          }
          if (snapshot.length < _perPage) _hasMore = false;
          if (snapshot.length < _perPage) _hasMorePast = false;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Erro Guardian: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadMoreAppointments() async {
    if (_isLoading || !_hasMore) return;
    setState(() => _isLoading = true);

    try {
      if (_lastDocument == null) {
        setState(() => _isLoading = false);
        return;
      }
      
      final lastDate = _lastDocument!['scheduled_at'] as String;
      
      final snapshot = await sb.Supabase.instance.client
          .from('appointments')
          .select('id, shop_id, professional_id, client_id, scheduled_at, duration_min, status, total_value, total_price, labor_value, valor_com_desconto, total_payable, discount_amount, paid_amount, remaining_amount, payment_method, payment_status, coupon_applied, coupon_code, coupon_discount_percent, birthday_discount_applied, birthday_discount_percent, metadata, service_id, client_name, client_phone, client_email, service_name, professional_name')
          .eq('shop_id', widget.shopId)
          .gt('scheduled_at', lastDate)
          .order('scheduled_at', ascending: true)
          .limit(_perPage);

      if (mounted) {
        setState(() {
          if (snapshot.isNotEmpty) {
            _lastDocument = snapshot.last;
            for (var d in snapshot) {
              final id = d['id'].toString();
              if (!_docCache.containsKey(id)) {
                _addToCache(d);
                _appointments.add(d);
              } else {
                _cacheAccess[id] = DateTime.now();
              }
            }
          }
          if (snapshot.length < _perPage) _hasMore = false;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // Carrega documentos antigos (passado) e os adiciona no início da lista
  Future<void> _loadMorePastAppointments() async {
    if (_isLoading || !_hasMorePast) return;
    setState(() => _isLoading = true);

    try {
      if (_firstDocument == null) {
        setState(() => _isLoading = false);
        return;
      }

      final firstDate = _firstDocument!['scheduled_at'] as String;

      final snapshot = await sb.Supabase.instance.client
          .from('appointments')
          .select('id, shop_id, professional_id, client_id, scheduled_at, duration_min, status, total_value, total_price, labor_value, valor_com_desconto, total_payable, discount_amount, paid_amount, remaining_amount, payment_method, payment_status, coupon_applied, coupon_code, coupon_discount_percent, birthday_discount_applied, birthday_discount_percent, metadata, service_id, client_name, client_phone, client_email, service_name, professional_name')
          .eq('shop_id', widget.shopId)
          .lt('scheduled_at', firstDate)
          .order('scheduled_at', ascending: false)
          .limit(_perPage);

      if (mounted) {
        setState(() {
          if (snapshot.isNotEmpty) {
            // inserir na frente (reverter para ordem asc)
            final newDocs = snapshot.reversed.toList();
            for (var d in newDocs) {
              final id = d['id'].toString();
              if (!_docCache.containsKey(id)) {
                _addToCache(d);
              }
            }
            // build merged list preserving order
            final merged = <Map<String, dynamic>>[];
            for (var d in newDocs) {
              final id = d['id'].toString();
              if (!_appointments.any((a) => a['id'].toString() == id)) merged.add(d);
            }
            _appointments = [...merged, ..._appointments];
            _firstDocument = _appointments.first;
          }
          if (snapshot.length < _perPage) _hasMorePast = false;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Erro ao carregar antigos: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  bool _shouldShowAppointment(Map<String, dynamic> data) {
    final status = (data['status'] ?? '').toString().toLowerCase();
    return status != 'cancelado';
  }

  // ðŸŽ¯ AÇÃO: IR PARA HOJE
  void _jumpToToday() {
    final now = DateTime.now();
    final startOfWeek = now.subtract(Duration(days: now.weekday - 1));
    final endOfWeek = startOfWeek.add(const Duration(days: 6));
    setState(() {
      _selectedDay = now;
      _focusedDay = now;
      _showOnlySelectedDay = false;
      _startFromSelectedDay = true;
      _startFromDate = DateTime(startOfWeek.year, startOfWeek.month, startOfWeek.day);
      _weekEndDate = DateTime(endOfWeek.year, endOfWeek.month, endOfWeek.day, 23, 59, 59);
    });
    _applyWeekFilterToCache();
    _fetchWeekFromServer(_startFromDate!, _weekEndDate!);
  }

  // 📍 Scroll automático até o cabeçalho do dia selecionado
  void _scrollToSelectedDay() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final dayKey = DateTime(_selectedDay.year, _selectedDay.month, _selectedDay.day);
      final key = _dayKeys[dayKey];
      if (key?.currentContext != null) {
        Scrollable.ensureVisible(
          key!.currentContext!,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeInOut,
          alignment: 0.0,
        );
      } else {
        // Fallback: scroll para o topo se o dia não tem header
        try {
          _scrollController.animateTo(0.0,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut);
        } catch (_) {}
      }
    });
  }

  // 💰 Recalcula faturamento semanal a partir dos agendamentos já carregados
  void _updateWeeklyRevenueFromAppointments() {
    double sum = 0;
    for (final d in _appointments) {
      if ((d['status'] ?? '').toString().toLowerCase() == 'cancelado') continue;
      sum += _safeParseValue(d);
    }
    if (mounted) {
      setState(() => _weeklyRevenue = sum);
    }
  }

  // âœ ï¸  EDITAR AGENDAMENTO
  // ignore: unused_element
  void _showEditDialog(Map<String, dynamic> data) {
    final TextEditingController nameController =
        TextEditingController(text: data['client_name'] ?? data['client_nome'] ?? '');
    String? selectedServiceId = data['service_id']?.toString();
    String selectedServiceName = data['service_name'] ?? data['servico_nome'] ?? '';
    String? selectedProfessionalId = data['professional_id']?.toString();
    String selectedProfessionalName = data['professional_name'] ?? data['profissional_nome'] ?? 'Selecione';
    double selectedServicePrice = _safeParseValue(data);

    final TextEditingController valueController = TextEditingController(
        text: selectedServicePrice.toStringAsFixed(2).replaceAll('.', ','));
    final TextEditingController paidController = TextEditingController(
        text: (data['valor_pago']?.toString() ?? '0').replaceAll('.', ','));

    final dateStr = data['scheduled_at'] as String;
    DateTime appointmentDate = DateTime.parse(dateStr);
    TimeOfDay appointmentTime = TimeOfDay.fromDateTime(appointmentDate);
    String selectedStatus =
        data['status']?.toString().toLowerCase() ?? 'pendente';

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return AlertDialog(
              title: Row(
                children: const [
                  Icon(Icons.edit, color: AppColors.primaryPurple),
                  SizedBox(width: 8),
                  Text("Editar Agendamento"),
                ],
              ),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Data
                    InkWell(
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: appointmentDate,
                          firstDate: DateTime(2010),
                          lastDate: DateTime(2035),
                        );
                        if (picked != null) {
                          setModalState(() {
                            appointmentDate = DateTime(
                              picked.year,
                              picked.month,
                              picked.day,
                              appointmentTime.hour,
                              appointmentTime.minute,
                            );
                          });
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 15),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade300),
                          borderRadius: BorderRadius.circular(10),
                          color: Colors.grey.shade50,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              DateFormat('dd/MM/yyyy').format(appointmentDate),
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            const Icon(Icons.calendar_today,
                                size: 18, color: AppColors.primaryPurple),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 15),

                    // Hora
                    InkWell(
                      onTap: () async {
                        final picked = await showTimePicker(
                          context: context,
                          initialTime: appointmentTime,
                        );
                        if (picked != null) {
                          setModalState(() {
                            appointmentTime = picked;
                            appointmentDate = DateTime(
                              appointmentDate.year,
                              appointmentDate.month,
                              appointmentDate.day,
                              picked.hour,
                              picked.minute,
                            );
                          });
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 15),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade300),
                          borderRadius: BorderRadius.circular(10),
                          color: Colors.grey.shade50,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              appointmentTime.format(context),
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            const Icon(Icons.access_time,
                                size: 18, color: AppColors.primaryPurple),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 15),

                    // Nome do Cliente
                    TextField(
                      controller: nameController,
                      decoration: InputDecoration(
                        labelText: 'Nome do Cliente',
                        filled: true,
                        fillColor: Colors.grey.shade50,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),

                    // Serviço (Dropdown com serviços cadastrados)
                    StreamBuilder<List<Map<String, dynamic>>>(
                      stream: sb.Supabase.instance.client
                          .from('services')
                          .stream(primaryKey: ['id'])
                          .eq('shop_id', widget.shopId)
                          .map((list) => list
                              .where((s) => (s['is_active'] ?? s['ativo'] ?? true) == true)
                              .toList()
                            ..sort((a, b) => (a['name'] ?? a['nome'] ?? '')
                                .toString()
                                .compareTo((b['name'] ?? b['nome'] ?? '').toString()))),
                      builder: (context, snapshot) {
                        if (!snapshot.hasData) {
                          return const CircularProgressIndicator();
                        }
                        final services = snapshot.data!;

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Serviço',
                                style: TextStyle(fontWeight: FontWeight.bold)),
                            const SizedBox(height: 8),
                            Container(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 12),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade50,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: DropdownButton<String>(
                                isExpanded: true,
                                underline: const SizedBox(),
                                value: selectedServiceId,
                                hint: Text(selectedServiceName.isNotEmpty
                                    ? selectedServiceName
                                    : 'Selecione um serviço'),
                                items: services.map((service) {
                                  final sData = service;
                                  return DropdownMenuItem<String>(
                                    value: service['id'].toString(),
                                    child: Text(
                                        '${sData['name'] ?? sData['nome']} - R\$ ${sData['price'] ?? sData['preco']}'),
                                  );
                                }).toList(),
                                onChanged: (value) {
                                  if (value != null) {
                                    final service = services
                                        .firstWhere((s) => s['id'].toString() == value);
                                    final sData = service;
                                    setModalState(() {
                                      selectedServiceId = value;
                                      selectedServiceName = sData['name'] ?? sData['nome'] ?? '';
                                      selectedServicePrice =
                                          (sData['price'] ?? sData['preco'] ?? 0).toDouble();
                                      valueController.text =
                                          selectedServicePrice
                                              .toStringAsFixed(2)
                                              .replaceAll('.', ',');
                                    });
                                  }
                                },
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 10),

                    // Profissional
                    StreamBuilder<List<Map<String, dynamic>>>(
                      stream: _employeesStream,
                      builder: (context, snapshot) {
                        if (!snapshot.hasData) return const SizedBox();
                        final pros = snapshot.data!;
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Profissional',
                                style: TextStyle(fontWeight: FontWeight.bold)),
                            const SizedBox(height: 8),
                            Container(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 12),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade50,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: DropdownButton<String>(
                                isExpanded: true,
                                underline: const SizedBox(),
                                value: pros.any(
                                        (p) => p['id'].toString() == selectedProfessionalId)
                                    ? selectedProfessionalId
                                    : null,
                                hint: Text(selectedProfessionalName),
                                items: pros.where((p) {
                                  if (selectedServiceId == null) return true;
                                  final List<dynamic> habilitados =
                                      p['services_ids'] ?? [];
                                  return habilitados
                                      .map((id) => id.toString())
                                      .contains(selectedServiceId.toString());
                                }).map((pro) {
                                  final pData = pro;
                                  return DropdownMenuItem<String>(
                                    value: pro['id'].toString(),
                                    child: Text(pData['name'] ?? 'Sem nome'),
                                  );
                                }).toList(),
                                onChanged: (value) {
                                  if (value != null) {
                                    final pro =
                                        pros.firstWhere((p) => p['id'].toString() == value);
                                    final pData = pro;
                                    setModalState(() {
                                      selectedProfessionalId = value;
                                      selectedProfessionalName =
                                          pData['name'] ?? pData['nome'] ?? '';
                                    });
                                  }
                                },
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 15),

                    // Horários Disponíveis (Sugestão Visual)
                    const Text(
                      'Sugestões de Horários Livres:',
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    const SizedBox(height: 8),
                    if (selectedProfessionalId != null)
                      FutureBuilder<List<Map<String, int>>>(
                        future: AvailabilityUtils.getBusyIntervals(
                          selectedProfessionalId!,
                          appointmentDate,
                          excludeDocId: data['id']?.toString(),
                        ),
                        builder: (context, busySnapshot) {
                          if (!busySnapshot.hasData) return const SizedBox();

                          // Buscando dados do profissional selecionado para pegar horários
                          return FutureBuilder<Map<String, dynamic>?>(
                              future: sb.Supabase.instance.client
                                  .from('employees')
                                  .select()
                                  .eq('id', selectedProfessionalId!)
                                  .maybeSingle(),
                              builder: (context, empSnapshot) {
                                if (!empSnapshot.hasData)
                                  return const SizedBox();
                                final empData = empSnapshot.data ?? {};

                                int duration = int.tryParse(
                                        data['duration_min']?.toString() ??
                                            '30') ??
                                    30;

                                final slots =
                                    AvailabilityUtils.generateSmartSlots(
                                  startStr:
                                      empData['work_start'] ?? "08:00",
                                  endStr: empData['work_end'] ?? "18:00",
                                  interval:
                                      _shopConfig['intervalo_agenda_min'] ?? 30,
                                  serviceDuration: duration,
                                  busyIntervals: busySnapshot.data!,
                                  preventGaps:
                                      _shopConfig['evitar_buracos_agenda'] ??
                                          false,
                                  minAdvanceHours:
                                      0, // Loja pode agendar para qualquer hora (passado/futuro)
                                  selectedDate: appointmentDate,
                                );

                                if (slots.isEmpty) {
                                  return const Text(
                                      "Sem horários livres sugeridos.",
                                      style: TextStyle(
                                          fontSize: 12, color: Colors.grey));
                                }

                                return Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: slots.take(12).map((slotStr) {
                                    final parts = slotStr.split(':');
                                    final slotTime = TimeOfDay(
                                        hour: int.parse(parts[0]),
                                        minute: int.parse(parts[1]));
                                    final isCurrent =
                                        appointmentTime.hour == slotTime.hour &&
                                            appointmentTime.minute ==
                                                slotTime.minute;

                                    return ChoiceChip(
                                      label: Text(slotStr,
                                          style: const TextStyle(fontSize: 11)),
                                      selected: isCurrent,
                                      onSelected: (selected) {
                                        if (selected) {
                                          setModalState(() {
                                            appointmentTime = slotTime;
                                            appointmentDate = DateTime(
                                              appointmentDate.year,
                                              appointmentDate.month,
                                              appointmentDate.day,
                                              slotTime.hour,
                                              slotTime.minute,
                                            );
                                          });
                                        }
                                      },
                                      selectedColor: AppColors.primaryPurple
                                          .withValues(alpha: 0.2),
                                      backgroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(8)),
                                    );
                                  }).toList(),
                                );
                              },
                            );
                        },
                      ),
                    const SizedBox(height: 10),

                    // Valor Total
                    TextField(
                      controller: valueController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: 'Valor Total (R\$)',
                        prefixText: "R\$ ",
                        filled: true,
                        fillColor: Colors.grey.shade50,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),

                    // Valor Pago
                    TextField(
                      controller: paidController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: 'Valor Pago (R\$)',
                        prefixText: "R\$ ",
                        filled: true,
                        fillColor: Colors.grey.shade50,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide.none,
                        ),
                        helperText: 'Valor já pago pelo cliente',
                      ),
                    ),
                    const SizedBox(height: 15),

                    // Status
                    const Text(
                      'Status:',
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: [
                        ChoiceChip(
                          label: const Text('Pendente'),
                          selected: selectedStatus == 'pendente',
                          onSelected: (selected) {
                            if (selected) {
                              setModalState(() => selectedStatus = 'pendente');
                            }
                          },
                          selectedColor: Colors.orange.withValues(alpha: 0.3),
                        ),
                        ChoiceChip(
                          label: const Text('Concluído'),
                          selected: selectedStatus == 'concluido',
                          onSelected: (selected) {
                            if (selected) {
                              setModalState(() => selectedStatus = 'concluido');
                            }
                          },
                          selectedColor: Colors.green.withValues(alpha: 0.3),
                        ),
                        ChoiceChip(
                          label: const Text('Cancelado'),
                          selected: selectedStatus == 'cancelado',
                          onSelected: (selected) {
                            if (selected) {
                              setModalState(() => selectedStatus = 'cancelado');
                            }
                          },
                          selectedColor: Colors.red.withValues(alpha: 0.3),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("Cancelar",
                      style: TextStyle(color: Colors.grey)),
                ),
                ElevatedButton(
                  onPressed: () async {
                    if (nameController.text.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text('Nome do cliente é obrigatório')),
                      );
                      return;
                    }

                    // Verificação Completa de Regras de Negócio
                    if (selectedProfessionalId != null) {
                      final conflicts = await _verifyBusinessRules(
                        professionalId: selectedProfessionalId!,
                        date: appointmentDate,
                        time: appointmentTime,
                        durationMin: int.tryParse(
                                data['duracao_min']?.toString() ?? '30') ??
                            30,
                        serviceId: selectedServiceId,
                        excludeDocId: data['id']?.toString(),
                      );

                      if (conflicts.isNotEmpty) {
                        bool confirm = await _showConflictDialog(
                          context: context,
                          professionalName: selectedProfessionalName,
                          timeStr: appointmentTime.format(context),
                          messages: conflicts,
                        );
                        if (!confirm) return;
                      }
                    }

                    double valorTotal = double.tryParse(
                            valueController.text.replaceAll(',', '.')) ??
                        0.0;

                    try {
                      await sb.Supabase.instance.client
                          .from('appointments')
                          .update({
                        'client_name': nameController.text.trim(),
                        'service_name': selectedServiceName.isEmpty
                            ? 'Serviço'
                            : selectedServiceName,
                        if (selectedServiceId != null)
                          'service_id': selectedServiceId,
                        if (selectedProfessionalId != null) ...{
                          'professional_id': selectedProfessionalId,
                          'professional_name': selectedProfessionalName,
                        },
                        'labor_value': valorTotal,
                        'total_value': valorTotal,
                        // paid_amount & remaining_amount não existem no BD
                        'status': selectedStatus,
                        'scheduled_at': appointmentDate.toIso8601String(),
                      }).eq('id', data['id']);

                      if (mounted) {
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content:
                                Text('Agendamento atualizado com sucesso!'),
                            backgroundColor: Colors.green,
                          ),
                        );
                        _loadAppointments();
                      }
                    } catch (e) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Erro ao atualizar: $e')),
                        );
                      }
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryPurple,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                  child: const Text("Salvar",
                      style: TextStyle(color: Colors.white)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showQuickEntryModal({DateTime? initialDate, Map<String, dynamic>? appointment}) async {
    if (_isOpeningQuickEntry) return;
    _isOpeningQuickEntry = true;

    try {
      final Map<String, dynamic>? editData = appointment;

      // Controladores básicos alinhados com o esquema do banco de dados em inglês
      final String initialName = (editData?['client_name'] ?? '').toString();
      final TextEditingController nameController = TextEditingController(text: (initialName == 'null' || initialName == 'Null') ? '' : initialName);
      
      final String initialPhone = (editData?['client_phone'] ?? '').toString();
      final TextEditingController phoneController = TextEditingController(text: (initialPhone == 'null' || initialPhone == 'Null') ? '' : initialPhone);
      
      final String initialService = (editData?['service_name'] ?? '').toString();
      final TextEditingController serviceController = TextEditingController(text: (initialService == 'null' || initialService == 'Null') ? '' : initialService);
      final TextEditingController valueController = TextEditingController();
      
      // Estado do Modal
      String? selectedClientId = editData?['client_id'] ?? editData?['clientId'];
      String? serviceId = editData?['service_id'] ?? editData?['servicoId'];
      int durationMin = editData?['duration_min'] ?? editData?['duracao_min'] ?? 30;
      String? selectedProfessionalId = editData?['professional_id'] ?? editData?['profissionalId'];
      String selectedProfessionalName = editData?['professional_name'] ?? editData?['profissional_nome'] ?? 'Selecione Profissional';
      DateTime manualDate = initialDate ?? _selectedDay;
      TimeOfDay manualTime = TimeOfDay.now();

      String rawValue = (editData?['payment_method'] ?? '').toString().trim();
      String paymentMethodFromDb = rawValue.toLowerCase();
      String selectedPaymentMethod = rawValue.isNotEmpty ? rawValue : 'Pessoalmente';
      if (paymentMethodFromDb == 'pix') selectedPaymentMethod = 'Pix';
      if (paymentMethodFromDb == 'cartão' || paymentMethodFromDb == 'cartao' || paymentMethodFromDb == 'card') selectedPaymentMethod = 'Cartão';
      if (paymentMethodFromDb == 'pessoalmente' || paymentMethodFromDb == 'no local' || paymentMethodFromDb == 'local') selectedPaymentMethod = 'Pessoalmente';

      bool isPaid = (double.tryParse(editData?['paid_amount']?.toString() ?? '0') ?? 0) > 0.01;
      
      if (editData != null) {
        final dateStr = editData['scheduled_at'] as String?;
        if (dateStr != null) {
          manualDate = DateTime.parse(dateStr);
          manualTime = TimeOfDay.fromDateTime(manualDate);
        }
        double val = _safeParseValue(appointment!);
        valueController.text = val > 0 ? val.toString().replaceAll('.', ',') : '';
        
        // Se já houver valor pago maior que zero, assume que está pago
        isPaid = (double.tryParse(editData['paid_amount']?.toString() ?? '0') ?? 0) > 0.01;
      }

      // --- REVISÃƒO / INTELIGÃŠNCIA INICIAL ---
      Map<String, dynamic>? suggestedService;
      Map<String, dynamic>? suggestedProfessional;
      bool isServiceConfirmed = false;
      bool isProfessionalConfirmed = false;
      bool isIntelligentLoading = (editData == null); // Só carregar inteligência para novos agendamentos

      if (!mounted) {
        _isOpeningQuickEntry = false;
        return;
      }

      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (context) {
          return StatefulBuilder(
            builder: (context, setModalState) {
              // Trigger inicial da inteligência se necessário
              if (isIntelligentLoading) {
                isIntelligentLoading = false; // Só rodar uma vez
                Future.microtask(() async {
                  try {
                    // 1. Match de Serviço
                    if (serviceId == null && serviceController.text.isNotEmpty) {
                      suggestedService = await TransactionAutocompleteService.findBestMatchingService(
                        shopId: widget.shopId,
                        rawName: serviceController.text,
                      );
                    }

                    // 2. Sugestão de Profissional
                    if (selectedProfessionalId == null) {
                      final candidates = await TransactionAutocompleteService.getCandidates(
                        shopId: widget.shopId,
                        serviceId: serviceId ?? suggestedService?['id']?.toString(),
                      );

                      List<Map<String, dynamic>> availableCands = [];
                      for (var cand in candidates) {
                        bool ok = await TransactionAutocompleteService.isProfessionalAvailable(
                          employeeId: cand['id'].toString(),
                          targetDate: manualDate,
                          durationMin: durationMin,
                          excludeDocId: appointment?['id']?.toString(),
                        );
                        if (ok) availableCands.add(cand);
                      }

                      if (availableCands.isNotEmpty) {
                        final ranked = await TransactionAutocompleteService.rankCandidatesByWorkload(
                          shopId: widget.shopId,
                          candidates: availableCands,
                          targetMonth: manualDate,
                        );
                        suggestedProfessional = ranked.first;
                        
                        // Aplicar sugestão automaticamente se o usuário não escolheu nada ainda
                        if (selectedProfessionalId == null) {
                           selectedProfessionalId = suggestedProfessional?['id']?.toString();
                           selectedProfessionalName = suggestedProfessional?['name'] ?? suggestedProfessional?['nome'] ?? 'Profissional';
                        }
                      }
                    }
                    if (context.mounted) setModalState(() {});
                  } catch (e) {
                    debugPrint("Erro na inteligência: $e");
                  }
                });
              }

            return Padding(
              padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom + MediaQuery.of(context).padding.bottom + 10),
              child: Container(
                height: MediaQuery.of(context).size.height * 0.75,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.only(topLeft: Radius.circular(20), topRight: Radius.circular(20)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Header
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        border: Border(bottom: BorderSide(color: Colors.grey.shade100)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(appointment == null ? "Lançamento Rápido" : "Editar Agendamento",
                              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.primaryPurple)),
                          IconButton(
                            icon: const Icon(Icons.close, size: 22),
                            onPressed: () => Navigator.pop(context),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                        ],
                      ),
                    ),
                    // Form
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Data e Horário
                            const Text('Data e Horário',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.grey)),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Expanded(
                                  child: InkWell(
                                    onTap: () async {
                                      final picked = await showDatePicker(
                                        context: context,
                                        initialDate: manualDate,
                                        firstDate: DateTime(2010),
                                        lastDate: DateTime(2035),
                                      );
                                      if (picked != null) {
                                        setModalState(() => manualDate = picked);
                                      }
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                      decoration: BoxDecoration(
                                        border: Border.all(color: Colors.grey.shade200),
                                        borderRadius: BorderRadius.circular(8),
                                        color: Colors.grey.shade50,
                                      ),
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(
                                            DateFormat('dd/MM/yyyy').format(manualDate),
                                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                                          ),
                                          const Icon(Icons.calendar_today, size: 16, color: AppColors.primaryPurple),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: InkWell(
                                    onTap: () async {
                                      final picked = await showTimePicker(context: context, initialTime: manualTime);
                                      if (picked != null) {
                                        setModalState(() => manualTime = picked);
                                      }
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                      decoration: BoxDecoration(
                                        border: Border.all(color: Colors.grey.shade200),
                                        borderRadius: BorderRadius.circular(8),
                                        color: Colors.grey.shade50,
                                      ),
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(
                                            manualTime.format(context),
                                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                                          ),
                                          const Icon(Icons.access_time, size: 16, color: AppColors.primaryPurple),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            // Cliente
                            const Text('Cliente',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.grey)),
                            const SizedBox(height: 4),
                            LayoutBuilder(builder: (context, constraints) {
                              TextEditingController? capturedNameCtrl;
                              return Autocomplete<Map<String, dynamic>>(
                                initialValue: TextEditingValue(text: nameController.text),
                                optionsBuilder: (TextEditingValue textEditingValue) async {
                                  // Sync nameController so save reads the correct text
                                  nameController.text = textEditingValue.text;
                                  return await TransactionAutocompleteService.findRecentClients(
                                    shopId: widget.shopId,
                                    search: textEditingValue.text,
                                  );
                                },
                                displayStringForOption: (option) => option['name'] ?? '',
                                onSelected: (option) {
                                  setModalState(() {
                                    nameController.text = option['name'] ?? '';
                                    phoneController.text = option['phone'] ?? '';
                                    selectedClientId = option['id'];
                                    if (capturedNameCtrl != null) {
                                      capturedNameCtrl!.text = option['name'] ?? '';
                                    }
                                  });
                                },
                                fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
                                  capturedNameCtrl = controller;
                                  // Sync the Autocomplete controller on first build
                                  if (controller.text.isEmpty && nameController.text.isNotEmpty) {
                                    controller.text = nameController.text;
                                  }
                                  // Make nameController always reflect what user typed
                                  controller.addListener(() {
                                    if (nameController.text != controller.text) {
                                      nameController.text = controller.text;
                                    }
                                  });
                                  return SizedBox(
                                    height: 40,
                                    child: TextField(
                                      controller: controller,
                                      focusNode: focusNode,
                                      textCapitalization: TextCapitalization.words,
                                      style: const TextStyle(fontSize: 14),
                                      decoration: InputDecoration(
                                        hintText: 'Nome do cliente',
                                        filled: true,
                                        fillColor: Colors.grey.shade50,
                                        prefixIcon: const Icon(Icons.person_outline, size: 18),
                                        contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(8),
                                          borderSide: BorderSide(color: Colors.grey.shade200),
                                        ),
                                        enabledBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(8),
                                          borderSide: BorderSide(color: Colors.grey.shade200),
                                        ),
                                      ),
                                    ),
                                  );
                                },
                                optionsViewBuilder: (context, onSelected, options) {
                                  return Align(
                                    alignment: Alignment.topLeft,
                                    child: Material(
                                      elevation: 4,
                                      borderRadius: BorderRadius.circular(8),
                                      child: Container(
                                        width: constraints.maxWidth,
                                        constraints: const BoxConstraints(maxHeight: 200),
                                        child: ListView.builder(
                                          padding: EdgeInsets.zero,
                                          shrinkWrap: true,
                                          itemCount: options.length,
                                          itemBuilder: (context, index) {
                                            final option = options.elementAt(index);
                                            final hasId = option['id'] != null;
                                            return ListTile(
                                              dense: true,
                                              leading: Icon(
                                                hasId ? Icons.verified_user : Icons.person_outline,
                                                size: 20,
                                                color: hasId ? Colors.blue : Colors.grey,
                                              ),
                                              title: Text(option['name'] ?? '', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                                              subtitle: Text(option['phone'] ?? 'Sem telefone', style: const TextStyle(fontSize: 11)),
                                              onTap: () => onSelected(option),
                                            );
                                          },
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              );
                            }),
                            const SizedBox(height: 10),
                            // Telefone
                            const Text('Telefone / WhatsApp',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.grey)),
                            const SizedBox(height: 4),
                            SizedBox(
                              height: 40,
                              child: TextField(
                                controller: phoneController,
                                keyboardType: TextInputType.phone,
                                style: const TextStyle(fontSize: 14),
                                decoration: InputDecoration(
                                  hintText: 'Telefone do cliente',
                                  filled: true,
                                  fillColor: Colors.grey.shade50,
                                  prefixIcon: const Icon(Icons.phone_outlined, size: 18),
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide: BorderSide(color: Colors.grey.shade200),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide: BorderSide(color: Colors.grey.shade200),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            // Profissional
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('Profissional',
                                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.grey)),
                                if (suggestedProfessional != null && !isProfessionalConfirmed && selectedProfessionalId == null)
                                  GestureDetector(
                                    onTap: () {
                                      final pData = suggestedProfessional!;
                                      setModalState(() {
                                        selectedProfessionalId = pData['id'].toString();
                                        selectedProfessionalName = pData['name'] ?? '';
                                        isProfessionalConfirmed = true;
                                      });
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Colors.blue.shade50,
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(color: Colors.blue.shade100),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(Icons.auto_awesome, size: 10, color: Colors.blue),
                                          const SizedBox(width: 4),
                                          Text("Sugerir: ${suggestedProfessional!['name']}", 
                                            style: const TextStyle(fontSize: 10, color: Colors.blue, fontWeight: FontWeight.bold)),
                                        ],
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 4),
                              StreamBuilder<List<Map<String, dynamic>>>(
                               stream: _employeesStream,
                               builder: (context, snapshot) {
                                 if (!snapshot.hasData) return const SizedBox(height: 40);
                                 final pros = snapshot.data!;
                                 
                                 return LayoutBuilder(builder: (context, constraints) {
                                   return Autocomplete<Map<String, dynamic>>(
                                     initialValue: TextEditingValue(
                                         text: selectedProfessionalId != null ? selectedProfessionalName : ''),
                                     optionsBuilder: (TextEditingValue textEditingValue) {
                                       // Filtra por habilitação (se houver serviço selecionado)
                                       final filteredByService = pros.where((p) {
                                         if (serviceId == null) return true;
                                         final List<dynamic> habilitados = p['services_ids'] ?? [];
                                         
                                         return habilitados.map((id) => id.toString()).contains(serviceId.toString());
                                       }).toList();

                                       if (textEditingValue.text.isEmpty) return filteredByService;
                                       return filteredByService.where((p) => (p['name'] ?? '')
                                           .toString()
                                           .toLowerCase()
                                           .contains(textEditingValue.text.toLowerCase()));
                                     },
                                     displayStringForOption: (option) => option['name'] ?? '',
                                     onSelected: (option) {
                                       setModalState(() {
                                         selectedProfessionalId = option['id'].toString();
                                         selectedProfessionalName = option['name'] ?? '';
                                         isProfessionalConfirmed = true;
                                       });
                                     },
                                     fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
                                       if (selectedProfessionalId != null && 
                                           controller.text != selectedProfessionalName && 
                                           !focusNode.hasFocus) {
                                         controller.text = selectedProfessionalName;
                                       }
                                       return SizedBox(
                                         height: 40,
                                         child: TextField(
                                           controller: controller,
                                           focusNode: focusNode,
                                           style: const TextStyle(fontSize: 14),
                                           decoration: InputDecoration(
                                             hintText: 'Buscar profissional...',
                                             filled: true,
                                             fillColor: Colors.grey.shade50,
                                             contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                                             border: OutlineInputBorder(
                                               borderRadius: BorderRadius.circular(8),
                                               borderSide: BorderSide(color: Colors.grey.shade200),
                                             ),
                                             enabledBorder: OutlineInputBorder(
                                               borderRadius: BorderRadius.circular(8),
                                               borderSide: BorderSide(color: Colors.grey.shade200),
                                             ),
                                             suffixIcon: controller.text.isNotEmpty
                                                 ? IconButton(
                                                     icon: const Icon(Icons.clear, size: 16),
                                                     onPressed: () {
                                                       controller.clear();
                                                       setModalState(() {
                                                         selectedProfessionalId = null;
                                                         selectedProfessionalName = 'Selecione...';
                                                       });
                                                     },
                                                   )
                                                 : const Icon(Icons.arrow_drop_down),
                                           ),
                                           onChanged: (v) {
                                             if (v.isEmpty) {
                                                setModalState(() {
                                                  selectedProfessionalId = null;
                                                  selectedProfessionalName = 'Selecione...';
                                                });
                                             }
                                           },
                                         ),
                                       );
                                     },
                                     optionsViewBuilder: (context, onSelected, options) {
                                       return Align(
                                         alignment: Alignment.topLeft,
                                         child: Material(
                                           elevation: 4,
                                           borderRadius: BorderRadius.circular(8),
                                           child: Container(
                                             width: constraints.maxWidth,
                                             constraints: const BoxConstraints(maxHeight: 200),
                                             child: ListView.builder(
                                               padding: EdgeInsets.zero,
                                               shrinkWrap: true,
                                               itemCount: options.length,
                                               itemBuilder: (BuildContext context, int index) {
                                                 final option = options.elementAt(index);
                                                 return ListTile(
                                                   dense: true,
                                                   title: Text(option['name'] ?? '', style: const TextStyle(fontSize: 13)),
                                                   onTap: () => onSelected(option),
                                                 );
                                               },
                                             ),
                                           ),
                                         ),
                                       );
                                     },
                                   );
                                 });
                               },
                             ),
                            const SizedBox(height: 10),
                            // Serviço Autocomplete
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('Serviço',
                                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.grey)),
                                if (suggestedService != null && !isServiceConfirmed && serviceId == null)
                                  GestureDetector(
                                    onTap: () {
                                      final sData = suggestedService!;
                                      setModalState(() {
                                        serviceId = sData['id'].toString();
                                        serviceController.text = sData['name'] ?? '';
                                        valueController.text = (sData['price'] ?? 0).toString().replaceAll('.', ',');
                                        durationMin = (sData['duration_min'] ?? 30);
                                        isServiceConfirmed = true;
                                      });
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Colors.green.shade50,
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(color: Colors.green.shade100),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(Icons.auto_awesome, size: 10, color: Colors.green),
                                          const SizedBox(width: 4),
                                          Text("Completar: ${suggestedService!['name']}", 
                                            style: const TextStyle(fontSize: 10, color: Colors.green, fontWeight: FontWeight.bold)),
                                        ],
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 4),
                             StreamBuilder<List<Map<String, dynamic>>>(
                               stream: sb.Supabase.instance.client
                                   .from('services')
                                   .stream(primaryKey: ['id'])
                                   .eq('shop_id', widget.shopId),
                               builder: (context, snapshot) {
                                 if (!snapshot.hasData) return const SizedBox(height: 40);
                                 final allServices = snapshot.data!
                                     .where((s) => s['is_active'] == null || s['is_active'] == true)
                                     .toList();

                                return LayoutBuilder(builder: (context, constraints) {
                                  return Autocomplete<Map<String, dynamic>>(
                                    initialValue: TextEditingValue(text: serviceController.text),
                                    optionsBuilder: (TextEditingValue textEditingValue) {
                                      if (textEditingValue.text.isEmpty) return allServices;
                                      return allServices.where((s) => s['name']
                                          .toString()
                                          .toLowerCase()
                                          .contains(textEditingValue.text.toLowerCase()));
                                    },
                                    displayStringForOption: (option) => option['name'] ?? '',
                                    onSelected: (option) {
                                      setModalState(() {
                                        serviceId = option['id'].toString();
                                        serviceController.text = option['name'] ?? '';
                                        valueController.text = (option['price'] ?? 0).toString().replaceAll('.', ',');
                                        durationMin = (option['duration_min'] ?? 30);
                                      });
                                    },
                                    fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
                                      // Sincronizar o controlador interno do Autocomplete com o valor inicial DE FORMA AGRESSIVA
                                      if (controller.text.isEmpty && serviceController.text.isNotEmpty) {
                                        Future.microtask(() => controller.text = serviceController.text);
                                      }
                                      return SizedBox(
                                        height: 40,
                                        child: TextField(
                                          controller: controller,
                                          focusNode: focusNode,
                                          style: const TextStyle(fontSize: 14),
                                          decoration: InputDecoration(
                                            hintText: 'Buscar serviço...',
                                            filled: true,
                                            fillColor: Colors.grey.shade50,
                                            contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                                            border: OutlineInputBorder(
                                              borderRadius: BorderRadius.circular(8),
                                              borderSide: BorderSide(color: Colors.grey.shade200),
                                            ),
                                            enabledBorder: OutlineInputBorder(
                                              borderRadius: BorderRadius.circular(8),
                                              borderSide: BorderSide(color: Colors.grey.shade200),
                                            ),
                                            suffixIcon: controller.text.isNotEmpty
                                                ? IconButton(
                                                    icon: const Icon(Icons.clear, size: 16),
                                                    onPressed: () {
                                                      controller.clear();
                                                      setModalState(() {
                                                        serviceId = null;
                                                        serviceController.clear();
                                                      });
                                                    },
                                                  )
                                                : null,
                                          ),
                                          onChanged: (v) {
                                            setModalState(() {
                                              serviceController.text = v;
                                              serviceId = null;
                                              isServiceConfirmed = false;
                                              suggestedService = null;
                                            });
                                            if (v.length >= 2) {
                                              TransactionAutocompleteService.findBestMatchingService(
                                                rawName: v,
                                                shopId: widget.shopId,
                                              ).then((best) {
                                                if (best != null) {
                                                  setModalState(() {
                                                    suggestedService = best;
                                                  });
                                                }
                                              });
                                            }
                                          },
                                        ),
                                      );
                                    },
                                    optionsViewBuilder: (context, onSelected, options) {
                                      return Align(
                                        alignment: Alignment.topLeft,
                                        child: Material(
                                          elevation: 4,
                                          borderRadius: BorderRadius.circular(8),
                                          child: Container(
                                            width: constraints.maxWidth,
                                            constraints: const BoxConstraints(maxHeight: 200),
                                            child: ListView.builder(
                                              padding: EdgeInsets.zero,
                                              shrinkWrap: true,
                                              itemCount: options.length,
                                              itemBuilder: (BuildContext context, int index) {
                                                final option = options.elementAt(index);
                                                return ListTile(
                                                  dense: true,
                                                  title: Text(option['name'] ?? option['nome'] ?? '', style: const TextStyle(fontSize: 13)),
                                                  subtitle: Text('R\$ ${option['price'] ?? option['preco']}', style: const TextStyle(fontSize: 11)),
                                                  onTap: () => onSelected(option),
                                                );
                                              },
                                            ),
                                          ),
                                        ),
                                      );
                                    },
                                  );
                                });
                              },
                            ),
                            const SizedBox(height: 10),
                            // Valor
                            const Text('Valor (R\$)',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.grey)),
                            const SizedBox(height: 4),
                            SizedBox(
                              height: 40,
                              child: TextField(
                                controller: valueController,
                                keyboardType: TextInputType.number,
                                style: const TextStyle(fontSize: 14),
                                decoration: InputDecoration(
                                  prefixText: 'R\$ ',
                                  filled: true,
                                  fillColor: Colors.grey.shade50,
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide: BorderSide(color: Colors.grey.shade200),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide: BorderSide(color: Colors.grey.shade200),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            // Método de Pagamento e Status
                            const Text('Forma de Pagamento',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.grey)),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                _paymentMethodChip(
                                  label: "Pix",
                                  icon: Icons.pix,
                                  isSelected: selectedPaymentMethod == 'Pix',
                                  onTap: () => setModalState(() => selectedPaymentMethod = 'Pix'),
                                ),
                                const SizedBox(width: 8),
                                _paymentMethodChip(
                                  label: "Cartão",
                                  icon: Icons.credit_card,
                                  isSelected: selectedPaymentMethod == 'Cartão',
                                  onTap: () => setModalState(() => selectedPaymentMethod = 'Cartão'),
                                ),
                                const SizedBox(width: 8),
                                _paymentMethodChip(
                                  label: "Pessoalmente",
                                  icon: Icons.person_pin_circle_outlined,
                                  isSelected: selectedPaymentMethod == 'Pessoalmente',
                                  onTap: () => setModalState(() => selectedPaymentMethod = 'Pessoalmente'),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: InkWell(
                                    onTap: () => setModalState(() => isPaid = false),
                                    borderRadius: BorderRadius.circular(8),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(vertical: 10),
                                      decoration: BoxDecoration(
                                        color: !isPaid ? Colors.orange.withValues(alpha: 0.1) : Colors.grey.shade50,
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(color: !isPaid ? Colors.orange.withValues(alpha: 0.3) : Colors.grey.shade200),
                                      ),
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Icon(Icons.hourglass_empty, size: 16, color: !isPaid ? Colors.orange : Colors.grey),
                                          const SizedBox(width: 6),
                                          const Text("Pendente", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: InkWell(
                                    onTap: () => setModalState(() => isPaid = true),
                                    borderRadius: BorderRadius.circular(8),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(vertical: 10),
                                      decoration: BoxDecoration(
                                        color: isPaid ? Colors.green.withValues(alpha: 0.1) : Colors.grey.shade50,
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(color: isPaid ? Colors.green.withValues(alpha: 0.3) : Colors.grey.shade200),
                                      ),
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Icon(Icons.check_circle, size: 16, color: isPaid ? Colors.green : Colors.grey),
                                          const SizedBox(width: 6),
                                          const Text("Pago", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 40),
                            // Horários
                            if (selectedProfessionalId != null)
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Text("Sugestões:",
                                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.grey)),
                                  const SizedBox(height: 6),
                                  FutureBuilder<List<Map<String, int>>>(
                                    future: AvailabilityUtils.getBusyIntervals(selectedProfessionalId!, manualDate, excludeDocId: appointment?['id']),
                                    builder: (context, busySnapshot) {
                                      if (!busySnapshot.hasData) return const SizedBox(height: 38);
                                      return FutureBuilder<Map<String, dynamic>?>(
                                        future: sb.Supabase.instance.client.from('employees').select().eq('id', selectedProfessionalId!).maybeSingle(),
                                        builder: (context, empSnapshot) {
                                          if (!empSnapshot.hasData) return const SizedBox();
                                          final empData = empSnapshot.data ?? {};
                                          final slots = AvailabilityUtils.generateSmartSlots(
                                            startStr: empData['work_start'] ?? "08:00",
                                            endStr: empData['work_end'] ?? "18:00",
                                            interval: _shopConfig['intervalo_agenda_min'] ?? 30,
                                            serviceDuration: durationMin,
                                            busyIntervals: busySnapshot.data!,
                                            preventGaps: _shopConfig['evitar_buracos_agenda'] ?? false,
                                            minAdvanceHours: 0,
                                            selectedDate: manualDate,
                                          );
                                          if (slots.isEmpty) return const Text("Sem horários.", style: TextStyle(fontSize: 11));
                                          return SizedBox(
                                            height: 36,
                                            child: ListView.separated(
                                              scrollDirection: Axis.horizontal,
                                              itemCount: slots.length,
                                              separatorBuilder: (_, __) => const SizedBox(width: 8),
                                              itemBuilder: (context, index) {
                                                final slotStr = slots[index];
                                                final parts = slotStr.split(':');
                                                final slotTime = TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
                                                final isCurrent = manualTime.hour == slotTime.hour && manualTime.minute == slotTime.minute;
                                                return ActionChip(
                                                  label: Text(slotStr, style: TextStyle(fontSize: 12, color: isCurrent ? Colors.white : Colors.black87)),
                                                  onPressed: () => setModalState(() => manualTime = slotTime),
                                                  backgroundColor: isCurrent ? AppColors.primaryPurple : Colors.grey.shade100,
                                                  padding: EdgeInsets.zero,
                                                  side: BorderSide.none,
                                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                                );
                                              },
                                            ),
                                          );
                                        },
                                      );
                                    },
                                  ),
                                ],
                              )
                            else
                              const Text("Selecione um profissional para ver sugestões.",
                                  style: TextStyle(fontSize: 11, color: Colors.grey)),
                            const SizedBox(height: 16),
                            // Botão Salvar
                            SizedBox(
                              width: double.infinity,
                              height: 48,
                              child: ElevatedButton(
                                onPressed: () async {
                                  if (nameController.text.isEmpty || valueController.text.isEmpty) {
                                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Preencha nome e valor')));
                                    return;
                                  }
                                  if (selectedProfessionalId != null) {
                                    final conflicts = await _verifyBusinessRules(
                                      professionalId: selectedProfessionalId!,
                                      date: manualDate,
                                      time: manualTime,
                                      durationMin: durationMin,
                                      serviceId: serviceId,
                                      excludeDocId: appointment?['id'],
                                    );
                                    
                                    if (conflicts.isNotEmpty) {
                                      bool confirm = await _showConflictDialog(
                                        context: context,
                                        professionalName: selectedProfessionalName,
                                        timeStr: manualTime.format(context),
                                        messages: conflicts,
                                      );
                                      if (!confirm) return;
                                    }
                                  }
                                  double valor = double.tryParse(valueController.text.replaceAll(',', '.')) ?? 0.0;
                                  final DateTime manualDateNormalized = DateTime(manualDate.year, manualDate.month, manualDate.day, manualTime.hour, manualTime.minute, 0);
                                  
                                  final Map<String, dynamic> appointmentData = {
                                    'shop_id': widget.shopId,
                                    'client_id': selectedClientId,
                                    'client_name': nameController.text.trim(),
                                    'client_phone': phoneController.text.trim().isEmpty ? null : phoneController.text.trim(),
                                    'service_name': serviceController.text.isEmpty ? 'Avulso' : serviceController.text,
                                    'service_id': serviceId,
                                    'duration_min': durationMin,
                                    // Colunas de valor que realmente existem no banco
                                    'labor_value': valor,
                                    'total_value': valor,
                                    if (selectedProfessionalId != null) ...{
                                      'professional_id': selectedProfessionalId,
                                      'professional_name': selectedProfessionalName,
                                    },
                                    'status': isPaid ? 'concluido' : 'agendado',
                                    'payment_method': selectedPaymentMethod,
                                    'payment_status': isPaid ? 'pago' : 'pendente',
                                    'paid_amount': isPaid ? valor : 0.0,
                                    'remaining_amount': isPaid ? 0.0 : valor,
                                    'scheduled_at': manualDateNormalized.toIso8601String(),
                                    'updated_at': DateTime.now().toIso8601String(),
                                    if (appointment == null) 'created_at': DateTime.now().toIso8601String(),
                                    // Garantir que o preço original seja salvo para histórico de descontos
                                    'total_price': valor,
                                    'total_payable': valor,
                                    'valor_com_desconto': valor,
                                  };

                                  try {
                                    if (appointment == null) {
                                      await sb.Supabase.instance.client.from('appointments').insert(appointmentData);
                                    } else {
                                      await sb.Supabase.instance.client.from('appointments').update(appointmentData).eq('id', appointment['id']);
                                      final apptId = appointment['id'].toString();
                                      setState(() {
                                        if (_selectedAppointment != null && _selectedAppointment!['id']?.toString() == apptId) {
                                          _selectedAppointment = {..._selectedAppointment!, ...appointmentData};
                                        }
                                        final idx = _appointments.indexWhere((a) => a['id']?.toString() == apptId);
                                        if (idx != -1) _appointments[idx] = {..._appointments[idx], ...appointmentData};
                                        if (_docCache.containsKey(apptId)) {
                                          _docCache[apptId] = {..._docCache[apptId]!, ...appointmentData};
                                        }
                                        _isLoading = false;
                                      });
                                    }

                                    ShopDataCacheService().invalidate(widget.shopId, 'appointments');

                                    if (!mounted) return;
                                    Navigator.pop(context, 'edit');
                                    _loadAppointments();
                                    _loadMonthEvents();
                                    
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(appointment == null ? 'Agendamento criado!' : 'Agendamento atualizado!'),
                                        backgroundColor: Colors.green,
                                      )
                                    );
                                  } catch (e) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('Erro ao salvar: $e'))
                                    );
                                  }
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.primaryPurple,
                                  foregroundColor: Colors.white,
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                                child: Text(appointment == null ? "Finalizar Lançamento" : "Salvar Alterações",
                                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                              ),
                            ),
                            const SizedBox(height: 10),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    ).whenComplete(() {
      _isOpeningQuickEntry = false;
    });
  } catch (e) {
    _isOpeningQuickEntry = false;
    debugPrint("Erro ao abrir modal: $e");
  }
}

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        bool isDesktop = constraints.maxWidth > 900;

        return Scaffold(
          backgroundColor: const Color(0xFFF2F4F8),
          floatingActionButton: isDesktop
              ? null
              : FloatingActionButton(
                  onPressed: _showQuickEntryModal,
                  backgroundColor: AppColors.primaryPurple,
                  foregroundColor: Colors.white,
                  child: const Icon(Icons.add, color: Colors.white),
                ),
          body: isDesktop ? _buildDesktopLayout() : _buildMobileLayout(),
        );
      },
    );
  }

  // 📱 LAYOUT MOBILE
  Widget _buildMobileLayout() {
    return RefreshIndicator(
      onRefresh: _loadAppointments,
      color: AppColors.primaryPurple,
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Container(
              color: Colors.white,
              child: Column(
                children: [
                  _buildCalendarCard(isMobile: true),
                  _buildStatsSection(),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.only(top: 10, bottom: 80),
            sliver: _buildSliverList(),
          ),
        ],
      ),
    );
  }

  // 🖥️ LAYOUT DESKTOP
  Widget _buildDesktopLayout() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // --- LATERAL ESQUERDA (Navegação) ---
        Container(
          width: 350,
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border(right: BorderSide(color: Colors.grey.shade200)),
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(20),
                child: ElevatedButton.icon(
                  onPressed: _showQuickEntryModal,
                  icon: const Icon(Icons.add, color: Colors.white),
                  label: const Text(
                    "NOVO AGENDAMENTO",
                    style: TextStyle(
                        fontWeight: FontWeight.bold, letterSpacing: 0.5),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryPurple,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(double.infinity, 50),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: _buildCalendarCard(isMobile: false),
                  ),
                ),
              ),
            ],
          ),
        ),

        // --- MIOLO (Lista) ---
        Expanded(
          flex: 3,
          child: Column(
            children: [
              _buildStatsSection(),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: _isLoading && _appointments.isEmpty
                      ? const Center(child: CircularProgressIndicator())
                      : () {
                          // 🆕 Filtrar appointments baseado na aba selecionada
                          final filteredAppointments = _appointments
                              .where(_shouldShowAppointment)
                              .toList();

                          return filteredAppointments.isEmpty
                              ? _buildEmptyState()
                              : ListView.builder(
                                  controller: _scrollController,
                                  padding: const EdgeInsets.only(
                                      top: 10, bottom: 20),
                                  itemCount: filteredAppointments.length +
                                      (_hasMore ? 1 : 0),
                                  itemBuilder: (context, index) {
                                    if (index == filteredAppointments.length) {
                                      return const Center(
                                        child: Padding(
                                          padding: EdgeInsets.all(10),
                                          child: CircularProgressIndicator(),
                                        ),
                                      );
                                    }
                                    return _buildAppointmentCard(
                                        filteredAppointments[index],
                                        isDesktop: true);
                                  },
                                );
                        }(),
                ),
              ),
            ],
          ),
        ),
        // --- LATERAL DIREITA (Detalhes) ---
        if (_selectedAppointment != null)
          Expanded(
            flex: 2,
            child: Container(
              decoration: BoxDecoration(
                border: Border(left: BorderSide(color: Colors.grey.shade200)),
              ),
              child: AppointmentDetailsPage(
                appointmentDoc: _selectedAppointment!,
                isEmbedded: true,
                onEdit: () => _showQuickEntryModal(appointment: _selectedAppointment!),
                onAppointmentUpdated: (updatedData) {
                  final id = updatedData['id']?.toString();
                  setState(() {
                    _selectedAppointment = {...?_selectedAppointment, ...updatedData};
                    if (id != null) {
                      final idx = _appointments.indexWhere((a) => a['id']?.toString() == id);
                      if (idx != -1) _appointments[idx] = {..._appointments[idx], ...updatedData};
                    }
                  });
                },
                onClose: () {
                  final id = _selectedAppointment?['id'];
                  setState(() => _selectedAppointment = null);
                  if (id != null) {
                    setState(() {
                      _docCache.remove(id);
                      _cacheAccess.remove(id);
                      _appointments.removeWhere((d) => d['id'].toString() == id.toString());
                      _events.forEach((key, list) => list.remove(id));
                    });
                  }
                  _loadAppointments();
                  _loadMonthEvents();
                },
              ),
            ),
          ),
      ],
    );
  }

  // --- COMPONENTES VISUAIS ---

  Widget _buildSliverList() {
    // Avoid showing an intrusive loader below the calendar; show empty state instead.
    if (_isLoading && _appointments.isEmpty) {
      return SliverFillRemaining(child: _buildEmptyState());
    }

    // 🆕 Filtrar appointments baseado na aba selecionada
    var filteredAppointments =
        _appointments.where(_shouldShowAppointment).toList();
    // Se o usuário escolheu uma data para ser o início, filtramos para mostrar apenas daqui em diante.
    if (_startFromSelectedDay && _startFromDate != null) {
      final start = DateTime(
          _startFromDate!.year, _startFromDate!.month, _startFromDate!.day);
      filteredAppointments = filteredAppointments.where((doc) {
        final dateStr = doc['scheduled_at'] as String?;
        if (dateStr == null) return false;
        final d = DateTime.parse(dateStr);
        final dd = DateTime(d.year, d.month, d.day);
        return !dd.isBefore(start); // keep date >= start
      }).toList();
    }

    if (filteredAppointments.isEmpty) {
      return SliverFillRemaining(child: _buildEmptyState());
    }
    // Group by day and flatten into list of widgets (header + cards)
    final Map<DateTime, List<Map<String, dynamic>>> grouped = {};
    for (var doc in filteredAppointments) {
      final data = doc;
      final dateStr = data['scheduled_at'] as String?;
      if (dateStr == null) continue;
      final d = DateTime.parse(dateStr);
      final key = DateTime(d.year, d.month, d.day);
      grouped.putIfAbsent(key, () => []).add(doc);
    }

    final keys = grouped.keys.toList();
    keys.sort((a, b) => a.compareTo(b));

    final List<Widget> flat = [];
    // show top loader if there are older items to load
    if (_hasMorePast) {
      flat.add(const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Center(
            child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2))),
      ));
    }
    // if week-view is active, don't show top loader (we only show that week's items)
    if (_startFromSelectedDay && _weekEndDate != null) {
      flat.clear();
    }
    for (final key in keys) {
      // header with + button
      final headerKey = _dayKeys.putIfAbsent(key, () => GlobalKey());
      flat.add(Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
        child: Container(
          key: headerKey,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(DateFormat('EEEE, dd/MM/yyyy', 'pt_BR').format(key),
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, color: Colors.grey)),
              IconButton(
                icon: const Icon(Icons.add_circle, color: Colors.green),
                tooltip: 'Adicionar agendamento neste dia',
                onPressed: () => _showQuickEntryModal(initialDate: key),
              ),
            ],
          ),
        ),
      ));

      for (final doc in grouped[key]!) {
        flat.add(Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: _buildAppointmentCard(doc, isDesktop: false),
        ));
      }
    }

    // NOTE: removed bottom loader to keep scrolling visual clean (preloading happens silently)

    return SliverList(
        delegate: SliverChildBuilderDelegate((context, index) {
      return flat[index];
    }, childCount: flat.length));
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.event_busy, size: 60, color: Colors.grey.shade300),
          const SizedBox(height: 15),
          Text(
            "Agenda vazia para este dia.",
            style: TextStyle(color: Colors.grey.shade600, fontSize: 16),
          ),
          TextButton(
            onPressed: _jumpToToday,
            child: const Text("Voltar para Hoje"),
          ),
        ],
      ),
    );
  }

  Future<List<String>> _verifyBusinessRules({
    required String professionalId,
    required DateTime date,
    required TimeOfDay time,
    required int durationMin,
    String? serviceId,
    String? excludeDocId,
  }) async {
    final List<String> conflicts = [];

    // 1. Fetch Professional Data
    final empDoc = await sb.Supabase.instance.client
        .from('employees')
        .select()
        .eq('id', professionalId)
        .maybeSingle();

    if (empDoc == null) return ["Profissional não encontrado."];

    // 2. Check Weekday
    final List<int> workDays = List<int>.from(empDoc['work_days'] ?? []);
    if (!workDays.contains(date.weekday) &&
        !(date.weekday == 7 && (workDays.contains(0) || workDays.contains(7)))) {
      conflicts.add("O profissional não trabalha neste dia da semana.");
    }

    // 3. Check Working Hours
    final String startStr = empDoc['work_start'] ?? "08:00";
    final String endStr = empDoc['work_end'] ?? "18:00";
    int startDayMin =
        int.parse(startStr.split(':')[0]) * 60 + int.parse(startStr.split(':')[1]);
    int endDayMin =
        int.parse(endStr.split(':')[0]) * 60 + int.parse(endStr.split(':')[1]);
    int targetStartMin = time.hour * 60 + time.minute;
    int targetEndMin = targetStartMin + durationMin;

    if (targetStartMin < startDayMin) {
      conflicts.add(
          "O horário de início é antes do expediente do profissional ($startStr).");
    }
    if (targetEndMin > endDayMin) {
      conflicts.add(
          "O agendamento termina após o expediente do profissional ($endStr).");
    }

    // 4. Check Service Aptitude
    if (serviceId != null) {
      final List<String> proServices =
          List<String>.from(empDoc['services_ids'] ?? []);
      if (!proServices.contains(serviceId)) {
        conflicts.add(
            "Este profissional não está marcado como apto para este serviço.");
      }
    }

    // 5. Check Overlaps
    final busy = await AvailabilityUtils.getBusyIntervals(professionalId, date,
        excludeDocId: excludeDocId);
    bool available =
        AvailabilityUtils.isSlotAvailable(targetStartMin, durationMin, busy);
    if (!available) {
      conflicts.add("Este horário já está ocupado por outro agendamento.");
    }

    return conflicts;
  }

  Future<bool> _showConflictDialog({
    required BuildContext context,
    required String professionalName,
    required String timeStr,
    List<String>? messages,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: const [
            Icon(Icons.warning_amber_rounded, color: Colors.orange),
            SizedBox(width: 10),
            Text("Conflito Detectado"),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "O agendamento para $professionalName às $timeStr possui os seguintes pontos de atenção:",
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            if (messages != null && messages.isNotEmpty)
              ...messages.map((m) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text("• ", style: TextStyle(fontWeight: FontWeight.bold)),
                        Expanded(child: Text(m)),
                      ],
                    ),
                  ))
            else
              const Text("Este horário já possui um agendamento (sobreposição)."),
            const SizedBox(height: 12),
            const Text("Deseja realizar a sobreposição administrativa mesmo assim?"),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("CANCELAR", style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
            ),
            child: const Text("SIM, SOBREPOR"),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Widget _buildCalendarCard({required bool isMobile}) {
    return Column(
      children: [
        TableCalendar(
          locale: 'pt_BR',
          firstDay: DateTime.utc(2020, 1, 1),
          lastDay: DateTime.utc(2030, 12, 31),
          focusedDay: _focusedDay,
          currentDay: DateTime.now(),
          calendarFormat: isMobile ? _calendarFormat : CalendarFormat.month,
          availableCalendarFormats: const {
            CalendarFormat.month: 'Mês',
            CalendarFormat.week: 'Semana'
          },
          onFormatChanged: (format) {
            if (!isMobile) return;
            setState(() => _calendarFormat = format);
            if (format == CalendarFormat.month) {
              _loadAppointmentsForMonth(_focusedDay);
            } else {
              final startOfWeek = _focusedDay.subtract(
                  Duration(days: _focusedDay.weekday - 1));
              final endOfWeek = startOfWeek.add(const Duration(days: 6));
              setState(() {
                _startFromSelectedDay = true;
                _startFromDate = DateTime(
                    startOfWeek.year, startOfWeek.month, startOfWeek.day);
                _weekEndDate = DateTime(
                    endOfWeek.year, endOfWeek.month, endOfWeek.day, 23, 59, 59);
              });
              _applyWeekFilterToCache();
              _fetchWeekFromServer(_startFromDate!, _weekEndDate!);
            }
            _loadRevenueStats();
          },
          selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
          eventLoader: _getEventsForDay,
          onDaySelected: (selectedDay, focusedDay) {
            // Ao selecionar um dia, definimos a semana do dia como ponto de partida
            final startOfWeek =
                selectedDay.subtract(Duration(days: selectedDay.weekday - 1));
            final endOfWeek = startOfWeek.add(const Duration(days: 6));
            setState(() {
              _selectedDay = selectedDay;
              _focusedDay = focusedDay;
              _showOnlySelectedDay = false;
              _startFromSelectedDay = true;
              _startFromDate = DateTime(
                  startOfWeek.year, startOfWeek.month, startOfWeek.day);
              _weekEndDate =
                  DateTime(endOfWeek.year, endOfWeek.month, endOfWeek.day, 23, 59, 59);
            });
            // Aplicar filtro imediato aos dados em cache e rolar para o dia selecionado.
            _applyWeekFilterToCache();
            _scrollToSelectedDay();
            // Buscar a semana no servidor em background e atualizar a lista quando retornar.
            _fetchWeekFromServer(_startFromDate!, _weekEndDate!);
          },
          onPageChanged: (focusedDay) {
            final oldYear = _focusedDay.year;
            setState(() => _focusedDay = focusedDay);
            if (focusedDay.year != oldYear) {
              _fetchHolidays();
            }
            _loadMonthEvents();

            // No modo semana: atualizar janela e buscar dados da semana
            final isMobileWeek = _calendarFormat == CalendarFormat.week;
            if (isMobileWeek) {
              final startOfWeek = focusedDay.subtract(
                  Duration(days: focusedDay.weekday - 1));
              final endOfWeek = startOfWeek.add(const Duration(days: 6));
              setState(() {
                _startFromSelectedDay = true;
                _startFromDate = DateTime(
                    startOfWeek.year, startOfWeek.month, startOfWeek.day);
                _weekEndDate = DateTime(
                    endOfWeek.year, endOfWeek.month, endOfWeek.day, 23, 59, 59);
              });
              _applyWeekFilterToCache();
              _fetchWeekFromServer(_startFromDate!, _weekEndDate!);
            } else {
              _loadAppointmentsForMonth(focusedDay);
            }
            _loadRevenueStats();
          },
          calendarBuilders: CalendarBuilders(
            markerBuilder: (context, day, events) {
              final List<Widget> markers = [];
              final isoDate = day.toIso8601String().split('T')[0];

              // 1. National/Global Holiday Marker (Blue)
              final isNational = _nationalHolidays.any((f) => f['date'] == isoDate);
              final isGlobal = _globalHolidays.any((f) => f['date'] == isoDate);
              
              if (isNational || isGlobal) {
                markers.add(
                  Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                      color: Colors.blue,
                      shape: BoxShape.circle,
                    ),
                  ),
                );
              }

              // 2. Appointment Marker (Orange)
              if (events.isNotEmpty) {
                markers.add(
                  Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                      color: Colors.orange,
                      shape: BoxShape.circle,
                    ),
                  ),
                );
              }

              if (markers.isEmpty) return null;

              return Positioned(
                bottom: 1,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: markers.map((m) => Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 1),
                    child: m,
                  )).toList(),
                ),
              );
            },
          ),
          headerStyle: const HeaderStyle(
            titleCentered: true,
            formatButtonVisible: true,
            titleTextStyle:
                TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          calendarStyle: CalendarStyle(
            selectedDecoration: const BoxDecoration(
              color: AppColors.primaryPurple,
              shape: BoxShape.circle,
            ),
            todayDecoration: BoxDecoration(
              color: AppColors.primaryPurple.withValues(alpha: 0.3),
              shape: BoxShape.circle,
            ),
            weekendTextStyle: const TextStyle(color: Colors.red),
            outsideDaysVisible: false,
          ),
        ),
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _buildStatsSection() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      color: Colors.transparent,
      child: Text(
        "Faturamento da semana: ${NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$').format(_weeklyRevenue)}",
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        textAlign: TextAlign.left,
      ),
    );
  }

  // Busca faturamento semanal com query filtrada por data
  Future<void> _loadRevenueStats() async {
    if (widget.shopId.isEmpty) return;
    final weekBase = _startFromDate ?? DateTime.now();
    final mondayOfWeek = weekBase.subtract(Duration(days: weekBase.weekday - 1));
    final weekStart = DateTime(mondayOfWeek.year, mondayOfWeek.month, mondayOfWeek.day);
    final weekEnd = DateTime(mondayOfWeek.year, mondayOfWeek.month, mondayOfWeek.day + 6, 23, 59, 59);
    try {
      final selectCols = 'total_payable, total_price, total_value, valor_com_desconto, labor_value, status';
      final snap = await sb.Supabase.instance.client
          .from('appointments')
          .select(selectCols)
          .eq('shop_id', widget.shopId)
          .gte('scheduled_at', weekStart.toUtc().toIso8601String())
          .lte('scheduled_at', weekEnd.toUtc().toIso8601String());
      double wSum = 0.0;
      for (final d in snap as List) {
        if ((d['status'] ?? '').toString().toLowerCase() == 'cancelado') continue;
        wSum += _parseRevenueValue(d);
      }
      if (mounted) {
        setState(() => _weeklyRevenue = wSum);
      }
    } catch (e) {
      debugPrint('Erro ao carregar receita: $e');
    }
  }

  double _parseRevenueValue(Map<String, dynamic> d) {
    final val = d['total_payable'] ?? d['total_price'] ?? d['total_value'] ?? d['valor_com_desconto'] ?? d['labor_value'] ?? 0;
    if (val is num) return val.toDouble();
    if (val is String) return double.tryParse(val.replaceAll(',', '.')) ?? 0.0;
    return 0.0;
  }

  // Canal Realtime: atualiza apenas o necessário quando há alterações
  void _startRealtimeSubscription() {
    if (widget.shopId.isEmpty) return;
    _scheduleRealtimeChannel = sb.Supabase.instance.client
        .channel('schedule_appts_${widget.shopId}')
        .onPostgresChanges(
          event: sb.PostgresChangeEvent.all,
          schema: 'public',
          table: 'appointments',
          filter: sb.PostgresChangeFilter(
            type: sb.PostgresChangeFilterType.eq,
            column: 'shop_id',
            value: widget.shopId,
          ),
          callback: (payload) {
            if (!mounted) return;
            _realtimeDebounceTimer?.cancel();
            _realtimeDebounceTimer = Timer(const Duration(milliseconds: 800), () {
              if (!mounted) return;
              final monthKey = '${_focusedDay.year}-${_focusedDay.month}';
              _loadedMonths.remove(monthKey);
              _loadRevenueStats();
              _fetchWeekFromServer(
                _startFromDate ?? DateTime.now(),
                _weekEndDate ?? DateTime.now().add(const Duration(days: 6)),
              );
            });
          },
        )
        .subscribe();
  }

  // --- CALCULADORAS ---
  double _safeParseValue(Map<String, dynamic> data) {
    dynamic val = data['total_value'] ?? 
                  data['valor_com_desconto'] ?? 
                  data['total_price'] ?? 
                  data['valor_total'] ?? 
                  data['price'] ?? 
                  data['valor'] ?? 
                  data['labor_value'] ?? 
                  data['preco'] ?? 0;
    if (val == null || val.toString().trim().isEmpty) return 0.0;
    if (val is num) return val.toDouble();
    if (val is String) return double.tryParse(val.replaceAll(',', '.')) ?? 0.0;
    return 0.0;
  }

  // -----------------------
  // Cache helpers
  // -----------------------
  void _addToCache(Map<String, dynamic> doc) {
    final id = doc['id'].toString();
    _docCache[id] = doc;
    _cacheAccess[id] = DateTime.now();
    _pruneCacheIfNeeded();
  }

  Future<void> _fetchHolidays() async {
    try {
      final year = _focusedDay.year;
      // 1. National Holidays (BrasilAPI)
      final national = await BrasilApiService.getHolidays(year);
      
      // 2. Global Holidays (Database)
      final global = await sb.Supabase.instance.client // Changed Supabase to sb.Supabase
          .from('global_holidays')
          .select()
          .gte('date', '$year-01-01')
          .lte('date', '$year-12-31');

      if (mounted) {
        setState(() {
          _nationalHolidays = national;
          _globalHolidays = List<Map<String, dynamic>>.from(global);
        });
      }
    } catch (e) {
      debugPrint("Erro ao buscar feriados: $e");
    }
  }

  void _pruneCacheIfNeeded() {
    if (_docCache.length <= _cacheMaxEntries) return;
    // remove least-recently used
    final entries = _cacheAccess.entries.toList();
    entries.sort((a, b) => a.value.compareTo(b.value));
    while (_docCache.length > _cacheMaxEntries && entries.isNotEmpty) {
      final oldest = entries.removeAt(0);
      _docCache.remove(oldest.key);
      _cacheAccess.remove(oldest.key);
      _appointments.removeWhere((d) => d['id'].toString() == oldest.key);
    }
  }

  Future<void> _refreshStaleCacheEntries() async {
    try {
      final now = DateTime.now();
      final staleIds = <String>[];
      _cacheAccess.forEach((id, ts) {
        if (now.difference(ts) > _cacheTTL) staleIds.add(id);
      });
      if (staleIds.isEmpty) return;
      final batch = staleIds.take(20).toList();
      // Single batch query — replaces N+1 sequential requests
      final docs = await sb.Supabase.instance.client
          .from('appointments')
          .select()
          .filter('id', 'in', '(${batch.join(',')})');  
      if (!mounted) return;
      final foundIds = <String>{
        for (final doc in docs) doc['id'].toString()
      };
      final removedIds = batch.where((id) => !foundIds.contains(id)).toList();
      setState(() {
        for (final doc in docs) {
          final id = doc['id'].toString();
          _docCache[id] = doc;
          _cacheAccess[id] = DateTime.now();
          final idx = _appointments.indexWhere((a) => a['id'].toString() == id);
          if (idx != -1) _appointments[idx] = doc;
        }
        for (final id in removedIds) {
          _docCache.remove(id);
          _cacheAccess.remove(id);
          _appointments.removeWhere((a) => a['id'].toString() == id);
        }
        _pruneCacheIfNeeded();
      });
    } catch (e) {
      debugPrint('Erro ao refresh cache: $e');
    }
  }

  @override
  void dispose() {
    _scheduleRealtimeChannel?.unsubscribe();
    _cacheRefreshTimer?.cancel();
    _realtimeDebounceTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  // Fetch a specific week from server and replace visible appointments (silent, no intr. loader)
  Future<void> _fetchWeekFromServer(
      DateTime startDate, DateTime endDate) async {
    try {
      final start =
          DateTime(startDate.year, startDate.month, startDate.day, 0, 0, 0);
      final end =
          DateTime(endDate.year, endDate.month, endDate.day, 23, 59, 59);
      final snap = await sb.Supabase.instance.client
          .from('appointments')
          .select('id, shop_id, professional_id, client_id, scheduled_at, duration_min, status, total_value, total_price, labor_value, valor_com_desconto, paid_amount, remaining_amount, payment_method, payment_status, coupon_applied, coupon_code, birthday_discount_applied, metadata, service_id, client_name, client_phone, client_email, service_name, professional_name')
          .eq('shop_id', widget.shopId)
          .gte('scheduled_at', start.toUtc().toIso8601String())
          .lte('scheduled_at', end.toUtc().toIso8601String())
          .order('scheduled_at', ascending: true)
          .limit(200);

      if (!mounted) return;
      setState(() {
        // replace visible appointments with fresh week data
        _appointments = List<Map<String, dynamic>>.from(snap);
        // update cache and cursors
        for (var d in snap) {
          _addToCache(d);
        }
        if (_appointments.isNotEmpty) {
          _firstDocument = _appointments.first;
          _lastDocument = _appointments.last;
        }
        // update events for this week
        for (var d in snap) {
          final data = d;
          final dateStr = data['scheduled_at'] as String?;
          if (dateStr == null) continue;
          final status = (data['status'] ?? '').toString().toLowerCase();
          if (status == 'cancelado') continue;
          
          final date = DateTime.parse(dateStr);
          final dateKey = DateTime(date.year, date.month, date.day);
          final existing = _events[dateKey] ?? [];
          final id = d['id'].toString();
          if (!existing.contains(id)) {
            existing.add(id);
            _events[dateKey] = existing;
          }
        }
      });
      // Recalcular faturamento semanal a partir dos dados frescos
      _updateWeeklyRevenueFromAppointments();
      // Scroll automático até o dia selecionado
      _scrollToSelectedDay();
    } catch (e) {
      debugPrint('Erro ao buscar semana: $e');
    }
  }

  // Apply week filter to currently cached documents (no network)
  void _applyWeekFilterToCache() {
    if (!(_startFromSelectedDay &&
        _startFromDate != null &&
        _weekEndDate != null)) {
      return;
    }
    final start = DateTime(
        _startFromDate!.year, _startFromDate!.month, _startFromDate!.day);
    final end =
        DateTime(_weekEndDate!.year, _weekEndDate!.month, _weekEndDate!.day, 23, 59, 59);

    final filtered = _docCache.values.where((data) {
      final dateStr = data['scheduled_at'] as String?;
      if (dateStr == null) return false;
      final d = DateTime.parse(dateStr);
      final dd = DateTime(d.year, d.month, d.day);
      return !dd.isBefore(start) && !dd.isAfter(end);
    }).toList();

    // sort by date asc
    filtered.sort((a, b) {
      final da = DateTime.parse(a['scheduled_at'] as String);
      final db = DateTime.parse(b['scheduled_at'] as String);
      return da.compareTo(db);
    });

    setState(() {
      _appointments = filtered;
      if (_appointments.isNotEmpty) {
        _firstDocument = _appointments.first;
        _lastDocument = _appointments.last;
      }
    });
  }

  Widget _buildAppointmentCard(Map<String, dynamic> data,
      {required bool isDesktop}) {
    final dateStr = data['scheduled_at'] as String;
    DateTime hora = DateTime.parse(dateStr);

    double total = _safeParseValue(data);
    double pago = double.tryParse(
      data['paid_amount']?.toString() ??
      data['paid_value']?.toString() ?? 
      data['valor_pago']?.toString() ?? 
      data['valorPago']?.toString() ?? "0") ?? 0;
    String status = data['status']?.toString().toLowerCase() ?? '';
    String paymentMethod = data['payment_method']?.toString() ?? 'Não informado';
    bool hasOnlinePayment = data['metadata'] != null && data['metadata'] is Map && data['metadata']['payment_id'] != null;

    // Priorizar payment_status se existir, senão inferir
    String pStat = data['payment_status']?.toString().toLowerCase() ?? '';
    bool quitado = pStat == 'pago' || (pago >= total && total > 0.01) || status == 'concluido';
    bool isCanceled = status == 'cancelado';

    Color statusColor = isCanceled ? Colors.red : Colors.green;
    String statusText = isCanceled ? "CANCELADO" : "CONFIRMADO";

    Color payColor = quitado ? Colors.green : (pago > 0.01 ? Colors.orange : Colors.grey);
    String payText = quitado ? "PAGO" : (pago > 0.01 ? "ADIANTADO" : "PGTO. PENDENTE");

    bool isSelected = isDesktop && _selectedAppointment?['id']?.toString() == data['id']?.toString();

    // Dados para abrir perfil do cliente
    final clientId = data['client_id'] ?? data['clientId'] ?? data['clienteId'] ?? data['userId'];
    final rawClientNome = (data['client_name'] ?? data['name'] ?? '').toString().trim();
    final clientNome = (rawClientNome.toLowerCase() == 'null') ? '' : rawClientNome;
    final String clientDisplay = clientNome.isNotEmpty ? clientNome : 'Cliente';
    final String clientInitial =
        clientDisplay.isNotEmpty ? clientDisplay[0].toUpperCase() : '?';

    final rawServiceNome = (data['service_name'] ?? data['servico_nome'] ?? data['servicoNome'] ?? data['serviceName'] ?? data['servico'] ?? '').toString().trim();
    final serviceNome = (rawServiceNome.toLowerCase() == 'null') ? '' : rawServiceNome;
    final String serviceDisplay = serviceNome.isNotEmpty ? serviceNome : 'Serviço';
    final String professionalNome = data['professional_name'] ?? data['profissional_nome'] ?? data['professionalName'] ?? data['profissionalNome'] ?? 'Não definido';

    void openClientProfile() {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (ctx) => DraggableScrollableSheet(
          initialChildSize: 0.85,
          maxChildSize: 0.95,
          minChildSize: 0.5,
          builder: (_, controller) => ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            child: Scaffold(
              body: ClientDetailsPage(
                clientData: {
                  'nome': clientNome,
                  'telefone': data['client_phone'] ??
                      data['telefone'] ??
                      data['whatsapp'] ??
                      'Não informado',
                  'email': data['client_email'] ?? data['email'] ?? '',
                  'origem': data['tipo'] == 'manual' ? 'manual' : 'app',
                  'totalGasto': total,
                  'visitas': 1,
                },
                clientId: clientId.toString(),
                shopIdOverride: widget.shopId,
                onClose: () => Navigator.pop(ctx),
              ),
            ),
          ),
        ),
      );
    }

    return GestureDetector(
      onTap: () async {
        if (isDesktop) {
          setState(() {
            _selectedAppointment = data;
          });
        } else {
          final result = await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => AppointmentDetailsPage(
                appointmentDoc: data,
                onEdit: () {
                  Navigator.pop(context, 'edit'); // Fecha Detalhes para abrir Modal
                  _showQuickEntryModal(appointment: data);
                },
              ),
            ),
          );
          // Se o pop foi pelo botão Editar, o modal cuida do reload — não recarregar agora
          if (result != 'edit') {
            final id = data['id'].toString();
            setState(() {
              _docCache.remove(id);
              _cacheAccess.remove(id);
              _appointments.removeWhere((d) => d['id'].toString() == id);
              // Remove também dos eventos
              for (var list in _events.values) {
                list.remove(id);
              }
            });
            _loadAppointments();
            _loadMonthEvents();
          }
        }
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: isSelected
              ? Border.all(color: AppColors.primaryPurple, width: 2)
              : Border.all(color: Colors.transparent),
          boxShadow: [
            BoxShadow(
              color: Colors.grey.withValues(alpha: 0.08),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: IntrinsicHeight(
          child: Row(
            children: [
              // Barra lateral de status
              Container(
                width: 6,
                decoration: BoxDecoration(
                  color: statusColor,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(12),
                    bottomLeft: Radius.circular(12),
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      // Coluna de Horários e Ícone
                      Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          GestureDetector(
                            onTap: openClientProfile,
                            child: Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: AppColors.primaryPurple.withValues(alpha: 0.1),
                                shape: BoxShape.circle,
                              ),
                              child: Center(
                                child: Text(
                                  clientInitial,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.primaryPurple,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            DateFormat('HH:mm').format(hora),
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 15,
                              color: Colors.black87,
                            ),
                          ),
                          Text(
                            DateFormat('HH:mm').format(hora.add(Duration(minutes: int.tryParse(data['duration_min']?.toString() ?? '30') ?? 30))),
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade600,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            DateFormat('dd/MM').format(hora),
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.grey.shade400,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(width: 16),
                      Container(
                          width: 1, height: 60, color: Colors.grey.shade200),
                      const SizedBox(width: 16),

                      // Infos Cliente
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: GestureDetector(
                                    onTap: openClientProfile,
                                    child: Text(
                                      clientDisplay,
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 15,
                                        decoration: isCanceled
                                            ? TextDecoration.lineThrough
                                            : TextDecoration.none,
                                        color: isCanceled
                                            ? Colors.grey
                                            : Colors.black87,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            // Serviço e Profissional
                            Text(
                              "$serviceDisplay • $professionalNome",
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.grey.shade600,
                                fontSize: 11,
                              ),
                            ),
                            const SizedBox(height: 6),
                            // Tags de Status e Pagamento
                            Wrap(
                              spacing: 6,
                              runSpacing: 4,
                              children: [
                                // Badge de Status do Agendamento
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: statusColor.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    statusText,
                                    style: TextStyle(
                                      fontSize: 8,
                                      fontWeight: FontWeight.w800,
                                      color: statusColor,
                                    ),
                                  ),
                                ),
                                // Badge de Forma de Pagamento
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: AppColors.primaryPurple.withValues(alpha: 0.05),
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(color: AppColors.primaryPurple.withValues(alpha: 0.2)),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.payments_outlined, size: 9, color: AppColors.primaryPurple),
                                      const SizedBox(width: 3),
                                      Text(
                                        paymentMethod.toUpperCase(),
                                        style: const TextStyle(
                                          fontSize: 8, 
                                          fontWeight: FontWeight.bold, 
                                          color: AppColors.primaryPurple
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      // Valor e Status
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Builder(builder: (context) {
                            final double originalPrice = double.tryParse(data['total_price']?.toString() ?? '0') ?? 0;
                            final double discountAmt = double.tryParse(data['discount_amount']?.toString() ?? '0') ?? 0;
                            final bool hasDiscount = discountAmt > 0.01 || originalPrice > total + 0.01;
                            if (!hasDiscount) return const SizedBox.shrink();
                            final double trueOriginal = originalPrice > total ? originalPrice : (total + discountAmt);
                            return Text(
                              NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$').format(trueOriginal),
                              style: const TextStyle(
                                fontSize: 10,
                                color: Colors.grey,
                                decoration: TextDecoration.lineThrough,
                              ),
                            );
                          }),
                          Text(
                            NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$').format(total),
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                          ),
                          const SizedBox(height: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: payColor.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              payText,
                              style: TextStyle(
                                color: payColor,
                                fontWeight: FontWeight.bold,
                                fontSize: 9,
                              ),
                            ),
                          ),
                          if (hasOnlinePayment) ...[
                            const SizedBox(height: 6),
                            InkWell(
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => TransactionDetailsPage(
                                      appointmentData: data,
                                    ),
                                  ),
                                );
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: AppColors.primaryPurple,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.receipt_long_outlined, size: 10, color: Colors.white),
                                    SizedBox(width: 4),
                                    Text(
                                      "PAGTO",
                                      style: TextStyle(
                                        fontSize: 8,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _paymentMethodChip({
    required String label,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.primaryPurple : Colors.grey.shade50,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isSelected ? AppColors.primaryPurple : Colors.grey.shade200,
            ),
          ),
          child: Column(
            children: [
              Icon(
                icon,
                size: 18,
                color: isSelected ? Colors.white : Colors.grey,
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: isSelected ? Colors.white : Colors.grey,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}