import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';
import 'dart:async';
import '../../core/theme/app_colors.dart';
import 'appointment_details_page.dart';
import 'helpers/cancellation_helper.dart';
import '../../core/services/brasilapi_service.dart';
import '../clients/client_details_page.dart';
import '../../core/utils/availability_utils.dart';
import '../../core/utils/work_schedule.dart';
import '../../core/utils/shop_category_helper.dart';
import '../../core/services/shop_data_cache_service.dart';
import '../../core/services/schedule_cache_service.dart';
import '../../core/services/transaction_autocomplete_service.dart';
import '../../core/services/privacy_service.dart';
import '../../utils/payment_summary.dart';
import '../../utils/name_utils.dart';
import 'holidays_page.dart';
import 'widgets/break_schedule_card.dart';
import 'widgets/client_avatar_badge.dart';
import 'widgets/client_note_badge.dart';
import 'widgets/holiday_schedule_card.dart';

class BusinessSchedulePage extends StatefulWidget {
  final String shopId;
  final DateTime? initialDate;
  final String? initialAppointmentId;
  final void Function(DateTime date, String holidayName)? onNavigateToHoliday;
  const BusinessSchedulePage({
    super.key,
    required this.shopId,
    this.initialDate,
    this.initialAppointmentId,
    this.onNavigateToHoliday,
  });

  @override
  State<BusinessSchedulePage> createState() => _BusinessSchedulePageState();
}

class _BusinessSchedulePageState extends State<BusinessSchedulePage>
    with AutomaticKeepAliveClientMixin {
  static const String _appointmentSelectCols =
      'id, shop_id, professional_id, client_id, scheduled_at, duration_min, status, '
      'total_value, total_price, labor_value, valor_com_desconto, total_payable, '
      'discount_amount, card_tax_percent, paid_amount, remaining_amount, '
      'payment_method, payment_status, payment_id, pago_em, created_at, updated_at, '
      'coupon_applied, coupon_code, coupon_discount_percent, '
      'birthday_discount_applied, birthday_discount_percent, metadata, '
      'service_id, client_name, client_phone, client_email, client_photo, '
      'service_name, professional_name, created_by, '
      'refund_status, refund_amount, refunded_at, refunded_by, '
      'confirmation_state, confirmed_via_whatsapp, '
      'whatsapp_reminder_status, whatsapp_reminder_sent_at, '
      'whatsapp_reminder_failed_at, whatsapp_reminder_confirmed_at';

  // --- CALENDÁRIO ---
  DateTime _focusedDay = DateTime.now();
  DateTime _selectedDay = DateTime.now();
  CalendarFormat _calendarFormat = CalendarFormat.week;
  String? _shopCategory;
  bool get _isTrancistaShop => ShopCategoryHelper.isTrancista(_shopCategory);

  // Eventos por dia (para pontinho laranja)
  Map<DateTime, List<String>> _events = {};
  // Keys para cada cabeçalho de dia (permitir scroll até o header)
  final Map<DateTime, GlobalKey> _dayKeys = {};
  // Keys para scroll até agendamento específico
  final Map<String, GlobalKey> _appointmentKeys = {};
  String? _highlightedAppointmentId;
  bool _initialScrollDone = false;

  String _formatHourMinute(dynamic isoString) {
    if (isoString == null) return '';
    try {
      final d = DateTime.parse(isoString.toString()).toLocal();
      return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return '';
    }
  }

  // Holidays state
  List<dynamic> _nationalHolidays = [];
  List<Map<String, dynamic>> _globalHolidays = [];
  Map<String, dynamic> _configuredHolidays = {};
  List<dynamic> _customHolidays = [];
  List<dynamic> _pendingHolidays = [];
  final Set<int> _loadedHolidayYears = {};

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
  Timer? _scrollTrackDebounce;
  bool _isLoading = false;
  bool _hasMore = true;
  bool _hasMorePast =
      true; // indica se há mais documentos no passado para carregar

  // Cache removido — NFS-e auto-emitida precisa de re-verificação a cada render

  Map<String, dynamic>? _lastDocument;
  Map<String, dynamic>? _firstDocument;
  final int _perPage = 20;
  Map<String, dynamic> _shopConfig = {};

  // --- LÓGICA DE VISUALIZAÇÃO ---
  bool _showOnlySelectedDay = false;
  Map<String, dynamic>? _selectedAppointment;
  // Quando true, a lista abaixo do calendário começa a partir de _startFromDate (inclusive)
  bool _startFromSelectedDay = false;
  DateTime? _startFromDate;
  DateTime? _weekEndDate;
  final Set<String> _vipClientIds = {};
  final Set<String> _checkedVipClientIds = {};

  // removed tabs: schedule shows active appointments by default
  bool _isOpeningQuickEntry = false;

  late final Stream<List<Map<String, dynamic>>> _employeesStream;
  List<Map<String, dynamic>> _professionals = [];

  // --- RECEITA CACHEADA (substitui streams ilimitados) ---
  double _weeklyRevenue = 0.0;
  sb.RealtimeChannel? _scheduleRealtimeChannel;
  final Set<String> _loadedMonths = {};

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadFromCache();
    // por padrão, começar a lista a partir da semana atual
    if (widget.initialDate != null) {
      final d = widget.initialDate!;
      _focusedDay = d;
      _selectedDay = d;
      _showOnlySelectedDay = false;
      _startFromSelectedDay = true;
      final startOfWeek = d.subtract(Duration(days: d.weekday - 1));
      final endOfWeek = startOfWeek.add(const Duration(days: 6));
      _startFromDate = DateTime(
          d.year, d.month, d.day); // lista começa no dia exato selecionado
      _weekEndDate =
          DateTime(endOfWeek.year, endOfWeek.month, endOfWeek.day, 23, 59, 59);
      final weekFetchStart =
          DateTime(startOfWeek.year, startOfWeek.month, startOfWeek.day);
      // Após o primeiro frame: mostra cache instantaneamente + busca servidor em background
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (_cacheCoversRange(weekFetchStart, _weekEndDate!)) {
          _applyWeekFilterToCache();
          _updateWeeklyRevenueFromAppointments();
          if (!_initialScrollDone && widget.initialAppointmentId != null) {
            _initialScrollDone = true;
            _scrollToAppointment(widget.initialAppointmentId!);
          } else {
            _scrollToSelectedDay();
          }
        }
        _fetchWeekFromServer(weekFetchStart, _weekEndDate!);
      });
    } else {
      _showOnlySelectedDay = false;
      _startFromSelectedDay = true;
      final now = DateTime.now();
      final startOfWeek = now.subtract(Duration(days: now.weekday - 1));
      _startFromDate = DateTime(now.year, now.month, now.day);
      final endOfWeek = startOfWeek.add(const Duration(days: 6));
      _weekEndDate =
          DateTime(endOfWeek.year, endOfWeek.month, endOfWeek.day, 23, 59, 59);
      // Carrega a semana atual imediatamente (inclui agendamentos futuros da semana)
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (_cacheCoversRange(_startFromDate!, _weekEndDate!)) {
          _applyWeekFilterToCache();
          _updateWeeklyRevenueFromAppointments();
          _scrollToSelectedDay();
        }
        _fetchWeekFromServer(_startFromDate!, _weekEndDate!);
      });
    }

    _loadShopConfig();
    _loadShopVipClients();
    _loadMonthEvents();
    _fetchHolidays(); // Added by user
    _scrollController.addListener(_onScroll);

    // 1. Inicializar Stream de Employees compartilhado
    _employeesStream = sb.Supabase.instance.client
        .from('employees')
        .stream(primaryKey: ['id'])
        .eq('shop_id', widget.shopId)
        .asBroadcastStream();

    _employeesStream.listen((data) {
      if (mounted) {
        setState(() {
          _professionals = data;
        });
      }
    });

    // Start periodic cache refresh to validate stale entries
    _cacheRefreshTimer = Timer.periodic(const Duration(minutes: 10), (_) {
      if (!mounted) return;
      _refreshStaleCacheEntries();
    });
    _loadRevenueStats();
    _startRealtimeSubscription();
  }

  Future<void> _loadFromCache() async {
    try {
      final cached =
          await ScheduleCacheService.getCachedAppointments(widget.shopId);
      if (cached != null && cached.isNotEmpty && mounted) {
        setState(() {
          _appointments = cached;
          for (var d in cached) {
            _addToCache(d);
          }
          _firstDocument = _appointments.first;
          _lastDocument = _appointments.last;
        });
        _resolveVipForAppointments(_appointments);
      }
    } catch (_) {}
  }

  Future<void> _loadShopConfig() async {
    final doc = await sb.Supabase.instance.client
        .from('shops')
        .select(
            'config, configured_holidays, custom_holidays, pending_holidays, category, niche')
        .eq('id', widget.shopId)
        .maybeSingle();
    if (doc != null && mounted) {
      final data = doc;
      setState(() {
        _shopCategory = (data['category'] ?? data['niche'] ?? '').toString();
        _shopConfig = data['config'] is Map
            ? Map<String, dynamic>.from(data['config'] as Map)
            : {};
        _configuredHolidays = data['configured_holidays'] is Map
            ? Map<String, dynamic>.from(data['configured_holidays'] as Map)
            : {};
        _customHolidays = data['custom_holidays'] is List
            ? List<dynamic>.from(data['custom_holidays'] as List)
            : [];
        _pendingHolidays = data['pending_holidays'] is List
            ? List<dynamic>.from(data['pending_holidays'] as List)
            : [];
      });
    }
  }

  void _buildEventsFromCache(DateTime start, DateTime end) {
    final Map<DateTime, List<String>> events = {};
    for (var doc in _docCache.values) {
      final rawSA = doc['scheduled_at'];
      if (rawSA == null) continue;
      final status = (doc['status'] ?? '').toString().toLowerCase();
      if (status == 'cancelado') continue;
      final date = rawSA is DateTime ? rawSA : DateTime.parse(rawSA.toString());
      final dateKey = DateTime(date.year, date.month, date.day);
      if (!dateKey.isBefore(start) && !dateKey.isAfter(end)) {
        events[dateKey] = (events[dateKey] ?? [])..add(doc['id'].toString());
      }
    }
    if (mounted) {
      setState(() {
        _events.removeWhere((date, _) =>
            date.isAfter(start.subtract(const Duration(days: 1))) &&
            date.isBefore(end.add(const Duration(days: 1))));
        _events.addAll(events);
      });
    }
  }

  // Carregar eventos do mês para marcar no calendário
  Future<void> _loadMonthEvents() async {
    final monthKey = '${_focusedDay.year}-${_focusedDay.month}';
    if (_loadedMonths.contains(monthKey)) return;
    final startOfMonth = DateTime(_focusedDay.year, _focusedDay.month, 1)
        .subtract(const Duration(days: 35));
    final endOfMonth =
        DateTime(_focusedDay.year, _focusedDay.month + 1, 0, 23, 59, 59)
            .add(const Duration(days: 35));

    _loadedMonths.add(monthKey);
    _buildEventsFromCache(startOfMonth, endOfMonth);

    try {
      final snapshot = await sb.Supabase.instance.client
          .from('appointments')
          .select('id, scheduled_at, status')
          .eq('shop_id', widget.shopId)
          .neq('status', 'pre_reserva')
          .gte('scheduled_at', startOfMonth.toIso8601String())
          .lte('scheduled_at', endOfMonth.toIso8601String());

      final Map<DateTime, List<String>> events = {};
      for (var data in snapshot) {
        final rawSA = data['scheduled_at'];
        if (rawSA == null) continue;

        final status = (data['status'] ?? '').toString().toLowerCase();
        if (status == 'cancelado') continue;

        final date =
            rawSA is DateTime ? rawSA : DateTime.parse(rawSA.toString());
        final dateKey = DateTime(date.year, date.month, date.day);
        events[dateKey] = (events[dateKey] ?? [])..add(data['id'].toString());
      }

      if (mounted) {
        setState(() {
          _events.removeWhere((date, _) =>
              date.isAfter(startOfMonth.subtract(const Duration(days: 1))) &&
              date.isBefore(endOfMonth.add(const Duration(days: 1))));
          _events.addAll(events);
        });
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

  // 🗓 CARGA POR MÊS: carrega todos os agendamentos do mês exibido no calendário
  Future<void> _loadAppointmentsForMonth(DateTime month) async {
    if (_isLoading) return;

    final startOfMonth = DateTime(month.year, month.month, 1);
    final endOfMonth = DateTime(month.year, month.month + 1, 0, 23, 59, 59);

    // Stale-While-Revalidate: Busca no cache local primeiro
    final cachedForMonth = _docCache.values.where((doc) {
      final rawSA = doc['scheduled_at'];
      if (rawSA == null) return false;
      final date = rawSA is DateTime ? rawSA : DateTime.parse(rawSA.toString());
      final dateKey = DateTime(date.year, date.month, date.day);
      return !dateKey.isBefore(startOfMonth) && !dateKey.isAfter(endOfMonth);
    }).toList();

    cachedForMonth.sort((a, b) {
      final da = a['scheduled_at'] is DateTime
          ? a['scheduled_at']
          : DateTime.parse(a['scheduled_at'].toString());
      final db = b['scheduled_at'] is DateTime
          ? b['scheduled_at']
          : DateTime.parse(b['scheduled_at'].toString());
      return da.compareTo(db);
    });

    setState(() {
      // Se não tem cache, mostra o loading. Se tem, já exibe na tela enquanto busca no fundo.
      if (cachedForMonth.isEmpty) {
        _isLoading = true;
      }
      _appointments = List<Map<String, dynamic>>.from(cachedForMonth);
      _lastDocument = null;
      _firstDocument = null;
      _hasMore = true;
      _hasMorePast = true;
      _startFromSelectedDay = false;
      _showOnlySelectedDay = false;
      _startFromDate = startOfMonth;
      _weekEndDate = endOfMonth;
    });

    try {
      final snapshot = await sb.Supabase.instance.client
          .from('appointments')
          .select(_appointmentSelectCols)
          .eq('shop_id', widget.shopId)
          .neq('status', 'pre_reserva')
          .gte('scheduled_at', startOfMonth.toIso8601String())
          .lte('scheduled_at', endOfMonth.toIso8601String())
          .order('scheduled_at', ascending: true)
          .limit(_perPage);

      await _enrichClientNames(snapshot);
      if (mounted) {
        setState(() {
          // Clear cached items and replace with fresh data from server
          _appointments.clear();
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
        _resolveVipForAppointments(_appointments);
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
      var query = client
          .from('appointments')
          .select(_appointmentSelectCols)
          .eq('shop_id', widget.shopId)
          .neq('status', 'pre_reserva');

      // Simple implementation: load first page
      if (_startFromSelectedDay &&
          _startFromDate != null &&
          _weekEndDate != null) {
        query = query
            .gte('scheduled_at', _startFromDate!.toIso8601String())
            .lte('scheduled_at', _weekEndDate!.toIso8601String());
      } else if (_showOnlySelectedDay) {
        final start =
            DateTime(_selectedDay.year, _selectedDay.month, _selectedDay.day)
                .subtract(const Duration(days: 7));
        final end = DateTime(
                _selectedDay.year, _selectedDay.month, _selectedDay.day)
            .add(const Duration(days: 14, hours: 23, minutes: 59, seconds: 59));
        query = query
            .gte('scheduled_at', start.toIso8601String())
            .lte('scheduled_at', end.toIso8601String());
      } else {
        final start = DateTime(2020, 1, 1);
        query = query.gte('scheduled_at', start.toIso8601String());
      }

      final snapshot =
          await query.order('scheduled_at', ascending: true).limit(_perPage);

      await _enrichClientNames(snapshot);
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
        _resolveVipForAppointments(_appointments);
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
      final rawLastDate = _lastDocument!['scheduled_at'];
      final lastDate = rawLastDate is DateTime
          ? rawLastDate.toIso8601String()
          : rawLastDate.toString();

      var query = sb.Supabase.instance.client
          .from('appointments')
          .select(_appointmentSelectCols)
          .eq('shop_id', widget.shopId)
          .neq('status', 'pre_reserva')
          .gt('scheduled_at', lastDate);

      if (_weekEndDate != null) {
        query = query.lte('scheduled_at', _weekEndDate!.toIso8601String());
      }

      final snapshot =
          await query.order('scheduled_at', ascending: true).limit(_perPage);

      await _enrichClientNames(snapshot);
      if (mounted) {
        setState(() {
          if (snapshot.isNotEmpty) {
            _lastDocument = snapshot.last;
            for (var d in snapshot) {
              final id = d['id'].toString();
              _addToCache(d);
              final existingIdx =
                  _appointments.indexWhere((a) => a['id']?.toString() == id);
              if (existingIdx != -1) {
                _appointments[existingIdx] = d;
              } else {
                _appointments.add(d);
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

      final rawFirstDate = _firstDocument!['scheduled_at'];
      final firstDate = rawFirstDate is DateTime
          ? rawFirstDate.toIso8601String()
          : rawFirstDate.toString();

      var query = sb.Supabase.instance.client
          .from('appointments')
          .select(_appointmentSelectCols)
          .eq('shop_id', widget.shopId)
          .neq('status', 'pre_reserva')
          .lt('scheduled_at', firstDate);

      if (_startFromDate != null) {
        query = query.gte('scheduled_at', _startFromDate!.toIso8601String());
      }

      final snapshot =
          await query.order('scheduled_at', ascending: false).limit(_perPage);

      await _enrichClientNames(snapshot);
      if (mounted) {
        setState(() {
          if (snapshot.isNotEmpty) {
            // inserir na frente (reverter para ordem asc)
            final newDocs = snapshot.reversed.toList();
            for (var d in newDocs) {
              _addToCache(d);
            }
            // build merged list preserving order and updating existing entries
            final merged = <Map<String, dynamic>>[];
            for (var d in newDocs) {
              final id = d['id'].toString();
              final existingIdx =
                  _appointments.indexWhere((a) => a['id']?.toString() == id);
              if (existingIdx != -1) {
                _appointments[existingIdx] = d;
              } else {
                merged.add(d);
              }
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

  // Busca o nome real do cliente em users quando client_name foi salvo como email
  Future<void> _enrichClientNames(List<Map<String, dynamic>> list) async {
    final toFix = list.where((a) {
      final n = (a['client_name'] ?? '').toString();
      return n.contains('@') && !n.contains(' ') && a['client_id'] != null;
    }).toList();
    if (toFix.isEmpty) return;
    final ids = toFix.map((a) => a['client_id'].toString()).toSet().toList();
    try {
      final rows = await sb.Supabase.instance.client
          .from('users')
          .select('id, name')
          .inFilter('id', ids);
      final nameMap = <String, String>{};
      for (final r in rows) {
        final n = (r['name'] ?? '').toString().trim();
        if (n.isNotEmpty && !n.contains('@')) nameMap[r['id'].toString()] = n;
      }
      for (final appt in toFix) {
        final rn = nameMap[appt['client_id'].toString()];
        if (rn != null) appt['client_name'] = rn;
      }
    } catch (_) {}
  }

  Future<void> _loadShopVipClients() async {
    if (widget.shopId.isEmpty) return;
    try {
      final rows = await sb.Supabase.instance.client
          .from('shop_clients')
          .select('id, user_id, classification, manual_tags')
          .eq('shop_id', widget.shopId);

      final vips = <String>{};
      for (final row in (rows as List)) {
        final isVip = evaluateIsClientVip(
          shopClientClassification: row['classification']?.toString(),
          shopClientManualTags: row['manual_tags'] as List<dynamic>?,
        );
        if (!isVip) continue;
        final userId = (row['user_id'] ?? '').toString().trim();
        final id = (row['id'] ?? '').toString().trim();
        if (userId.isNotEmpty) vips.add(userId);
        if (id.isNotEmpty) vips.add(id);
      }

      if (vips.isNotEmpty && mounted) {
        setState(() {
          _vipClientIds.addAll(vips);
        });
      }
    } catch (_) {}
  }

  Future<void> _resolveVipForAppointments(
    List<Map<String, dynamic>> list, {
    bool forceRefresh = false,
  }) async {
    if (widget.shopId.isEmpty || list.isEmpty) return;
    final candidateIds = <String>[];
    for (final a in list) {
      final rawId =
          a['client_id'] ?? a['clientId'] ?? a['clienteId'] ?? a['userId'];
      final cid = rawId?.toString().trim() ?? '';
      if (cid.isEmpty) continue;
      if (forceRefresh ||
          (!_vipClientIds.contains(cid) &&
              !_checkedVipClientIds.contains(cid))) {
        if (!candidateIds.contains(cid)) {
          candidateIds.add(cid);
        }
      }
    }
    if (candidateIds.isEmpty) return;
    _checkedVipClientIds.addAll(candidateIds);

    try {
      final client = sb.Supabase.instance.client;
      final foundVips = <String>{};

      if (forceRefresh) {
        final scByUser = await client
            .from('shop_clients')
            .select('id, user_id, classification, manual_tags')
            .eq('shop_id', widget.shopId)
            .inFilter('user_id', candidateIds);
        final scById = await client
            .from('shop_clients')
            .select('id, user_id, classification, manual_tags')
            .eq('shop_id', widget.shopId)
            .inFilter('id', candidateIds);

        for (final row in <dynamic>[...scByUser, ...scById]) {
          final isVip = evaluateIsClientVip(
            shopClientClassification: row['classification']?.toString(),
            shopClientManualTags: row['manual_tags'] as List<dynamic>?,
          );
          if (!isVip) continue;
          final userId = (row['user_id'] ?? '').toString().trim();
          final id = (row['id'] ?? '').toString().trim();
          if (userId.isNotEmpty) foundVips.add(userId);
          if (id.isNotEmpty) foundVips.add(id);
        }
      }

      final userRows = await client
          .from('users')
          .select('id, is_vip')
          .inFilter('id', candidateIds)
          .eq('is_vip', true);
      for (final row in (userRows as List)) {
        final uid = (row['id'] ?? '').toString().trim();
        if (uid.isNotEmpty) foundVips.add(uid);
      }

      final remainingIds = candidateIds
          .where((id) =>
              !foundVips.contains(id) &&
              (forceRefresh || !_vipClientIds.contains(id)))
          .toList();

      if (remainingIds.isNotEmpty) {
        final vipMinVisits =
            (_shopConfig['vip_min_visits'] as num?)?.toInt() ?? 15;
        final sumidoMaxDays =
            (_shopConfig['sumido_max_days'] as num?)?.toInt() ?? 45;

        final apptRows = await client
            .from('appointments')
            .select('client_id, scheduled_at, status')
            .eq('shop_id', widget.shopId)
            .inFilter('client_id', remainingIds);

        final visitsByClient = <String, int>{};
        final lastVisitByClient = <String, DateTime>{};
        for (final row in (apptRows as List)) {
          final cid = (row['client_id'] ?? '').toString().trim();
          if (cid.isEmpty) continue;
          final status = (row['status'] ?? '').toString().toLowerCase();
          if (status == 'cancelado' ||
              status == 'recusado' ||
              status == 'excluido') {
            continue;
          }
          final dt = DateTime.tryParse(row['scheduled_at']?.toString() ?? '');
          if (dt == null) continue;
          visitsByClient[cid] = (visitsByClient[cid] ?? 0) + 1;
          final prev = lastVisitByClient[cid];
          if (prev == null || dt.isAfter(prev)) {
            lastVisitByClient[cid] = dt;
          }
        }

        final now = DateTime.now();
        for (final cid in remainingIds) {
          final isAutoVip = evaluateIsClientVip(
            validVisits: visitsByClient[cid] ?? 0,
            lastValidVisit: lastVisitByClient[cid],
            vipMinVisits: vipMinVisits,
            sumidoMaxDays: sumidoMaxDays,
            now: now,
          );
          if (isAutoVip) {
            foundVips.add(cid);
          }
        }
      }

      bool changed = false;
      if (forceRefresh) {
        for (final cid in candidateIds) {
          final shouldBeVip = foundVips.contains(cid);
          if (shouldBeVip && _vipClientIds.add(cid)) changed = true;
          if (!shouldBeVip && _vipClientIds.remove(cid)) changed = true;
        }
      } else {
        for (final cid in foundVips) {
          if (_vipClientIds.add(cid)) changed = true;
        }
      }

      if (changed && mounted) {
        setState(() {});
      }
    } catch (_) {}
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

    // Obter com seguranca se o layout é desktop
    final bool isDesktop = MediaQuery.of(context).size.width > 900;

    setState(() {
      _selectedDay = now;
      _focusedDay = now;
      _showOnlySelectedDay = isDesktop;
      _startFromSelectedDay = true;
      _startFromDate = DateTime(now.year, now.month, now.day);
      _weekEndDate = isDesktop
          ? DateTime(now.year, now.month, now.day, 23, 59, 59)
          : DateTime(
              endOfWeek.year, endOfWeek.month, endOfWeek.day, 23, 59, 59);
    });
    _applyWeekFilterToCache();
    final fetchStart = isDesktop
        ? _startFromDate!
        : DateTime(startOfWeek.year, startOfWeek.month, startOfWeek.day);
    _fetchWeekFromServer(fetchStart, _weekEndDate!);
  }

  // 📍 Scroll automático até o topo (dia selecionado é sempre o primeiro item da lista)
  void _scrollToSelectedDay() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            0.0,
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeInOut,
          );
        }
      } catch (_) {}
    });
  }

  // 📍 Scroll automático até um agendamento específico com destaque visual
  void _scrollToAppointment(String appointmentId) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final key = _appointmentKeys[appointmentId];
      if (key?.currentContext != null) {
        Scrollable.ensureVisible(
          key!.currentContext!,
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeInOut,
          alignment: 0.05,
        );
        setState(() => _highlightedAppointmentId = appointmentId);
        Future.delayed(const Duration(seconds: 3), () {
          if (mounted) setState(() => _highlightedAppointmentId = null);
        });
      } else {
        _scrollToSelectedDay();
      }
    });
  }

  // 💰 Recalcula faturamento semanal a partir dos agendamentos já carregados
  void _updateWeeklyRevenueFromAppointments() {
    double sum = 0;
    for (final d in _appointments) {
      if ((d['status'] ?? '').toString().toLowerCase() == 'cancelado') continue;
      sum += _getDisplayTotal(d);
    }
    if (mounted) {
      setState(() => _weeklyRevenue = sum);
    }
  }

  // âœ ï¸  EDITAR AGENDAMENTO
  // ignore: unused_element
  void _showEditDialog(Map<String, dynamic> data) {
    final TextEditingController nameController = TextEditingController(
        text: data['client_name'] ?? data['client_nome'] ?? '');
    String? selectedServiceId = data['service_id']?.toString();
    String selectedServiceName =
        data['service_name'] ?? data['servico_nome'] ?? '';
    String? selectedProfessionalId = data['professional_id']?.toString();
    String selectedProfessionalName =
        data['professional_name'] ?? data['profissional_nome'] ?? 'Selecione';
    double selectedServicePrice = _safeParseValue(data);

    final TextEditingController valueController = TextEditingController(
        text: selectedServicePrice.toStringAsFixed(2).replaceAll('.', ','));
    final TextEditingController paidController = TextEditingController(
        text: (data['valor_pago']?.toString() ?? '0').replaceAll('.', ','));

    final rawSA = data['scheduled_at'];
    DateTime appointmentDate =
        rawSA is DateTime ? rawSA : DateTime.parse(rawSA.toString());
    TimeOfDay appointmentTime = TimeOfDay.fromDateTime(appointmentDate);
    String selectedStatus =
        data['status']?.toString().toLowerCase() ?? 'pendente';

    // Pré-carregar serviços FORA do builder para evitar recriação a cada setModalState
    final Future<List<Map<String, dynamic>>> servicesFuture = sb
        .Supabase.instance.client
        .from('services')
        .select()
        .eq('shop_id', widget.shopId)
        .then((dynamic raw) {
      final list = List<Map<String, dynamic>>.from(raw as List);
      return list
        ..sort((a, b) => (a['name'] ?? a['nome'] ?? '')
            .toString()
            .compareTo((b['name'] ?? b['nome'] ?? '').toString()));
    });

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
                    FutureBuilder<List<Map<String, dynamic>>>(
                      future: servicesFuture,
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
                                    child: ValueListenableBuilder<bool>(
                                      valueListenable: PrivacyService
                                          .instance.isHiddenNotifier,
                                      builder: (context, isHidden, _) => Text(isHidden
                                          ? '${sData['name'] ?? sData['nome']} - R\$ *****'
                                          : '${sData['name'] ?? sData['nome']} - R\$ ${sData['price'] ?? sData['preco']}'),
                                    ),
                                  );
                                }).toList(),
                                onChanged: (value) {
                                  if (value != null) {
                                    final service = services.firstWhere(
                                        (s) => s['id'].toString() == value);
                                    final sData = service;
                                    setModalState(() {
                                      selectedServiceId = value;
                                      selectedServiceName =
                                          sData['name'] ?? sData['nome'] ?? '';
                                      selectedServicePrice = (sData['price'] ??
                                              sData['preco'] ??
                                              0)
                                          .toDouble();
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
                                value: pros.any((p) =>
                                        p['id'].toString() ==
                                        selectedProfessionalId)
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
                                    final pro = pros.firstWhere(
                                        (p) => p['id'].toString() == value);
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
                              if (!empSnapshot.hasData) return const SizedBox();
                              final empData = empSnapshot.data ?? {};

                              int duration = int.tryParse(
                                      data['duration_min']?.toString() ??
                                          '30') ??
                                  30;

                              final wsEmp =
                                  WorkSchedule.fromEmployeeRow(empData);
                              final dayCfg =
                                  wsEmp.forWeekday(appointmentDate.weekday);
                              final startStr = dayCfg?.start ??
                                  (empData['work_start'] ??
                                      empData['start_time'] ??
                                      "08:00");
                              final endStr = dayCfg?.end ??
                                  (empData['work_end'] ??
                                      empData['end_time'] ??
                                      "18:00");
                              final breakI = dayCfg?.breakInterval == null
                                  ? null
                                  : {
                                      'start': dayCfg!.breakInterval!.startMin,
                                      'end': dayCfg.breakInterval!.endMin
                                    };
                              final slots =
                                  AvailabilityUtils.generateSmartSlots(
                                startStr: startStr,
                                endStr: endStr,
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
                                breakInterval: breakI,
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
                                  final isCurrent = appointmentTime.hour ==
                                          slotTime.hour &&
                                      appointmentTime.minute == slotTime.minute;

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
                                        borderRadius: BorderRadius.circular(8)),
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
                      Map<String, dynamic> extraUpdates = {};
                      if (selectedStatus == 'cancelado') {
                        final payload =
                            await CancellationHelper.getCancellationPayload(
                                context, data['id']);
                        if (payload == null)
                          return; // User aborted cancellation
                        extraUpdates = payload;
                      } else {
                        extraUpdates = {'status': selectedStatus};
                      }

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
                        'scheduled_at': appointmentDate.toIso8601String(),
                        ...extraUpdates,
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

  void _showQuickEntryModal(
      {DateTime? initialDate, Map<String, dynamic>? appointment}) async {
    if (_isOpeningQuickEntry) return;
    _isOpeningQuickEntry = true;

    try {
      final Map<String, dynamic>? editData = appointment;

      // Controladores básicos alinhados com o esquema do banco de dados em inglês
      final String initialName = (editData?['client_name'] ?? '').toString();
      final TextEditingController nameController = TextEditingController(
          text: (initialName == 'null' || initialName == 'Null')
              ? ''
              : initialName);

      final String initialPhone = (editData?['client_phone'] ?? '').toString();
      final String rawInitialPhone =
          (initialPhone == 'null' || initialPhone == 'Null')
              ? ''
              : initialPhone.replaceAll(RegExp(r'\D'), '');

      // Formatter de telefone customizado: sempre aceita até 11 dígitos
      // e formata automaticamente como (XX) XXXXX-XXXX ou (XX) XXXX-XXXX.
      // Isso elimina o bug do MaskTextInputFormatter que truncava o 11º dígito.
      String _formatPhone(String digits) {
        if (digits.isEmpty) return '';
        if (digits.length <= 2) return '($digits';
        if (digits.length <= 6)
          return '(${digits.substring(0, 2)}) ${digits.substring(2)}';
        if (digits.length <= 10) {
          return '(${digits.substring(0, 2)}) ${digits.substring(2, 6)}-${digits.substring(6)}';
        }
        // 11 dígitos = celular
        return '(${digits.substring(0, 2)}) ${digits.substring(2, 7)}-${digits.substring(7)}';
      }

      final phoneFormatter =
          TextInputFormatter.withFunction((oldValue, newValue) {
        final digits = newValue.text.replaceAll(RegExp(r'\D'), '');
        if (digits.length > 11) {
          // Limita a 11 dígitos
          final limited = digits.substring(0, 11);
          final formatted = _formatPhone(limited);
          return TextEditingValue(
            text: formatted,
            selection: TextSelection.collapsed(offset: formatted.length),
          );
        }
        final formatted = _formatPhone(digits);
        return TextEditingValue(
          text: formatted,
          selection: TextSelection.collapsed(offset: formatted.length),
        );
      });

      final TextEditingController phoneController = TextEditingController(
        text: _formatPhone(rawInitialPhone),
      );

      final String initialService =
          (editData?['service_name'] ?? '').toString();
      final TextEditingController serviceController = TextEditingController(
          text: (initialService == 'null' || initialService == 'Null')
              ? ''
              : initialService);
      final TextEditingController valueController = TextEditingController();

      final String initialColor = (editData?['metadata'] is Map
              ? (editData!['metadata']['cor'] ?? '')
              : '')
          .toString();
      final TextEditingController colorController = TextEditingController(
          text: (initialColor == 'null' || initialColor == 'Null')
              ? ''
              : initialColor);

      // Estado do Modal
      String? selectedClientId =
          editData?['client_id'] ?? editData?['clientId'];
      String? serviceId = editData?['service_id'] ?? editData?['servicoId'];
      int durationMin =
          editData?['duration_min'] ?? editData?['duracao_min'] ?? 30;
      String? selectedProfessionalId =
          editData?['professional_id'] ?? editData?['profissionalId'];
      String selectedProfessionalName = editData?['professional_name'] ??
          editData?['profissional_nome'] ??
          'Selecione Profissional';
      DateTime manualDate = initialDate ?? _selectedDay;
      TimeOfDay manualTime = TimeOfDay.now();

      String rawValue = (editData?['payment_method'] ?? '').toString().trim();
      String paymentMethodFromDb = rawValue.toLowerCase();
      String selectedPaymentMethod =
          rawValue.isNotEmpty ? rawValue : 'Pessoalmente';
      if (paymentMethodFromDb == 'pix') selectedPaymentMethod = 'Pix';
      if (paymentMethodFromDb == 'cartão' ||
          paymentMethodFromDb == 'cartao' ||
          paymentMethodFromDb == 'card') selectedPaymentMethod = 'Cartão';
      if (paymentMethodFromDb == 'pessoalmente' ||
          paymentMethodFromDb == 'no local' ||
          paymentMethodFromDb == 'local')
        selectedPaymentMethod = 'Pessoalmente';

      PaymentSummary? editSummary;
      bool hasProtectedOrPartialPayment = false;
      bool isPaid = false;
      double? originalModalValue;

      if (editData != null) {
        final rawSAEdit = editData['scheduled_at'];
        if (rawSAEdit != null) {
          manualDate = rawSAEdit is DateTime
              ? rawSAEdit
              : DateTime.parse(rawSAEdit.toString());
          manualTime = TimeOfDay.fromDateTime(manualDate);
        }
        double val = _safeParseValue(appointment!);
        originalModalValue = val;
        valueController.text =
            val > 0 ? val.toString().replaceAll('.', ',') : '';

        editSummary = getPaymentSummary(editData);
        hasProtectedOrPartialPayment =
            editSummary.hasOnlinePayment || editSummary.status == 'parcial';
        isPaid = editSummary.status == 'pago';
      }

      // --- REVISÃO / INTELIGÊNCIA INICIAL ---
      Map<String, dynamic>? suggestedService;
      Map<String, dynamic>? suggestedProfessional;
      bool isServiceConfirmed = false;
      bool isProfessionalConfirmed = false;
      bool isIntelligentLoading = (editData ==
          null); // Só carregar inteligência para novos agendamentos

      if (!mounted) {
        _isOpeningQuickEntry = false;
        return;
      }

      // Pré-carregar serviços FORA do builder para evitar recriação a cada setModalState
      final Future<List<Map<String, dynamic>>> servicesFuture = sb
          .Supabase.instance.client
          .from('services')
          .select()
          .eq('shop_id', widget.shopId)
          .then((dynamic raw) {
        final list = List<Map<String, dynamic>>.from(raw as List);
        return list
          ..sort((a, b) => (a['name'] ?? a['nome'] ?? '')
              .toString()
              .compareTo((b['name'] ?? b['nome'] ?? '').toString()));
      });

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
                    if (serviceId == null &&
                        serviceController.text.isNotEmpty) {
                      suggestedService = await TransactionAutocompleteService
                          .findBestMatchingService(
                        shopId: widget.shopId,
                        rawName: serviceController.text,
                      );
                    }

                    // 2. Sugestão de Profissional
                    if (selectedProfessionalId == null) {
                      final candidates =
                          await TransactionAutocompleteService.getCandidates(
                        shopId: widget.shopId,
                        serviceId:
                            serviceId ?? suggestedService?['id']?.toString(),
                      );

                      List<Map<String, dynamic>> availableCands = [];
                      for (var cand in candidates) {
                        bool ok = await TransactionAutocompleteService
                            .isProfessionalAvailable(
                          employeeId: cand['id'].toString(),
                          targetDate: manualDate,
                          durationMin: durationMin,
                          excludeDocId: appointment?['id']?.toString(),
                        );
                        if (ok) availableCands.add(cand);
                      }

                      if (availableCands.isNotEmpty) {
                        final ranked = await TransactionAutocompleteService
                            .rankCandidatesByWorkload(
                          shopId: widget.shopId,
                          candidates: availableCands,
                          targetMonth: manualDate,
                        );
                        suggestedProfessional = ranked.first;

                        // Aplicar sugestão automaticamente se o usuário não escolheu nada ainda
                        if (selectedProfessionalId == null) {
                          selectedProfessionalId =
                              suggestedProfessional?['id']?.toString();
                          selectedProfessionalName =
                              suggestedProfessional?['name'] ??
                                  suggestedProfessional?['nome'] ??
                                  'Profissional';
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
                padding: EdgeInsets.only(
                    bottom: MediaQuery.of(context).viewInsets.bottom +
                        MediaQuery.of(context).padding.bottom +
                        10),
                child: Container(
                  height: MediaQuery.of(context).size.height * 0.75,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(20),
                        topRight: Radius.circular(20)),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Header
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          border: Border(
                              bottom: BorderSide(color: Colors.grey.shade100)),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                                appointment == null
                                    ? "Lançamento Rápido"
                                    : "Editar Agendamento",
                                style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.primaryPurple)),
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
                          padding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Data e Horário
                              const Text('Data e Horário',
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 11,
                                      color: Colors.grey)),
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
                                          setModalState(
                                              () => manualDate = picked);
                                        }
                                      },
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 12, vertical: 10),
                                        decoration: BoxDecoration(
                                          border: Border.all(
                                              color: Colors.grey.shade200),
                                          borderRadius:
                                              BorderRadius.circular(8),
                                          color: Colors.grey.shade50,
                                        ),
                                        child: Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceBetween,
                                          children: [
                                            Text(
                                              DateFormat('dd/MM/yyyy')
                                                  .format(manualDate),
                                              style: const TextStyle(
                                                  fontWeight: FontWeight.w600,
                                                  fontSize: 13),
                                            ),
                                            const Icon(Icons.calendar_today,
                                                size: 16,
                                                color: AppColors.primaryPurple),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: InkWell(
                                      onTap: () async {
                                        final picked = await showTimePicker(
                                            context: context,
                                            initialTime: manualTime);
                                        if (picked != null) {
                                          setModalState(
                                              () => manualTime = picked);
                                        }
                                      },
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 12, vertical: 10),
                                        decoration: BoxDecoration(
                                          border: Border.all(
                                              color: Colors.grey.shade200),
                                          borderRadius:
                                              BorderRadius.circular(8),
                                          color: Colors.grey.shade50,
                                        ),
                                        child: Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceBetween,
                                          children: [
                                            Text(
                                              manualTime.format(context),
                                              style: const TextStyle(
                                                  fontWeight: FontWeight.w600,
                                                  fontSize: 13),
                                            ),
                                            const Icon(Icons.access_time,
                                                size: 16,
                                                color: AppColors.primaryPurple),
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
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 11,
                                      color: Colors.grey)),
                              const SizedBox(height: 4),
                              LayoutBuilder(builder: (context, constraints) {
                                TextEditingController? capturedNameCtrl;
                                return Autocomplete<Map<String, dynamic>>(
                                  initialValue: TextEditingValue(
                                      text: nameController.text),
                                  optionsBuilder: (TextEditingValue
                                      textEditingValue) async {
                                    // Sync nameController so save reads the correct text
                                    nameController.text = textEditingValue.text;
                                    return await TransactionAutocompleteService
                                        .findRecentClients(
                                      shopId: widget.shopId,
                                      search: textEditingValue.text,
                                    );
                                  },
                                  displayStringForOption: (option) =>
                                      option['name'] ?? '',
                                  onSelected: (option) {
                                    setModalState(() {
                                      nameController.text =
                                          option['name'] ?? '';
                                      final selPhone = (option['phone'] ?? '')
                                          .toString()
                                          .replaceAll(RegExp(r'\D'), '');
                                      phoneController.text =
                                          _formatPhone(selPhone);
                                      selectedClientId = option['id'];
                                      if (capturedNameCtrl != null) {
                                        capturedNameCtrl!.text =
                                            option['name'] ?? '';
                                      }
                                    });
                                  },
                                  fieldViewBuilder: (context, controller,
                                      focusNode, onFieldSubmitted) {
                                    capturedNameCtrl = controller;
                                    // Sync the Autocomplete controller on first build
                                    if (controller.text.isEmpty &&
                                        nameController.text.isNotEmpty) {
                                      controller.text = nameController.text;
                                    }
                                    // Make nameController always reflect what user typed
                                    controller.addListener(() {
                                      if (nameController.text !=
                                          controller.text) {
                                        nameController.text = controller.text;
                                      }
                                    });
                                    return SizedBox(
                                      height: 40,
                                      child: TextField(
                                        controller: controller,
                                        focusNode: focusNode,
                                        textCapitalization:
                                            TextCapitalization.words,
                                        style: const TextStyle(fontSize: 14),
                                        decoration: InputDecoration(
                                          hintText: 'Nome do cliente',
                                          filled: true,
                                          fillColor: Colors.grey.shade50,
                                          prefixIcon: const Icon(
                                              Icons.person_outline,
                                              size: 18),
                                          contentPadding:
                                              const EdgeInsets.symmetric(
                                                  horizontal: 12),
                                          border: OutlineInputBorder(
                                            borderRadius:
                                                BorderRadius.circular(8),
                                            borderSide: BorderSide(
                                                color: Colors.grey.shade200),
                                          ),
                                          enabledBorder: OutlineInputBorder(
                                            borderRadius:
                                                BorderRadius.circular(8),
                                            borderSide: BorderSide(
                                                color: Colors.grey.shade200),
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                  optionsViewBuilder:
                                      (context, onSelected, options) {
                                    return Align(
                                      alignment: Alignment.topLeft,
                                      child: Material(
                                        elevation: 4,
                                        borderRadius: BorderRadius.circular(8),
                                        child: Container(
                                          width: constraints.maxWidth,
                                          constraints: const BoxConstraints(
                                              maxHeight: 200),
                                          child: ListView.builder(
                                            padding: EdgeInsets.zero,
                                            shrinkWrap: true,
                                            itemCount: options.length,
                                            itemBuilder: (context, index) {
                                              final option =
                                                  options.elementAt(index);
                                              final hasId =
                                                  option['id'] != null;
                                              return ListTile(
                                                dense: true,
                                                leading: Icon(
                                                  hasId
                                                      ? Icons.verified_user
                                                      : Icons.person_outline,
                                                  size: 20,
                                                  color: hasId
                                                      ? Colors.blue
                                                      : Colors.grey,
                                                ),
                                                title: Text(
                                                    option['name'] ?? '',
                                                    style: const TextStyle(
                                                        fontSize: 13,
                                                        fontWeight:
                                                            FontWeight.bold)),
                                                subtitle: Text(
                                                    option['phone'] ??
                                                        'Sem telefone',
                                                    style: const TextStyle(
                                                        fontSize: 11)),
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
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 11,
                                      color: Colors.grey)),
                              const SizedBox(height: 4),
                              SizedBox(
                                height: 40,
                                child: TextField(
                                  controller: phoneController,
                                  keyboardType: TextInputType.phone,
                                  inputFormatters: [phoneFormatter],
                                  style: const TextStyle(fontSize: 14),
                                  decoration: InputDecoration(
                                    hintText: 'Telefone do cliente',
                                    filled: true,
                                    fillColor: Colors.grey.shade50,
                                    prefixIcon: const Icon(Icons.phone_outlined,
                                        size: 18),
                                    contentPadding: const EdgeInsets.symmetric(
                                        horizontal: 12),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                      borderSide: BorderSide(
                                          color: Colors.grey.shade200),
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                      borderSide: BorderSide(
                                          color: Colors.grey.shade200),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 10),
                              // Profissional
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text('Profissional',
                                      style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 11,
                                          color: Colors.grey)),
                                  if (suggestedProfessional != null &&
                                      !isProfessionalConfirmed &&
                                      selectedProfessionalId == null)
                                    GestureDetector(
                                      onTap: () {
                                        final pData = suggestedProfessional!;
                                        setModalState(() {
                                          selectedProfessionalId =
                                              pData['id'].toString();
                                          selectedProfessionalName =
                                              pData['name'] ?? '';
                                          isProfessionalConfirmed = true;
                                        });
                                      },
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: Colors.blue.shade50,
                                          borderRadius:
                                              BorderRadius.circular(12),
                                          border: Border.all(
                                              color: Colors.blue.shade100),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(Icons.auto_awesome,
                                                size: 10, color: Colors.blue),
                                            const SizedBox(width: 4),
                                            Text(
                                                "Sugerir: ${suggestedProfessional!['name']}",
                                                style: const TextStyle(
                                                    fontSize: 10,
                                                    color: Colors.blue,
                                                    fontWeight:
                                                        FontWeight.bold)),
                                          ],
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              StreamBuilder<List<Map<String, dynamic>>>(
                                stream: _employeesStream,
                                initialData: _professionals,
                                builder: (context, snapshot) {
                                  if (!snapshot.hasData)
                                    return const SizedBox(height: 40);
                                  final pros = snapshot.data!;

                                  return LayoutBuilder(
                                      builder: (context, constraints) {
                                    return Autocomplete<Map<String, dynamic>>(
                                      initialValue: TextEditingValue(
                                          text: selectedProfessionalId != null
                                              ? selectedProfessionalName
                                              : ''),
                                      optionsBuilder:
                                          (TextEditingValue textEditingValue) {
                                        // LOJA: exibe TODOS os profissionais (sem filtro por habilitacao).
                                        // O filtro so se aplica ao booking do cliente.
                                        if (textEditingValue.text.isEmpty)
                                          return pros;
                                        return pros.where((p) =>
                                            (p['name'] ?? '')
                                                .toString()
                                                .toLowerCase()
                                                .contains(textEditingValue.text
                                                    .toLowerCase()));
                                      },
                                      displayStringForOption: (option) =>
                                          option['name'] ?? '',
                                      onSelected: (option) {
                                        setModalState(() {
                                          selectedProfessionalId =
                                              option['id'].toString();
                                          selectedProfessionalName =
                                              option['name'] ?? '';
                                          isProfessionalConfirmed = true;
                                        });
                                      },
                                      fieldViewBuilder: (context, controller,
                                          focusNode, onFieldSubmitted) {
                                        if (selectedProfessionalId != null &&
                                            controller.text !=
                                                selectedProfessionalName &&
                                            !focusNode.hasFocus) {
                                          controller.text =
                                              selectedProfessionalName;
                                        }
                                        return SizedBox(
                                          height: 40,
                                          child: TextField(
                                            controller: controller,
                                            focusNode: focusNode,
                                            style:
                                                const TextStyle(fontSize: 14),
                                            decoration: InputDecoration(
                                              hintText:
                                                  'Buscar profissional...',
                                              filled: true,
                                              fillColor: Colors.grey.shade50,
                                              contentPadding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 12),
                                              border: OutlineInputBorder(
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                                borderSide: BorderSide(
                                                    color:
                                                        Colors.grey.shade200),
                                              ),
                                              enabledBorder: OutlineInputBorder(
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                                borderSide: BorderSide(
                                                    color:
                                                        Colors.grey.shade200),
                                              ),
                                              suffixIcon: controller
                                                      .text.isNotEmpty
                                                  ? IconButton(
                                                      icon: const Icon(
                                                          Icons.clear,
                                                          size: 16),
                                                      onPressed: () {
                                                        controller.clear();
                                                        setModalState(() {
                                                          selectedProfessionalId =
                                                              null;
                                                          selectedProfessionalName =
                                                              'Selecione...';
                                                        });
                                                      },
                                                    )
                                                  : const Icon(
                                                      Icons.arrow_drop_down),
                                            ),
                                            onChanged: (v) {
                                              if (v.isEmpty) {
                                                setModalState(() {
                                                  selectedProfessionalId = null;
                                                  selectedProfessionalName =
                                                      'Selecione...';
                                                });
                                              }
                                            },
                                          ),
                                        );
                                      },
                                      optionsViewBuilder:
                                          (context, onSelected, options) {
                                        return Align(
                                          alignment: Alignment.topLeft,
                                          child: Material(
                                            elevation: 4,
                                            borderRadius:
                                                BorderRadius.circular(8),
                                            child: Container(
                                              width: constraints.maxWidth,
                                              constraints: const BoxConstraints(
                                                  maxHeight: 200),
                                              child: ListView.builder(
                                                padding: EdgeInsets.zero,
                                                shrinkWrap: true,
                                                itemCount: options.length,
                                                itemBuilder:
                                                    (BuildContext context,
                                                        int index) {
                                                  final option =
                                                      options.elementAt(index);
                                                  // Indica visualmente profissionais nao habilitados para o servico
                                                  final List<dynamic>
                                                      habilitados =
                                                      option['services_ids']
                                                              as List? ??
                                                          option['servicos_habilidade']
                                                              as List? ??
                                                          [];
                                                  final bool isApto =
                                                      serviceId == null ||
                                                          habilitados.isEmpty ||
                                                          habilitados
                                                              .map((id) =>
                                                                  id.toString())
                                                              .contains(serviceId
                                                                  .toString());
                                                  return ListTile(
                                                    dense: true,
                                                    title: Row(
                                                      children: [
                                                        Flexible(
                                                          child: Text(
                                                              option['name'] ??
                                                                  '',
                                                              style:
                                                                  const TextStyle(
                                                                      fontSize:
                                                                          13)),
                                                        ),
                                                        if (!isApto) ...[
                                                          const SizedBox(
                                                              width: 4),
                                                          Container(
                                                            padding:
                                                                const EdgeInsets
                                                                    .symmetric(
                                                                    horizontal:
                                                                        4,
                                                                    vertical:
                                                                        1),
                                                            decoration:
                                                                BoxDecoration(
                                                              color: Colors
                                                                  .orange
                                                                  .withValues(
                                                                      alpha:
                                                                          0.15),
                                                              borderRadius:
                                                                  BorderRadius
                                                                      .circular(
                                                                          4),
                                                              border: Border.all(
                                                                  color: Colors
                                                                      .orange
                                                                      .withValues(
                                                                          alpha:
                                                                              0.4)),
                                                            ),
                                                            child: const Text(
                                                              '\u26a0\ufe0f Nao hab.',
                                                              style: TextStyle(
                                                                  fontSize: 9,
                                                                  color: Colors
                                                                      .orange,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .bold),
                                                            ),
                                                          ),
                                                        ],
                                                      ],
                                                    ),
                                                    onTap: () =>
                                                        onSelected(option),
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
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text('Serviço',
                                      style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 11,
                                          color: Colors.grey)),
                                  if (suggestedService != null &&
                                      !isServiceConfirmed &&
                                      serviceId == null)
                                    GestureDetector(
                                      onTap: () {
                                        final sData = suggestedService!;
                                        setModalState(() {
                                          serviceId = sData['id'].toString();
                                          serviceController.text =
                                              sData['name'] ?? '';
                                          valueController.text =
                                              (sData['price'] ?? 0)
                                                  .toString()
                                                  .replaceAll('.', ',');
                                          durationMin =
                                              (sData['duration_min'] ?? 30);
                                          isServiceConfirmed = true;
                                        });
                                      },
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: Colors.green.shade50,
                                          borderRadius:
                                              BorderRadius.circular(12),
                                          border: Border.all(
                                              color: Colors.green.shade100),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(Icons.auto_awesome,
                                                size: 10, color: Colors.green),
                                            const SizedBox(width: 4),
                                            Text(
                                                "Completar: ${suggestedService!['name']}",
                                                style: const TextStyle(
                                                    fontSize: 10,
                                                    color: Colors.green,
                                                    fontWeight:
                                                        FontWeight.bold)),
                                          ],
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              FutureBuilder<List<Map<String, dynamic>>>(
                                future: servicesFuture,
                                builder: (context, snapshot) {
                                  if (!snapshot.hasData)
                                    return const SizedBox(height: 40);
                                  final allServices = snapshot.data!
                                      .where((s) =>
                                          s['is_active'] == null ||
                                          s['is_active'] == true)
                                      .toList();

                                  return LayoutBuilder(
                                      builder: (context, constraints) {
                                    return Autocomplete<Map<String, dynamic>>(
                                      initialValue: TextEditingValue(
                                          text: serviceController.text),
                                      optionsBuilder:
                                          (TextEditingValue textEditingValue) {
                                        if (textEditingValue.text.isEmpty)
                                          return allServices;
                                        return allServices.where((s) =>
                                            s['name']
                                                .toString()
                                                .toLowerCase()
                                                .contains(textEditingValue.text
                                                    .toLowerCase()));
                                      },
                                      displayStringForOption: (option) =>
                                          option['name'] ?? '',
                                      onSelected: (option) {
                                        setModalState(() {
                                          serviceId = option['id'].toString();
                                          serviceController.text =
                                              option['name'] ?? '';
                                          valueController.text =
                                              (option['price'] ?? 0)
                                                  .toString()
                                                  .replaceAll('.', ',');
                                          durationMin =
                                              (option['duration_min'] ?? 30);
                                        });
                                      },
                                      fieldViewBuilder: (context, controller,
                                          focusNode, onFieldSubmitted) {
                                        // Sincronizar o controlador interno do Autocomplete com o valor inicial DE FORMA AGRESSIVA
                                        if (controller.text.isEmpty &&
                                            serviceController.text.isNotEmpty) {
                                          Future.microtask(() => controller
                                              .text = serviceController.text);
                                        }
                                        return SizedBox(
                                          height: 40,
                                          child: TextField(
                                            controller: controller,
                                            focusNode: focusNode,
                                            style:
                                                const TextStyle(fontSize: 14),
                                            decoration: InputDecoration(
                                              hintText: 'Buscar serviço...',
                                              filled: true,
                                              fillColor: Colors.grey.shade50,
                                              contentPadding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 12),
                                              border: OutlineInputBorder(
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                                borderSide: BorderSide(
                                                    color:
                                                        Colors.grey.shade200),
                                              ),
                                              enabledBorder: OutlineInputBorder(
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                                borderSide: BorderSide(
                                                    color:
                                                        Colors.grey.shade200),
                                              ),
                                              suffixIcon:
                                                  controller.text.isNotEmpty
                                                      ? IconButton(
                                                          icon: const Icon(
                                                              Icons.clear,
                                                              size: 16),
                                                          onPressed: () {
                                                            controller.clear();
                                                            setModalState(() {
                                                              serviceId = null;
                                                              serviceController
                                                                  .clear();
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
                                                TransactionAutocompleteService
                                                    .findBestMatchingService(
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
                                      optionsViewBuilder:
                                          (context, onSelected, options) {
                                        return Align(
                                          alignment: Alignment.topLeft,
                                          child: Material(
                                            elevation: 4,
                                            borderRadius:
                                                BorderRadius.circular(8),
                                            child: Container(
                                              width: constraints.maxWidth,
                                              constraints: const BoxConstraints(
                                                  maxHeight: 200),
                                              child: ListView.builder(
                                                padding: EdgeInsets.zero,
                                                shrinkWrap: true,
                                                itemCount: options.length,
                                                itemBuilder:
                                                    (BuildContext context,
                                                        int index) {
                                                  final option =
                                                      options.elementAt(index);
                                                  return ListTile(
                                                    dense: true,
                                                    title: Text(
                                                        option['name'] ??
                                                            option['nome'] ??
                                                            '',
                                                        style: const TextStyle(
                                                            fontSize: 13)),
                                                    subtitle:
                                                        ValueListenableBuilder<
                                                            bool>(
                                                      valueListenable:
                                                          PrivacyService
                                                              .instance
                                                              .isHiddenNotifier,
                                                      builder: (context,
                                                              isHidden, _) =>
                                                          Text(
                                                              isHidden
                                                                  ? 'R\$ *****'
                                                                  : 'R\$ ${option['price'] ?? option['preco']}',
                                                              style:
                                                                  const TextStyle(
                                                                      fontSize:
                                                                          11)),
                                                    ),
                                                    onTap: () =>
                                                        onSelected(option),
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
                              if (_isTrancistaShop) ...[
                                const Text('Cor das Tranças (Opcional)',
                                    style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 11,
                                        color: Colors.grey)),
                                const SizedBox(height: 4),
                                SizedBox(
                                  height: 40,
                                  child: TextField(
                                    controller: colorController,
                                    style: const TextStyle(fontSize: 14),
                                    decoration: InputDecoration(
                                      hintText:
                                          'Ex: Preto 1B, Castanho, Mel, 613, Marsala...',
                                      prefixIcon: const Icon(
                                          Icons.palette_outlined,
                                          size: 18),
                                      filled: true,
                                      fillColor: Colors.grey.shade50,
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                              horizontal: 12),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8),
                                        borderSide: BorderSide(
                                            color: Colors.grey.shade200),
                                      ),
                                      enabledBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8),
                                        borderSide: BorderSide(
                                            color: Colors.grey.shade200),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 10),
                              ],
                              // Valor
                              const Text('Valor (R\$)',
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 11,
                                      color: Colors.grey)),
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
                                    contentPadding: const EdgeInsets.symmetric(
                                        horizontal: 12),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                      borderSide: BorderSide(
                                          color: Colors.grey.shade200),
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                      borderSide: BorderSide(
                                          color: Colors.grey.shade200),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 10),
                              // Método de Pagamento e Status
                              const Text('Forma de Pagamento',
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 11,
                                      color: Colors.grey)),
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  _paymentMethodChip(
                                    label: "Pix",
                                    icon: Icons.pix,
                                    isSelected: selectedPaymentMethod == 'Pix',
                                    onTap: () => setModalState(
                                        () => selectedPaymentMethod = 'Pix'),
                                  ),
                                  const SizedBox(width: 8),
                                  _paymentMethodChip(
                                    label: "Cartão",
                                    icon: Icons.credit_card,
                                    isSelected:
                                        selectedPaymentMethod == 'Cartão',
                                    onTap: () => setModalState(
                                        () => selectedPaymentMethod = 'Cartão'),
                                  ),
                                  const SizedBox(width: 8),
                                  _paymentMethodChip(
                                    label: "Pessoalmente",
                                    icon: Icons.person_pin_circle_outlined,
                                    isSelected:
                                        selectedPaymentMethod == 'Pessoalmente',
                                    onTap: () => setModalState(() =>
                                        selectedPaymentMethod = 'Pessoalmente'),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              if (editData != null &&
                                  hasProtectedOrPartialPayment)
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 10),
                                  decoration: BoxDecoration(
                                    color: (editSummary?.status == 'pago'
                                            ? Colors.green
                                            : Colors.orange)
                                        .withValues(alpha: 0.08),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: (editSummary?.status == 'pago'
                                              ? Colors.green
                                              : Colors.orange)
                                          .withValues(alpha: 0.35),
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        editSummary?.status == 'pago'
                                            ? Icons.verified_outlined
                                            : Icons.payments_outlined,
                                        size: 18,
                                        color: editSummary?.status == 'pago'
                                            ? Colors.green.shade700
                                            : Colors.orange.shade800,
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              editSummary?.cardBadgeText ??
                                                  'PGTO. PARCIAL',
                                              style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 12,
                                                color: editSummary?.status ==
                                                        'pago'
                                                    ? Colors.green.shade800
                                                    : Colors.orange.shade900,
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              'Pagamento online/parcial — gerencie na tela de detalhes do agendamento.',
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: Colors.grey.shade700,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                )
                              else
                                Row(
                                  children: [
                                    Expanded(
                                      child: InkWell(
                                        onTap: () =>
                                            setModalState(() => isPaid = false),
                                        borderRadius: BorderRadius.circular(8),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                              vertical: 10),
                                          decoration: BoxDecoration(
                                            color: !isPaid
                                                ? Colors.orange
                                                    .withValues(alpha: 0.1)
                                                : Colors.grey.shade50,
                                            borderRadius:
                                                BorderRadius.circular(8),
                                            border: Border.all(
                                                color: !isPaid
                                                    ? Colors.orange
                                                        .withValues(alpha: 0.3)
                                                    : Colors.grey.shade200),
                                          ),
                                          child: Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: [
                                              Icon(Icons.hourglass_empty,
                                                  size: 16,
                                                  color: !isPaid
                                                      ? Colors.orange
                                                      : Colors.grey),
                                              const SizedBox(width: 6),
                                              const Text("Pendente",
                                                  style: TextStyle(
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      fontSize: 13)),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: InkWell(
                                        onTap: () =>
                                            setModalState(() => isPaid = true),
                                        borderRadius: BorderRadius.circular(8),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                              vertical: 10),
                                          decoration: BoxDecoration(
                                            color: isPaid
                                                ? Colors.green
                                                    .withValues(alpha: 0.1)
                                                : Colors.grey.shade50,
                                            borderRadius:
                                                BorderRadius.circular(8),
                                            border: Border.all(
                                                color: isPaid
                                                    ? Colors.green
                                                        .withValues(alpha: 0.3)
                                                    : Colors.grey.shade200),
                                          ),
                                          child: Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: [
                                              Icon(Icons.check_circle,
                                                  size: 16,
                                                  color: isPaid
                                                      ? Colors.green
                                                      : Colors.grey),
                                              const SizedBox(width: 6),
                                              const Text("Pago",
                                                  style: TextStyle(
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      fontSize: 13)),
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
                                        style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 11,
                                            color: Colors.grey)),
                                    const SizedBox(height: 6),
                                    FutureBuilder<List<Map<String, int>>>(
                                      future:
                                          AvailabilityUtils.getBusyIntervals(
                                              selectedProfessionalId!,
                                              manualDate,
                                              excludeDocId: appointment?['id']),
                                      builder: (context, busySnapshot) {
                                        if (!busySnapshot.hasData)
                                          return const SizedBox(height: 38);
                                        return FutureBuilder<
                                            Map<String, dynamic>?>(
                                          future: sb.Supabase.instance.client
                                              .from('employees')
                                              .select()
                                              .eq('id', selectedProfessionalId!)
                                              .maybeSingle(),
                                          builder: (context, empSnapshot) {
                                            if (!empSnapshot.hasData)
                                              return const SizedBox();
                                            final empData =
                                                empSnapshot.data ?? {};
                                            final wsEmp =
                                                WorkSchedule.fromEmployeeRow(
                                                    empData);
                                            final dayCfg = wsEmp
                                                .forWeekday(manualDate.weekday);
                                            final startStr = dayCfg?.start ??
                                                (empData['work_start'] ??
                                                    empData['start_time'] ??
                                                    "08:00");
                                            final endStr = dayCfg?.end ??
                                                (empData['work_end'] ??
                                                    empData['end_time'] ??
                                                    "18:00");
                                            final breakI =
                                                dayCfg?.breakInterval == null
                                                    ? null
                                                    : {
                                                        'start': dayCfg!
                                                            .breakInterval!
                                                            .startMin,
                                                        'end': dayCfg
                                                            .breakInterval!
                                                            .endMin
                                                      };
                                            final slots = AvailabilityUtils
                                                .generateSmartSlots(
                                              startStr: startStr,
                                              endStr: endStr,
                                              interval: _shopConfig[
                                                      'intervalo_agenda_min'] ??
                                                  30,
                                              serviceDuration: durationMin,
                                              busyIntervals: busySnapshot.data!,
                                              preventGaps: _shopConfig[
                                                      'evitar_buracos_agenda'] ??
                                                  false,
                                              minAdvanceHours: 0,
                                              selectedDate: manualDate,
                                              breakInterval: breakI,
                                            );
                                            if (slots.isEmpty)
                                              return const Text("Sem horários.",
                                                  style:
                                                      TextStyle(fontSize: 11));
                                            return SizedBox(
                                              height: 36,
                                              child: ListView.separated(
                                                scrollDirection:
                                                    Axis.horizontal,
                                                itemCount: slots.length,
                                                separatorBuilder: (_, __) =>
                                                    const SizedBox(width: 8),
                                                itemBuilder: (context, index) {
                                                  final slotStr = slots[index];
                                                  final parts =
                                                      slotStr.split(':');
                                                  final slotTime = TimeOfDay(
                                                      hour: int.parse(parts[0]),
                                                      minute:
                                                          int.parse(parts[1]));
                                                  final isCurrent =
                                                      manualTime.hour ==
                                                              slotTime.hour &&
                                                          manualTime.minute ==
                                                              slotTime.minute;
                                                  return ActionChip(
                                                    label: Text(slotStr,
                                                        style: TextStyle(
                                                            fontSize: 12,
                                                            color: isCurrent
                                                                ? Colors.white
                                                                : Colors
                                                                    .black87)),
                                                    onPressed: () =>
                                                        setModalState(() =>
                                                            manualTime =
                                                                slotTime),
                                                    backgroundColor: isCurrent
                                                        ? AppColors
                                                            .primaryPurple
                                                        : Colors.grey.shade100,
                                                    padding: EdgeInsets.zero,
                                                    side: BorderSide.none,
                                                    shape:
                                                        RoundedRectangleBorder(
                                                            borderRadius:
                                                                BorderRadius
                                                                    .circular(
                                                                        8)),
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
                                const Text(
                                    "Selecione um profissional para ver sugestões.",
                                    style: TextStyle(
                                        fontSize: 11, color: Colors.grey)),
                              const SizedBox(height: 16),
                              // Botão Salvar
                              SizedBox(
                                width: double.infinity,
                                height: 48,
                                child: ElevatedButton(
                                  onPressed: () async {
                                    if (nameController.text.isEmpty ||
                                        valueController.text.isEmpty) {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(const SnackBar(
                                              content: Text(
                                                  'Preencha nome e valor')));
                                      return;
                                    }
                                    if (selectedProfessionalId != null) {
                                      final conflicts =
                                          await _verifyBusinessRules(
                                        professionalId: selectedProfessionalId!,
                                        date: manualDate,
                                        time: manualTime,
                                        durationMin: durationMin,
                                        serviceId: serviceId,
                                        excludeDocId: appointment?['id'],
                                      );

                                      if (conflicts.isNotEmpty) {
                                        bool confirm =
                                            await _showConflictDialog(
                                          context: context,
                                          professionalName:
                                              selectedProfessionalName,
                                          timeStr: manualTime.format(context),
                                          messages: conflicts,
                                        );
                                        if (!confirm) return;
                                      }
                                    }
                                    double valor = double.tryParse(
                                            valueController.text
                                                .replaceAll(',', '.')) ??
                                        0.0;
                                    final DateTime manualDateNormalized =
                                        DateTime(
                                            manualDate.year,
                                            manualDate.month,
                                            manualDate.day,
                                            manualTime.hour,
                                            manualTime.minute,
                                            0);
                                    final String nowUtc = DateTime.now()
                                        .toUtc()
                                        .toIso8601String();
                                    final bool priceChanged =
                                        originalModalValue == null ||
                                            (valor - originalModalValue).abs() >
                                                0.01;

                                    final Map<String, dynamic> appointmentData =
                                        {
                                      'shop_id': widget.shopId,
                                      'client_id': selectedClientId,
                                      'client_name': nameController.text.trim(),
                                      'client_phone': phoneController.text
                                              .replaceAll(RegExp(r'\D'), '')
                                              .isEmpty
                                          ? null
                                          : phoneController.text
                                              .replaceAll(RegExp(r'\D'), ''),
                                      'service_name':
                                          serviceController.text.isEmpty
                                              ? 'Avulso'
                                              : serviceController.text,
                                      'service_id': serviceId,
                                      'duration_min': durationMin,
                                      if (selectedProfessionalId != null) ...{
                                        'professional_id':
                                            selectedProfessionalId,
                                        'professional_name':
                                            selectedProfessionalName,
                                      },
                                      'scheduled_at': manualDateNormalized
                                          .toIso8601String(),
                                      'end_at': manualDateNormalized
                                          .add(Duration(minutes: durationMin))
                                          .toIso8601String(),
                                      'updated_at': nowUtc,
                                      if (appointment == null)
                                        'created_at': nowUtc,
                                      // Dono autorizado a sobrepor agendamentos manualmente
                                      'bypass_overlap_check': true,
                                    };

                                    if (editData != null &&
                                        hasProtectedOrPartialPayment) {
                                      final double existingPaid =
                                          editSummary!.paidAmount;
                                      final double effectiveTotal =
                                          (!priceChanged &&
                                                  editSummary.totalPayable >
                                                      0.01)
                                              ? editSummary.totalPayable
                                              : valor;
                                      final double newRem =
                                          (effectiveTotal - existingPaid) > 0.01
                                              ? double.parse((effectiveTotal -
                                                      existingPaid)
                                                  .toStringAsFixed(2))
                                              : 0.0;
                                      final String preservedPayStatus =
                                          resolvePaymentStatus(
                                        paidAmount: existingPaid,
                                        totalPayable: effectiveTotal,
                                      );
                                      appointmentData['payment_status'] =
                                          preservedPayStatus;
                                      appointmentData['remaining_amount'] =
                                          newRem;
                                      if (priceChanged) {
                                        appointmentData['labor_value'] = valor;
                                        appointmentData['total_value'] = valor;
                                        appointmentData['total_price'] = valor;
                                        appointmentData['total_payable'] =
                                            valor;
                                        appointmentData['valor_com_desconto'] =
                                            valor;
                                      }
                                    } else {
                                      appointmentData['labor_value'] = valor;
                                      appointmentData['total_value'] = valor;
                                      appointmentData['total_price'] = valor;
                                      appointmentData['total_payable'] = valor;
                                      appointmentData['valor_com_desconto'] =
                                          valor;
                                      appointmentData['status'] =
                                          isPaid ? 'concluido' : 'agendado';
                                      appointmentData['payment_method'] =
                                          selectedPaymentMethod;
                                      appointmentData['payment_status'] =
                                          isPaid ? 'pago' : 'pendente';
                                      appointmentData['paid_amount'] =
                                          isPaid ? valor : 0.0;
                                      appointmentData['remaining_amount'] =
                                          isPaid ? 0.0 : valor;
                                      if (isPaid) {
                                        appointmentData['payment_id'] =
                                            'manual';
                                        appointmentData['pago_em'] = nowUtc;
                                        appointmentData['metadata'] =
                                            appendPaymentTransactionMetadata(
                                          existingMetadata:
                                              editData?['metadata'] is Map
                                                  ? Map<String, dynamic>.from(
                                                      editData!['metadata']
                                                          as Map)
                                                  : null,
                                          amount: valor,
                                          method: selectedPaymentMethod,
                                          origem: 'manual',
                                          label: 'Pagamento Total',
                                          paymentId: 'manual',
                                          totalPayable: valor,
                                          newPaidTotal: valor,
                                          paidAtIso: nowUtc,
                                          isCompletion: false,
                                        );
                                      }
                                    }

                                    if (_isTrancistaShop) {
                                      final Map<String, dynamic> currentMeta =
                                          appointmentData['metadata'] is Map
                                              ? Map<String, dynamic>.from(
                                                  appointmentData['metadata']
                                                      as Map)
                                              : (editData?['metadata'] is Map
                                                  ? Map<String, dynamic>.from(
                                                      editData!['metadata']
                                                          as Map)
                                                  : <String, dynamic>{});
                                      final corText =
                                          colorController.text.trim();
                                      if (corText.isNotEmpty) {
                                        currentMeta['cor'] = corText;
                                      } else {
                                        currentMeta.remove('cor');
                                      }
                                      appointmentData['metadata'] = currentMeta;
                                    }

                                    try {
                                      if (appointment == null) {
                                        await sb.Supabase.instance.client
                                            .from('appointments')
                                            .insert(appointmentData);
                                      } else {
                                        await sb.Supabase.instance.client
                                            .from('appointments')
                                            .update(appointmentData)
                                            .eq('id', appointment['id']);
                                        final apptId =
                                            appointment['id'].toString();
                                        setState(() {
                                          if (_selectedAppointment != null &&
                                              _selectedAppointment!['id']
                                                      ?.toString() ==
                                                  apptId) {
                                            _selectedAppointment = {
                                              ..._selectedAppointment!,
                                              ...appointmentData
                                            };
                                          }
                                          final idx = _appointments.indexWhere(
                                              (a) =>
                                                  a['id']?.toString() ==
                                                  apptId);
                                          if (idx != -1)
                                            _appointments[idx] = {
                                              ..._appointments[idx],
                                              ...appointmentData
                                            };
                                          if (_docCache.containsKey(apptId)) {
                                            _docCache[apptId] = {
                                              ..._docCache[apptId]!,
                                              ...appointmentData
                                            };
                                          }
                                          _isLoading = false;
                                        });
                                      }

                                      ShopDataCacheService().invalidate(
                                          widget.shopId, 'appointments');

                                      if (!mounted) return;
                                      Navigator.pop(context, 'edit');
                                      _loadAppointments();
                                      _loadMonthEvents();

                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(SnackBar(
                                        content: Text(appointment == null
                                            ? 'Agendamento criado!'
                                            : 'Agendamento atualizado!'),
                                        backgroundColor: Colors.green,
                                      ));
                                    } catch (e) {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(SnackBar(
                                              content:
                                                  Text('Erro ao salvar: $e')));
                                    }
                                  },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.primaryPurple,
                                    foregroundColor: Colors.white,
                                    elevation: 0,
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(12)),
                                  ),
                                  child: Text(
                                      appointment == null
                                          ? "Finalizar Lançamento"
                                          : "Salvar Alterações",
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16)),
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
    return Column(
      children: [
        // Cabeçalho fixo — calendário sempre visível no topo
        Container(
          color: Colors.white,
          child: Column(
            children: [
              _buildCalendarCard(isMobile: true),
              _buildStatsSection(),
            ],
          ),
        ),
        // Lista de agendamentos com scroll independente
        Expanded(
          child: RefreshIndicator(
            onRefresh: _loadAppointments,
            color: AppColors.primaryPurple,
            child: CustomScrollView(
              controller: _scrollController,
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.only(top: 10, bottom: 80),
                  sliver: _buildSliverList(),
                ),
              ],
            ),
          ),
        ),
      ],
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

                          final groupedItems = _buildGroupedListItems(
                            appointments: filteredAppointments,
                            isDesktop: true,
                          );
                          return groupedItems.isEmpty
                              ? _buildEmptyState()
                              : ListView(
                                  controller: _scrollController,
                                  padding: const EdgeInsets.only(
                                      top: 10, bottom: 20),
                                  children: groupedItems,
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
                shopCategory: _shopCategory,
                isEmbedded: true,
                onEdit: () =>
                    _showQuickEntryModal(appointment: _selectedAppointment!),
                onAppointmentUpdated: (updatedData) {
                  final id = updatedData['id']?.toString();
                  setState(() {
                    final mergedSelected = {
                      ...?_selectedAppointment,
                      ...updatedData
                    };
                    _selectedAppointment = mergedSelected;
                    if (id != null) {
                      final idx = _appointments
                          .indexWhere((a) => a['id']?.toString() == id);
                      if (idx != -1) {
                        final merged = {..._appointments[idx], ...updatedData};
                        _appointments[idx] = merged;
                        _docCache[id] = merged;
                      } else {
                        _docCache[id] = mergedSelected;
                      }
                      _cacheAccess[id] = DateTime.now();
                    }
                  });
                  ScheduleCacheService.saveAppointments(
                      widget.shopId, _appointments);
                },
                onClose: () {
                  final id = _selectedAppointment?['id'];
                  setState(() => _selectedAppointment = null);
                  if (id != null) {
                    setState(() {
                      _docCache.remove(id);
                      _cacheAccess.remove(id);
                      _appointments.removeWhere(
                          (d) => d['id'].toString() == id.toString());
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
        final dynamic scheduledAt = doc['scheduled_at'];
        if (scheduledAt == null) return false;
        final d = scheduledAt is DateTime
            ? scheduledAt
            : DateTime.parse(scheduledAt.toString());
        final dd = DateTime(d.year, d.month, d.day);
        return !dd.isBefore(start); // keep date >= start
      }).toList();
    }

    final flat = _buildGroupedListItems(
      appointments: filteredAppointments,
      isDesktop: false,
    );

    final hasContent = flat.isNotEmpty;

    if (!hasContent) {
      return SliverFillRemaining(child: _buildEmptyState());
    }

    return SliverList(
        delegate: SliverChildBuilderDelegate((context, index) {
      return flat[index];
    }, childCount: flat.length));
  }

  List<Widget> _buildGroupedListItems({
    required List<Map<String, dynamic>> appointments,
    required bool isDesktop,
  }) {
    // Group by day
    final Map<DateTime, List<Map<String, dynamic>>> grouped = {};
    for (var doc in appointments) {
      final dynamic scheduledAt = doc['scheduled_at'];
      if (scheduledAt == null) continue;
      final d = scheduledAt is DateTime
          ? scheduledAt
          : DateTime.parse(scheduledAt.toString());
      final key = DateTime(d.year, d.month, d.day);
      grouped.putIfAbsent(key, () => []).add(doc);
    }

    // Injetar pseudo-agendamentos de folga
    final now = DateTime.now();
    final minViewDate = _startFromDate ??
        DateTime(now.year, now.month, now.day)
            .subtract(const Duration(days: 30));
    final maxViewDate =
        _weekEndDate ?? minViewDate.add(const Duration(days: 60));

    for (var prof in _professionals) {
      final breaks = prof['breaks'];
      if (breaks != null && breaks is List) {
        for (var b in breaks) {
          final startStr = b['start']?.toString();
          final endStr = b['end']?.toString();
          if (startStr != null && endStr != null) {
            final start = DateTime.parse(startStr).toLocal();
            final end = DateTime.parse(endStr).toLocal();

            for (var dt = DateTime(start.year, start.month, start.day);
                !dt.isAfter(end);
                dt = dt.add(const Duration(days: 1))) {
              if (dt.isBefore(minViewDate) || dt.isAfter(maxViewDate)) continue;
              if (isDesktop &&
                  _showOnlySelectedDay &&
                  _startFromDate != null &&
                  dt !=
                      DateTime(_startFromDate!.year, _startFromDate!.month,
                          _startFromDate!.day)) continue;

              final fType = b['type']?.toString() ?? 'full_day';
              String timeStr = 'Dia inteiro';
              if (fType == 'partial' &&
                  b['start_time'] != null &&
                  b['end_time'] != null) {
                timeStr = '${b['start_time']} às ${b['end_time']}';
              }

              final profPhoto = (prof['photo_url'] ??
                      prof['avatar_url'] ??
                      prof['foto_url'] ??
                      prof['foto_perfil'] ??
                      '')
                  .toString()
                  .trim();

              final pseudoAppt = {
                'id': 'break_${prof['id']}_${dt.millisecondsSinceEpoch}',
                'is_break': true,
                'professional_id': prof['id'],
                'professional_name': prof['name'],
                'professional_photo': profPhoto,
                'break_type': fType,
                'break_time': timeStr,
                'notes': b['notes'] ?? 'Folga',
                'scheduled_at': dt.toIso8601String(),
              };

              grouped.putIfAbsent(dt, () => []).add(pseudoAppt);
            }
          }
        }
      }
    }

    // Injetar feriados personalizados/nacionais/globais dentro da janela visível
    final Map<String, Map<String, dynamic>> holidaysByIso = {};
    void registerHoliday({
      required dynamic rawDate,
      required String name,
      required String scope,
      required bool isCustom,
    }) {
      final rawStr = rawDate?.toString().split('T').first ?? '';
      if (rawStr.isEmpty) return;
      final parsed = DateTime.tryParse(rawStr);
      if (parsed == null) return;
      final dt = DateTime(parsed.year, parsed.month, parsed.day);
      final iso =
          '${dt.year.toString().padLeft(4, '0')}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
      holidaysByIso[iso] = {
        'date': dt,
        'iso': iso,
        'name': name,
        'scope': scope,
        'is_custom': isCustom,
      };
    }

    for (final h in _globalHolidays) {
      registerHoliday(
        rawDate: h['date'],
        name: (h['title'] ?? h['name'] ?? 'Feriado').toString(),
        scope: 'Feriado Regional',
        isCustom: false,
      );
    }
    for (final h in _nationalHolidays) {
      final hType = h['type']?.toString().toLowerCase() ?? '';
      registerHoliday(
        rawDate: h['date'],
        name: (h['name'] ?? h['title'] ?? 'Feriado').toString(),
        scope: hType == 'national' ? 'Feriado Nacional' : 'Feriado',
        isCustom: false,
      );
    }
    for (final h in _customHolidays) {
      if (h is Map) {
        registerHoliday(
          rawDate: h['date'],
          name: (h['name'] ?? h['title'] ?? 'Feriado da Loja').toString(),
          scope: 'Feriado da Loja',
          isCustom: true,
        );
      }
    }

    for (final entry in holidaysByIso.values) {
      final dt = entry['date'] as DateTime;
      if (dt.isBefore(minViewDate) || dt.isAfter(maxViewDate)) continue;
      if (isDesktop &&
          _showOnlySelectedDay &&
          _startFromDate != null &&
          dt !=
              DateTime(_startFromDate!.year, _startFromDate!.month,
                  _startFromDate!.day)) {
        continue;
      }

      grouped.putIfAbsent(dt, () => []).add({
        'id': 'holiday_${entry['iso']}',
        'is_holiday': true,
        'holiday_iso': entry['iso'],
        'holiday_name': entry['name'],
        'holiday_scope': entry['scope'],
        'is_custom_holiday': entry['is_custom'],
        'scheduled_at': dt.toIso8601String(),
      });
    }

    final keys = grouped.keys.toList();
    keys.sort((a, b) => a.compareTo(b));
    for (var k in keys) {
      grouped[k]!.sort((a, b) {
        if (a['is_holiday'] == true && b['is_holiday'] != true) return -1;
        if (b['is_holiday'] == true && a['is_holiday'] != true) return 1;
        if (a['is_break'] == true && b['is_break'] != true) return -1;
        if (b['is_break'] == true && a['is_break'] != true) return 1;

        final dtA = a['scheduled_at'] is DateTime
            ? a['scheduled_at']
            : DateTime.tryParse(a['scheduled_at'].toString()) ?? DateTime.now();
        final dtB = b['scheduled_at'] is DateTime
            ? b['scheduled_at']
            : DateTime.tryParse(b['scheduled_at'].toString()) ?? DateTime.now();
        return dtA.compareTo(dtB);
      });
    }

    final List<Widget> flat = [];

    // Mobile: show top loader if there are older items to load
    if (!isDesktop &&
        _hasMorePast &&
        !(_startFromSelectedDay && _weekEndDate != null)) {
      flat.add(const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Center(
            child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2))),
      ));
    }

    for (final key in keys) {
      final dayAppointments = grouped[key]!;

      // Calcular total do dia (especialmente para desktop)
      double dayTotal = 0;
      for (var appt in dayAppointments) {
        if (appt['is_holiday'] == true || appt['is_break'] == true) continue;
        dayTotal += _getDisplayTotal(appt);
      }

      // header with + button
      final headerKey = _dayKeys.putIfAbsent(key, () => GlobalKey());
      flat.add(Padding(
        padding: isDesktop
            ? const EdgeInsets.fromLTRB(0, 20, 0, 10)
            : const EdgeInsets.fromLTRB(16, 6, 16, 2),
        child: Container(
          key: headerKey,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Text(
                    DateFormat('EEEE, dd/MM/yyyy', 'pt_BR').format(key),
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, color: Colors.grey),
                  ),
                  if (isDesktop) ...[
                    const SizedBox(width: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.primaryPurple.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: ValueListenableBuilder<bool>(
                        valueListenable:
                            PrivacyService.instance.isHiddenNotifier,
                        builder: (context, isHidden, _) => Text(
                          isHidden
                              ? "Total: R\$ *****"
                              : "Total: ${NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$').format(dayTotal)}",
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: AppColors.primaryPurple,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              if (!isDesktop)
                IconButton(
                  icon: const Icon(Icons.add_circle, color: Colors.green),
                  tooltip: 'Adicionar agendamento neste dia',
                  onPressed: () => _showQuickEntryModal(initialDate: key),
                ),
            ],
          ),
        ),
      ));

      // 🆕 Layout em Colunas por Profissional (Apenas Desktop e quando clicou na data)
      if (isDesktop && _showOnlySelectedDay) {
        final dayHolidays =
            dayAppointments.where((a) => a['is_holiday'] == true).toList();
        final dayBreaks =
            dayAppointments.where((a) => a['is_break'] == true).toList();
        final dayRegularApps = dayAppointments
            .where((a) => a['is_holiday'] != true && a['is_break'] != true)
            .toList();

        for (final holidayDoc in dayHolidays) {
          flat.add(_buildHolidayCard(holidayDoc, isDesktop: true));
        }
        for (final breakDoc in dayBreaks) {
          flat.add(_buildBreakCard(breakDoc, isDesktop: true));
        }

        if (dayRegularApps.isNotEmpty) {
          final Map<String, List<Map<String, dynamic>>> byPro = {};
          for (var appt in dayRegularApps) {
            final proId = appt['professional_id']?.toString() ?? 'nao_definido';
            byPro.putIfAbsent(proId, () => []).add(appt);
          }

          final proIds = byPro.keys.toList();

          flat.add(
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return Wrap(
                    spacing: 20,
                    runSpacing: 20,
                    children: proIds.map((proId) {
                      final proApps = byPro[proId]!;
                      final proInfo = _professionals.firstWhere(
                        (p) => p['id']?.toString() == proId,
                        orElse: () => {},
                      );
                      final String proName = proInfo['name'] ??
                          proApps.first['professional_name'] ??
                          'Profissional';
                      final String? proPhoto = proInfo['photo_url'];

                      return SizedBox(
                        width: proIds.length > 1
                            ? (constraints.maxWidth - 20) / 2
                            : constraints.maxWidth,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildProfessionalHeader(proName, proPhoto),
                            const SizedBox(height: 12),
                            ...proApps.map((doc) => Padding(
                                  padding: const EdgeInsets.only(bottom: 10),
                                  child: _buildAppointmentCard(doc,
                                      isDesktop: true),
                                )),
                          ],
                        ),
                      );
                    }).toList(),
                  );
                },
              ),
            ),
          );
        }
      } else {
        // Layout Normal (Lista Vertical)
        for (final doc in dayAppointments) {
          final docId = doc['id']?.toString() ?? '';
          final appointmentKey = docId.isNotEmpty
              ? _appointmentKeys.putIfAbsent(docId, () => GlobalKey())
              : null;
          flat.add(Container(
            key: appointmentKey,
            child: Padding(
              padding: isDesktop
                  ? EdgeInsets.zero
                  : const EdgeInsets.symmetric(horizontal: 16),
              child: _buildAppointmentCard(
                doc,
                isDesktop: isDesktop,
                highlighted: docId == _highlightedAppointmentId,
              ),
            ),
          ));
        }
      }
    }

    // Desktop: show bottom loader if hasMore (only if not showing only selected day)
    if (isDesktop && _hasMore && !_showOnlySelectedDay) {
      flat.add(const Center(
        child: Padding(
          padding: EdgeInsets.all(10),
          child: CircularProgressIndicator(),
        ),
      ));
    }

    return flat;
  }

  Widget _buildProfessionalHeader(String name, String? photoUrl) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: AppColors.primaryPurple.withValues(alpha: 0.1),
            backgroundImage: (photoUrl != null && photoUrl.isNotEmpty)
                ? NetworkImage(photoUrl)
                : null,
            child: (photoUrl == null || photoUrl.isEmpty)
                ? Text(name.isNotEmpty ? name[0].toUpperCase() : 'P',
                    style: const TextStyle(
                        color: AppColors.primaryPurple,
                        fontSize: 14,
                        fontWeight: FontWeight.bold))
                : null,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              name,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
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
        !(date.weekday == 7 &&
            (workDays.contains(0) || workDays.contains(7)))) {
      conflicts.add("O profissional não trabalha neste dia da semana.");
    }

    // 3. Check Working Hours (per-day schedule)
    final wsEmp = WorkSchedule.fromEmployeeRow(empDoc);
    final dayCfg = wsEmp.forWeekday(date.weekday);
    final String startStr = dayCfg?.start ??
        (empDoc['work_start'] ?? empDoc['start_time'] ?? "08:00");
    final String endStr =
        dayCfg?.end ?? (empDoc['work_end'] ?? empDoc['end_time'] ?? "18:00");
    int startDayMin = int.parse(startStr.split(':')[0]) * 60 +
        int.parse(startStr.split(':')[1]);
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
    // Pausa diária (almoço etc.)
    final br = dayCfg?.breakInterval;
    if (br != null &&
        targetStartMin < br.endMin &&
        targetEndMin > br.startMin) {
      conflicts.add(
          "O horário conflita com a pausa do profissional (${br.start}–${br.end}).");
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
                        const Text("• ",
                            style: TextStyle(fontWeight: FontWeight.bold)),
                        Expanded(child: Text(m)),
                      ],
                    ),
                  ))
            else
              const Text(
                  "Este horário já possui um agendamento (sobreposição)."),
            const SizedBox(height: 12),
            const Text(
                "Deseja realizar a sobreposição administrativa mesmo assim?"),
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
          rowHeight: 42, // <-- Altura reduzida das células dos dias
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
              final startOfWeek =
                  _focusedDay.subtract(Duration(days: _focusedDay.weekday - 1));
              final endOfWeek = startOfWeek.add(const Duration(days: 6));
              setState(() {
                _showOnlySelectedDay = false;
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
            // Ao selecionar um dia, a lista começa a partir desse dia
            final startOfWeek =
                selectedDay.subtract(Duration(days: selectedDay.weekday - 1));
            final endOfWeek = startOfWeek.add(const Duration(days: 6));
            final weekStart =
                DateTime(startOfWeek.year, startOfWeek.month, startOfWeek.day);
            final weekEnd = DateTime(
                endOfWeek.year, endOfWeek.month, endOfWeek.day, 23, 59, 59);

            final bool isDesktop = MediaQuery.of(context).size.width > 900;

            setState(() {
              _selectedDay = selectedDay;
              _focusedDay = focusedDay;
              _showOnlySelectedDay =
                  isDesktop; // No desktop, filtra apenas o dia
              _startFromSelectedDay = true;
              _startFromDate = DateTime(selectedDay.year, selectedDay.month,
                  selectedDay.day); // lista começa no dia clicado
              _weekEndDate = isDesktop
                  ? _startFromDate!
                      .add(const Duration(hours: 23, minutes: 59, seconds: 59))
                  : weekEnd;
            });
            // Filtro imediato no cache + busca semana completa no servidor
            _applyWeekFilterToCache();
            _fetchWeekFromServer(isDesktop ? _startFromDate! : weekStart,
                isDesktop ? _weekEndDate! : weekEnd);
          },
          onPageChanged: (focusedDay) {
            final oldYear = _focusedDay.year;
            setState(() => _focusedDay = focusedDay);
            if (focusedDay.year != oldYear ||
                focusedDay.month >= 11 ||
                focusedDay.month <= 2) {
              _fetchHolidays();
            }
            _loadMonthEvents();

            // No modo semana: atualizar janela e buscar dados da semana
            final isMobileWeek = _calendarFormat == CalendarFormat.week;
            if (isMobileWeek) {
              final startOfWeek =
                  focusedDay.subtract(Duration(days: focusedDay.weekday - 1));
              final endOfWeek = startOfWeek.add(const Duration(days: 6));
              setState(() {
                _showOnlySelectedDay = false;
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
              final isoDate =
                  '${day.year.toString().padLeft(4, '0')}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';

              // 1. National/Global/Custom Holiday Marker (Blue)
              final isNational =
                  _nationalHolidays.any((f) => f['date'] == isoDate);
              final isGlobal = _globalHolidays.any((f) => f['date'] == isoDate);
              final isCustomHoliday = _customHolidays.any((f) =>
                  f is Map &&
                  (f['date']?.toString().split('T').first ?? '') == isoDate);

              if (isNational || isGlobal || isCustomHoliday) {
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

              // 3. Break Marker (Amber)
              bool hasBreak = false;
              for (var prof in _professionals) {
                final breaks = prof['breaks'];
                if (breaks != null && breaks is List) {
                  for (var b in breaks) {
                    final startStr = b['start']?.toString();
                    final endStr = b['end']?.toString();
                    if (startStr != null && endStr != null) {
                      final start = DateTime.tryParse(startStr)?.toLocal();
                      final end = DateTime.tryParse(endStr)?.toLocal();
                      if (start == null || end == null) continue;
                      final startDay =
                          DateTime(start.year, start.month, start.day);
                      final endDay = DateTime(end.year, end.month, end.day);
                      final dayOnly = DateTime(day.year, day.month, day.day);
                      if (!dayOnly.isBefore(startDay) &&
                          !dayOnly.isAfter(endDay)) {
                        hasBreak = true;
                        break;
                      }
                    }
                  }
                }
                if (hasBreak) break;
              }

              if (hasBreak) {
                markers.add(
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: Colors.amber.shade700,
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
                  children: markers
                      .map((m) => Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 1),
                            child: m,
                          ))
                      .toList(),
                ),
              );
            },
          ),
          headerStyle: const HeaderStyle(
            titleCentered: true,
            formatButtonVisible: true,
            headerPadding:
                EdgeInsets.symmetric(vertical: 4.0), // <-- Padding reduzido
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
        const SizedBox(height: 2), // <-- Margem inferior reduzida
      ],
    );
  }

  Widget _buildStatsSection() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
      color: Colors.transparent,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          ValueListenableBuilder<bool>(
            valueListenable: PrivacyService.instance.isHiddenNotifier,
            builder: (context, isHidden, _) => Text(
              isHidden
                  ? "Faturamento da semana: R\$ *****"
                  : "Faturamento da semana: ${NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$').format(_weeklyRevenue)}",
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              textAlign: TextAlign.left,
            ),
          ),
          ValueListenableBuilder<bool>(
            valueListenable: PrivacyService.instance.isHiddenNotifier,
            builder: (context, isHidden, _) => IconButton(
              icon: Icon(
                isHidden ? Icons.visibility_off : Icons.visibility,
                color: Colors.grey[700],
              ),
              onPressed: () => PrivacyService.instance.togglePrivacy(),
            ),
          ),
        ],
      ),
    );
  }

  void _computeWeekRevenueFromCache(DateTime weekStart, DateTime weekEnd) {
    double wSum = 0.0;
    final seenIds = <String>{};
    for (var doc in _docCache.values) {
      final rawSA = doc['scheduled_at'];
      if (rawSA == null) continue;
      final date = rawSA is DateTime ? rawSA : DateTime.parse(rawSA.toString());
      if (date.isBefore(weekStart) || date.isAfter(weekEnd)) continue;
      if ((doc['status'] ?? '').toString().toLowerCase() == 'cancelado')
        continue;
      final id = doc['id'].toString();
      if (seenIds.add(id)) wSum += _getDisplayTotal(doc);
    }
    if (mounted) {
      setState(() => _weeklyRevenue = wSum);
    }
  }

  // Busca faturamento semanal com query filtrada por data
  Future<void> _loadRevenueStats() async {
    if (widget.shopId.isEmpty) return;
    final weekBase = _startFromDate ?? DateTime.now();
    final mondayOfWeek =
        weekBase.subtract(Duration(days: weekBase.weekday - 1));
    final weekStart =
        DateTime(mondayOfWeek.year, mondayOfWeek.month, mondayOfWeek.day);
    final weekEnd = DateTime(mondayOfWeek.year, mondayOfWeek.month,
        mondayOfWeek.day + 6, 23, 59, 59);
    _computeWeekRevenueFromCache(weekStart, weekEnd);
    try {
      final selectCols =
          'total_payable, total_price, total_value, valor_com_desconto, labor_value, status, discount_amount, birthday_discount_applied, birthday_discount_percent, coupon_applied, coupon_discount_percent';
      final snap = await sb.Supabase.instance.client
          .from('appointments')
          .select(selectCols)
          .eq('shop_id', widget.shopId)
          .neq('status', 'pre_reserva')
          .gte('scheduled_at', weekStart.toIso8601String())
          .lte('scheduled_at', weekEnd.toIso8601String());
      double wSum = 0.0;
      for (final d in snap as List) {
        if ((d['status'] ?? '').toString().toLowerCase() == 'cancelado')
          continue;
        wSum += _getDisplayTotal(d as Map<String, dynamic>);
      }
      if (mounted) {
        setState(() => _weeklyRevenue = wSum);
      }
    } catch (e) {
      debugPrint('Erro ao carregar receita: $e');
    }
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

            // ── REALTIME CIRÚRGICO: trata UPDATE sem descartar campos de pagamento ──
            if (payload.eventType == sb.PostgresChangeEvent.update) {
              final newRecord = payload.newRecord;
              final id = newRecord['id']?.toString();
              if (id != null) {
                final newStatus =
                    (newRecord['status'] ?? '').toString().toLowerCase();

                // Agendamento cancelado: remove da lista com animação (via setState)
                if (newStatus == 'cancelled' || newStatus == 'cancelado') {
                  setState(() {
                    _appointments.removeWhere((a) => a['id'].toString() == id);
                    _docCache.remove(id);
                    _cacheAccess.remove(id);
                    if (_selectedAppointment?['id']?.toString() == id) {
                      _selectedAppointment = null;
                    }
                    for (var list in _events.values) list.remove(id);
                  });
                  ScheduleCacheService.saveAppointments(
                      widget.shopId, _appointments);
                  return;
                }

                final idx =
                    _appointments.indexWhere((a) => a['id'].toString() == id);
                if (idx != -1) {
                  final existing = _appointments[idx];
                  final oldScheduled =
                      existing['scheduled_at']?.toString() ?? '';
                  final newScheduled =
                      newRecord['scheduled_at']?.toString() ?? '';
                  final bool scheduledChanged = oldScheduled.isNotEmpty &&
                      newScheduled.isNotEmpty &&
                      DateTime.tryParse(oldScheduled)?.toUtc() !=
                          DateTime.tryParse(newScheduled)?.toUtc();

                  final merged = Map<String, dynamic>.from(existing)
                    ..addAll(newRecord);
                  // Preserva client_name já enriquecido caso newRecord venha vazio ou como email
                  final incomingName =
                      (newRecord['client_name'] ?? '').toString().trim();
                  final oldName =
                      (existing['client_name'] ?? '').toString().trim();
                  if ((incomingName.isEmpty ||
                          (incomingName.contains('@') &&
                              !incomingName.contains(' '))) &&
                      oldName.isNotEmpty &&
                      !oldName.contains('@')) {
                    merged['client_name'] = oldName;
                  }

                  setState(() {
                    _appointments[idx] = merged;
                    _docCache[id] = merged;
                    _cacheAccess[id] = DateTime.now();
                    if (_selectedAppointment?['id']?.toString() == id) {
                      _selectedAppointment = merged;
                    }
                  });
                  ScheduleCacheService.saveAppointments(
                      widget.shopId, _appointments);
                  _loadRevenueStats();

                  if (!scheduledChanged) {
                    return;
                  }
                }
              }
            }

            // Qualquer outro evento: debounce + reload da semana
            _realtimeDebounceTimer?.cancel();
            _realtimeDebounceTimer =
                Timer(const Duration(milliseconds: 800), () {
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
        data['preco'] ??
        0;
    if (val == null || val.toString().trim().isEmpty) return 0.0;
    if (val is num) return val.toDouble();
    if (val is String) return double.tryParse(val.replaceAll(',', '.')) ?? 0.0;
    return 0.0;
  }

  /// Retorna o valor real após descontos para exibição em cards e relatórios.
  /// Delega à fonte única [getCalculatedTotal] com fallback para [_safeParseValue].
  double _getDisplayTotal(Map<String, dynamic> data) {
    final calculated = getCalculatedTotal(data);
    return calculated > 0.01 ? calculated : _safeParseValue(data);
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
      final yearsNeeded = <int>{
        year,
        if (_focusedDay.month >= 11) year + 1,
        if (_focusedDay.month <= 2) year - 1,
      };
      final missingYears = yearsNeeded
          .where((y) => !_loadedHolidayYears.contains(y))
          .toList()
        ..sort();
      if (missingYears.isEmpty) return;

      // 1. National Holidays (BrasilAPI) para os anos faltantes na janela atual
      final nationalLists = await Future.wait(
        missingYears.map((y) => BrasilApiService.getHolidays(y)),
      );

      // 2. Global Holidays (Database)
      final minY = missingYears.first;
      final maxY = missingYears.last;
      final global =
          await sb.Supabase.instance.client // Changed Supabase to sb.Supabase
              .from('global_holidays')
              .select()
              .gte('date', '$minY-01-01')
              .lte('date', '$maxY-12-31');

      if (mounted) {
        setState(() {
          _loadedHolidayYears.addAll(missingYears);

          final mergedNational = List<dynamic>.from(_nationalHolidays);
          final seenNational = mergedNational
              .map((h) => '${h['date']}|${h['name'] ?? h['title'] ?? ''}')
              .toSet();
          for (final batch in nationalLists) {
            for (final item in batch) {
              final key =
                  '${item['date']}|${item['name'] ?? item['title'] ?? ''}';
              if (seenNational.add(key)) {
                mergedNational.add(item);
              }
            }
          }
          _nationalHolidays = mergedNational;

          final mergedGlobal = List<Map<String, dynamic>>.from(_globalHolidays);
          final seenGlobal = mergedGlobal
              .map((h) => '${h['date']}|${h['title'] ?? h['name'] ?? ''}')
              .toSet();
          for (final item in List<Map<String, dynamic>>.from(global)) {
            final key =
                '${item['date']}|${item['title'] ?? item['name'] ?? ''}';
            if (seenGlobal.add(key)) {
              mergedGlobal.add(item);
            }
          }
          _globalHolidays = mergedGlobal;
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

  bool _cacheCoversRange(DateTime start, DateTime end) {
    for (var a in _appointments) {
      final rawSA = a['scheduled_at'];
      if (rawSA == null) continue;
      final date = rawSA is DateTime ? rawSA : DateTime.parse(rawSA.toString());
      if (!date.isBefore(start) && !date.isAfter(end)) return true;
    }
    return false;
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
      final foundIds = <String>{for (final doc in docs) doc['id'].toString()};
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
    _scrollTrackDebounce?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    // Carregar mais agendamentos futuros quando próximo do fim
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent * 0.7) {
      _loadMoreAppointments();
    }
    // Carregar agendamentos passados quando próximo do topo
    if (_scrollController.position.pixels <=
        _scrollController.position.minScrollExtent + 150) {
      _loadMorePastAppointments();
    }
    // Atualizar dia/semana selecionado conforme scroll
    _updateSelectedDayFromScroll();
  }

  void _updateSelectedDayFromScroll() {
    _scrollTrackDebounce?.cancel();
    _scrollTrackDebounce = Timer(const Duration(milliseconds: 200), () {
      if (!mounted) return;
      DateTime? topDay;
      double? closestBelow;

      for (final entry in _dayKeys.entries) {
        final ctx = entry.value.currentContext;
        if (ctx == null) continue;
        final box = ctx.findRenderObject() as RenderBox?;
        if (box == null || !box.attached) continue;
        final pos = box.localToGlobal(Offset.zero);
        // Pegar o cabeçalho de dia que está mais próximo do topo visível (acima de 350px)
        if (pos.dy > 0 && pos.dy < 350) {
          if (closestBelow == null || pos.dy < closestBelow) {
            closestBelow = pos.dy;
            topDay = entry.key;
          }
        }
      }

      if (topDay != null && !isSameDay(topDay, _selectedDay)) {
        final day = topDay;
        setState(() {
          _selectedDay = day;
          _focusedDay = day;
        });
      }
    });
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
          .select(_appointmentSelectCols)
          .eq('shop_id', widget.shopId)
          .neq('status', 'pre_reserva')
          .gte('scheduled_at', start.toIso8601String())
          .lte('scheduled_at', end.toIso8601String())
          .order('scheduled_at', ascending: true)
          .limit(200);

      if (!mounted) return;
      setState(() {
        // replace visible appointments with fresh week data
        _appointments = List<Map<String, dynamic>>.from(snap);
        // Na visualizacao do dia ou da semana, so teremos paginacao se a query atingiu o limite maximo (200)
        _hasMore = snap.length >= 200;
        _hasMorePast =
            false; // Trazemos o range completo, o passado daquela janela esgotou
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
          final rawSAEvt = data['scheduled_at'];
          if (rawSAEvt == null) continue;
          final status = (data['status'] ?? '').toString().toLowerCase();
          if (status == 'cancelado') continue;

          final date = rawSAEvt is DateTime
              ? rawSAEvt
              : DateTime.parse(rawSAEvt.toString());
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
      if (!_showOnlySelectedDay) {
        _updateWeeklyRevenueFromAppointments();
      } else {
        // No desktop, ao selecionar um dia, _appointments só tem aquele dia.
        // Precisamos carregar o faturamento da semana inteira separadamente.
        _loadRevenueStats();
      }
      _resolveVipForAppointments(_appointments);
      // Scroll: para agendamento específico no primeiro carregamento, senão para o topo do dia
      if (!_initialScrollDone && widget.initialAppointmentId != null) {
        _initialScrollDone = true;
        _scrollToAppointment(widget.initialAppointmentId!);
      } else {
        _scrollToSelectedDay();
      }
      ScheduleCacheService.saveAppointments(widget.shopId, _appointments);
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
    final end = DateTime(
        _weekEndDate!.year, _weekEndDate!.month, _weekEndDate!.day, 23, 59, 59);

    final filtered = _docCache.values.where((data) {
      final rawSAFilter = data['scheduled_at'];
      if (rawSAFilter == null) return false;
      final d = rawSAFilter is DateTime
          ? rawSAFilter
          : DateTime.parse(rawSAFilter.toString());
      final dd = DateTime(d.year, d.month, d.day);
      return !dd.isBefore(start) && !dd.isAfter(end);
    }).toList();

    // sort by date asc
    filtered.sort((a, b) {
      final rawA = a['scheduled_at'];
      final da = rawA is DateTime ? rawA : DateTime.parse(rawA.toString());
      final rawB = b['scheduled_at'];
      final db = rawB is DateTime ? rawB : DateTime.parse(rawB.toString());
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

  Widget _buildBreakCard(Map<String, dynamic> data, {required bool isDesktop}) {
    String photoUrl = (data['professional_photo'] ?? '').toString().trim();
    if (photoUrl.isEmpty && data['professional_id'] != null) {
      final proId = data['professional_id'].toString();
      final proInfo = _professionals.firstWhere(
        (p) => p['id']?.toString() == proId,
        orElse: () => const {},
      );
      photoUrl = (proInfo['photo_url'] ??
              proInfo['avatar_url'] ??
              proInfo['foto_url'] ??
              proInfo['foto_perfil'] ??
              '')
          .toString()
          .trim();
    }

    return BreakScheduleCard(
      professionalName:
          (data['professional_name'] ?? 'Profissional').toString(),
      professionalPhotoUrl: photoUrl.isNotEmpty ? photoUrl : null,
      breakTime: (data['break_time'] ?? '').toString(),
      notes: data['notes']?.toString(),
      breakType: (data['break_type'] ?? 'full_day').toString(),
    );
  }

  Widget _buildHolidayCard(Map<String, dynamic> data,
      {required bool isDesktop}) {
    final rawDt = data['scheduled_at']?.toString() ?? '';
    final parsed = DateTime.tryParse(rawDt) ?? DateTime.now();
    final date = DateTime(parsed.year, parsed.month, parsed.day);
    final iso = data['holiday_iso']?.toString() ??
        '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    final name = data['holiday_name']?.toString() ?? 'Feriado';
    final scope = data['holiday_scope']?.toString() ?? 'Feriado';
    final isCustom = data['is_custom_holiday'] == true;

    final status = resolveHolidayShopStatus(
      isoDate: iso,
      configuredHolidays: _configuredHolidays,
      pendingHolidays: _pendingHolidays,
      autoBlockHolidays: _shopConfig['auto_block_holidays'] == true,
    );

    return HolidayScheduleCard(
      date: date,
      name: name,
      scopeLabel: scope,
      status: status,
      isCustom: isCustom,
      onTap: () async {
        if (widget.onNavigateToHoliday != null) {
          widget.onNavigateToHoliday!(date, name);
        } else {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => HolidaysPage(
                shopId: widget.shopId,
                initialDate: date,
                initialHolidayName: name,
                showAppBar: true,
              ),
            ),
          );
          if (mounted) {
            _loadShopConfig();
          }
        }
      },
    );
  }

  Widget _buildAppointmentCard(Map<String, dynamic> data,
      {required bool isDesktop, bool highlighted = false}) {
    if (data['is_holiday'] == true) {
      return _buildHolidayCard(data, isDesktop: isDesktop);
    }
    if (data['is_break'] == true) {
      return _buildBreakCard(data, isDesktop: isDesktop);
    }

    final rawScheduledAt = data['scheduled_at'];
    DateTime hora;
    if (rawScheduledAt is DateTime) {
      hora = rawScheduledAt;
    } else {
      hora = DateTime.parse(rawScheduledAt.toString());
    }

    final summary = getPaymentSummary(data);
    double total = summary.totalPayable > 0.01
        ? summary.totalPayable
        : _getDisplayTotal(data);
    String status = data['status']?.toString().toLowerCase() ?? '';
    String paymentMethod =
        data['payment_method']?.toString() ?? 'Não informado';
    final bool hasOnlinePayment = summary.hasOnlinePayment;

    // Auto-correção visual para agendamentos antigos:
    if (hasOnlinePayment &&
        (paymentMethod.toLowerCase().contains('pessoal') ||
            paymentMethod.toLowerCase().contains('dinheiro') ||
            paymentMethod.toLowerCase().contains('manual'))) {
      paymentMethod = 'Pago no App';
    }

    bool isCanceled = status == 'cancelado' || summary.isCanceled;

    Color statusColor = Colors.blue;

    if (isCanceled) {
      statusColor = Colors.red;
    } else if (status == 'concluido') {
      statusColor = Colors.grey;
    } else if (status == 'confirmed_by_client' ||
        data['confirmed_via_whatsapp'] == true) {
      statusColor = Colors.green;
    } else if (status == 'confirmado') {
      statusColor = Colors.green;
    }

    final Color payColor;
    final String payText;
    final String hiddenPayText;
    if (summary.isRefunded) {
      payColor = Colors.teal;
      payText = 'ESTORNADO';
      hiddenPayText = 'ESTORNADO';
    } else if (isCanceled && summary.hasPendingRefund) {
      payColor = Colors.amber.shade800;
      payText = 'ESTORNO PEND.';
      hiddenPayText = 'ESTORNO PEND.';
    } else if (isCanceled && summary.refundStatus == 'retido') {
      payColor = Colors.red.shade700;
      payText = 'RETIDO';
      hiddenPayText = 'RETIDO';
    } else if (summary.isOverpaid) {
      payColor = Colors.red.shade700;
      payText = summary.cardBadgeText;
      hiddenPayText = 'PAGO !';
    } else if (summary.status == 'pago') {
      payColor = Colors.green;
      payText = 'PAGO';
      hiddenPayText = 'PAGO';
    } else if (summary.status == 'parcial') {
      payColor = Colors.orange.shade800;
      payText = summary.cardBadgeText;
      hiddenPayText = 'PAGO R\$ ***';
    } else {
      payColor = Colors.grey;
      payText = 'A PAGAR';
      hiddenPayText = 'A PAGAR';
    }

    final bool showPartialPaidBelowTotal = !summary.isRefunded &&
        !(isCanceled && summary.hasPendingRefund) &&
        !(isCanceled && summary.refundStatus == 'retido') &&
        !summary.isOverpaid &&
        summary.status == 'parcial';

    bool isSelected = isDesktop &&
        _selectedAppointment?['id']?.toString() == data['id']?.toString();

    // Dados para abrir perfil do cliente
    final clientId = data['client_id'] ??
        data['clientId'] ??
        data['clienteId'] ??
        data['userId'];
    final rawClientNome =
        (data['client_name'] ?? data['name'] ?? '').toString().trim();
    final clientNomeRaw =
        (rawClientNome.toLowerCase() == 'null') ? '' : rawClientNome;
    // Se o campo contém email (ex: armazenado por engano), extrai o nome local
    final bool isEmailName =
        clientNomeRaw.contains('@') && !clientNomeRaw.contains(' ');
    final String clientDisplay = isEmailName
        ? 'Cliente' // enriquecimento falhou (rede?) — fallback neutro
        : (clientNomeRaw.isNotEmpty ? clientNomeRaw : 'Cliente');
    final String clientInitial =
        clientDisplay.isNotEmpty ? clientDisplay[0].toUpperCase() : '?';
    final String clientPhoto = (data['client_photo'] ?? '').toString().trim();

    final rawServiceNome = (data['service_name'] ??
            data['servico_nome'] ??
            data['servicoNome'] ??
            data['serviceName'] ??
            data['servico'] ??
            '')
        .toString()
        .trim();
    final serviceNome =
        (rawServiceNome.toLowerCase() == 'null') ? '' : rawServiceNome;
    final String serviceDisplay =
        serviceNome.isNotEmpty ? serviceNome : 'Serviço';
    final String professionalNome = data['professional_name'] ??
        data['profissional_nome'] ??
        data['professionalName'] ??
        data['profissionalNome'] ??
        'Não definido';

    final bool isClientVip =
        clientId != null && _vipClientIds.contains(clientId.toString());

    Future<void> openClientProfile() async {
      if (clientId == null) return;
      await showModalBottomSheet(
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
                  'nome': clientDisplay,
                  'name': clientDisplay,
                  'telefone': data['client_phone'] ??
                      data['telefone'] ??
                      data['whatsapp'] ??
                      'Não informado',
                  'email': data['client_email'] ?? data['email'] ?? '',
                  'origem': data['tipo'] == 'manual' ? 'manual' : 'app',
                  'totalGasto': total,
                  'visitas': 1,
                  // Passa a foto do cliente para exibição imediata
                  'foto': clientPhoto.isNotEmpty ? clientPhoto : null,
                  'foto_perfil': clientPhoto.isNotEmpty ? clientPhoto : null,
                  'photo_url': clientPhoto.isNotEmpty ? clientPhoto : null,
                },
                clientId: clientId.toString(),
                shopIdOverride: widget.shopId,
                onClose: () => Navigator.pop(ctx),
              ),
            ),
          ),
        ),
      );
      if (mounted) {
        _resolveVipForAppointments(
          [
            {'client_id': clientId.toString()}
          ],
          forceRefresh: true,
        );
      }
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
                shopCategory: _shopCategory,
                onEdit: () {
                  Navigator.pop(
                      context, 'edit'); // Fecha Detalhes para abrir Modal
                  _showQuickEntryModal(appointment: data);
                },
              ),
            ),
          );
          // Re-validação de NFS-e ao voltar dos detalhes
          final id = data['id'].toString();

          // Se o pop foi pelo botão Editar, o modal cuida do reload — não recarregar agora
          if (result != 'edit') {
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
        margin: const EdgeInsets.only(bottom: 6),
        decoration: BoxDecoration(
          color: highlighted
              ? AppColors.primaryPurple.withValues(alpha: 0.04)
              : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: isSelected
              ? Border.all(color: AppColors.primaryPurple, width: 2)
              : highlighted
                  ? Border.all(
                      color: AppColors.primaryPurple.withValues(alpha: 0.55),
                      width: 1.5)
                  : Border.all(color: Colors.transparent),
          boxShadow: [
            BoxShadow(
              color: Colors.grey.withValues(alpha: 0.08),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius:
              BorderRadius.circular(isSelected || highlighted ? 10 : 12),
          child: Container(
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(color: statusColor, width: 6),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Coluna de Horários e Avatar
                        SizedBox(
                          width: 44,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              ClientAvatarBadge(
                                initial: clientInitial,
                                photoUrl: clientPhoto,
                                isVip: isClientVip,
                                onTap: openClientProfile,
                              ),
                              const SizedBox(height: 6),
                              Text(
                                DateFormat('HH:mm').format(hora),
                                maxLines: 1,
                                softWrap: false,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 14,
                                  color: Colors.black87,
                                ),
                              ),
                              Text(
                                DateFormat('HH:mm').format(hora.add(Duration(
                                    minutes: int.tryParse(
                                            data['duration_min']?.toString() ??
                                                '30') ??
                                        30))),
                                maxLines: 1,
                                softWrap: false,
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: Colors.grey.shade600,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                DateFormat('dd/MM').format(hora),
                                maxLines: 1,
                                softWrap: false,
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.grey.shade400,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          width: 1,
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          color: Colors.grey.shade200,
                        ),
                        const SizedBox(width: 8),

                        // Infos Cliente
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                formatShortClientName(clientDisplay),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                  decoration: isCanceled
                                      ? TextDecoration.lineThrough
                                      : TextDecoration.none,
                                  color:
                                      isCanceled ? Colors.grey : Colors.black87,
                                ),
                              ),
                              const SizedBox(height: 2),
                              // Serviço
                              Text(
                                serviceDisplay,
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                                style: TextStyle(
                                  color: Colors.grey.shade600,
                                  fontSize: 11,
                                ),
                              ),
                              const SizedBox(height: 2),
                              // Profissional
                              Row(
                                children: [
                                  Icon(Icons.content_cut_rounded,
                                      size: 9, color: Colors.grey.shade400),
                                  const SizedBox(width: 3),
                                  Flexible(
                                    child: Text(
                                      professionalNome,
                                      overflow: TextOverflow.ellipsis,
                                      maxLines: 1,
                                      style: TextStyle(
                                        color: Colors.grey.shade500,
                                        fontSize: 10,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              if (const {
                                'sent',
                                'confirmed',
                                'failed',
                                'expired',
                              }.contains(data['whatsapp_reminder_status']
                                  ?.toString())) ...[
                                const SizedBox(height: 6),
                                // Tags de Confirmação (WhatsApp / Meta)
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 4,
                                  children: [
                                    if (data['whatsapp_reminder_status'] ==
                                        'sent')
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: Colors.grey
                                              .withValues(alpha: 0.12),
                                          borderRadius:
                                              BorderRadius.circular(4),
                                          border: Border.all(
                                              color: Colors.grey
                                                  .withValues(alpha: 0.4)),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(Icons.access_time,
                                                size: 10, color: Colors.grey),
                                            const SizedBox(width: 3),
                                            Flexible(
                                              child: Text(
                                                'MENSAGEM ENVIADA${data['whatsapp_reminder_sent_at'] != null ? ' · ${_formatHourMinute(data['whatsapp_reminder_sent_at'])}' : ''}',
                                                style: const TextStyle(
                                                    fontSize: 8,
                                                    fontWeight: FontWeight.w800,
                                                    color: Colors.grey),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    if (data['whatsapp_reminder_status'] ==
                                        'confirmed')
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF22C55E)
                                              .withValues(alpha: 0.12),
                                          borderRadius:
                                              BorderRadius.circular(4),
                                          border: Border.all(
                                              color: const Color(0xFF22C55E)
                                                  .withValues(alpha: 0.3)),
                                        ),
                                        child: const Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(Icons.check_circle,
                                                size: 10,
                                                color: Color(0xFF16A34A)),
                                            SizedBox(width: 3),
                                            Flexible(
                                              child: Text(
                                                  'AGENDAMENTO CONFIRMADO',
                                                  style: TextStyle(
                                                      fontSize: 8,
                                                      fontWeight:
                                                          FontWeight.w800,
                                                      color: Color(0xFF15803D)),
                                                  overflow:
                                                      TextOverflow.ellipsis),
                                            ),
                                          ],
                                        ),
                                      ),
                                    if (data['whatsapp_reminder_status'] ==
                                        'failed')
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFEF4444)
                                              .withValues(alpha: 0.12),
                                          borderRadius:
                                              BorderRadius.circular(4),
                                          border: Border.all(
                                              color: const Color(0xFFEF4444)
                                                  .withValues(alpha: 0.3)),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(Icons.warning_rounded,
                                                size: 10,
                                                color: Color(0xFFDC2626)),
                                            const SizedBox(width: 3),
                                            Flexible(
                                              child: Text(
                                                'FALHA NO ENVIO${data['whatsapp_reminder_failed_at'] != null ? ' · ${_formatHourMinute(data['whatsapp_reminder_failed_at'])}' : ''}',
                                                style: const TextStyle(
                                                    fontSize: 8,
                                                    fontWeight: FontWeight.w800,
                                                    color: Color(0xFFDC2626)),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    if (data['whatsapp_reminder_status'] ==
                                        'expired')
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: Colors.blue
                                              .withValues(alpha: 0.12),
                                          borderRadius:
                                              BorderRadius.circular(4),
                                          border: Border.all(
                                              color: Colors.blue
                                                  .withValues(alpha: 0.3)),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(Icons.flash_on,
                                                size: 10, color: Colors.blue),
                                            const SizedBox(width: 3),
                                            const Flexible(
                                              child: Text(
                                                'AGENDAMENTO DE OPORTUNIDADE',
                                                style: TextStyle(
                                                    fontSize: 8,
                                                    fontWeight: FontWeight.w800,
                                                    color: Colors.blue),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          width: 1,
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          color: Colors.grey.shade200,
                        ),
                        const SizedBox(width: 6),
                        // Valor e Status (exclusivo de pagamento)
                        SizedBox(
                          width: 68,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Builder(builder: (context) {
                                final double originalPrice = double.tryParse(
                                        data['total_price']?.toString() ??
                                            '0') ??
                                    0;
                                final double discountAmt = double.tryParse(
                                        data['discount_amount']?.toString() ??
                                            '0') ??
                                    0;
                                final double cDesc = double.tryParse(
                                        data['valor_com_desconto']
                                                ?.toString() ??
                                            '0') ??
                                    0;
                                final bool hasBd =
                                    data['birthday_discount_applied'] == true;
                                final bool hasCp =
                                    data['coupon_applied'] == true;
                                double discVal = 0;
                                if (discountAmt > 0.01) {
                                  discVal = discountAmt;
                                } else if (cDesc > 0 &&
                                    originalPrice > 0 &&
                                    cDesc < originalPrice - 0.01) {
                                  discVal = originalPrice - cDesc;
                                } else if (hasBd && originalPrice > 0) {
                                  final pct = double.tryParse(
                                          data['birthday_discount_percent']
                                                  ?.toString() ??
                                              '0') ??
                                      0;
                                  if (pct > 0)
                                    discVal = originalPrice * pct / 100;
                                } else if (hasCp && originalPrice > 0) {
                                  final pct = double.tryParse(
                                          data['coupon_discount_percent']
                                                  ?.toString() ??
                                              '0') ??
                                      0;
                                  if (pct > 0)
                                    discVal = originalPrice * pct / 100;
                                }
                                if (discVal < 0.01 || originalPrice < 0.01)
                                  return const SizedBox.shrink();
                                return ValueListenableBuilder<bool>(
                                  valueListenable:
                                      PrivacyService.instance.isHiddenNotifier,
                                  builder: (context, isHidden, _) => FittedBox(
                                    fit: BoxFit.scaleDown,
                                    alignment: Alignment.center,
                                    child: Text(
                                      isHidden
                                          ? "R\$ *****"
                                          : NumberFormat.currency(
                                                  locale: 'pt_BR',
                                                  symbol: 'R\$')
                                              .format(originalPrice),
                                      maxLines: 1,
                                      style: const TextStyle(
                                        fontSize: 10,
                                        color: Colors.grey,
                                        decoration: TextDecoration.lineThrough,
                                      ),
                                    ),
                                  ),
                                );
                              }),
                              ValueListenableBuilder<bool>(
                                valueListenable:
                                    PrivacyService.instance.isHiddenNotifier,
                                builder: (context, isHidden, _) => FittedBox(
                                  fit: BoxFit.scaleDown,
                                  alignment: Alignment.center,
                                  child: Text(
                                    isHidden
                                        ? "R\$ *****"
                                        : NumberFormat.currency(
                                                locale: 'pt_BR', symbol: 'R\$')
                                            .format(total),
                                    maxLines: 1,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14.5),
                                  ),
                                ),
                              ),
                              if (showPartialPaidBelowTotal) ...[
                                const SizedBox(height: 2),
                                ValueListenableBuilder<bool>(
                                  valueListenable:
                                      PrivacyService.instance.isHiddenNotifier,
                                  builder: (context, isHidden, _) => FittedBox(
                                    fit: BoxFit.scaleDown,
                                    alignment: Alignment.center,
                                    child: Text(
                                      isHidden
                                          ? 'Pago R\$ ***'
                                          : 'Pago ${formatCompactCurrency(summary.paidAmount)}',
                                      maxLines: 1,
                                      style: TextStyle(
                                        color: Colors.green.shade700,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 11.5,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                              if (data['birthday_discount_applied'] ==
                                  true) ...[
                                const SizedBox(height: 3),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 5, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: Colors.pink.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(
                                        color:
                                            Colors.pink.withValues(alpha: 0.3)),
                                  ),
                                  child: const Text('🎂 ANIV.',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                          fontSize: 7,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.pink)),
                                ),
                              ],
                              if (data['coupon_applied'] == true &&
                                  data['coupon_code'] != null) ...[
                                const SizedBox(height: 3),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 5, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: Colors.blue.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(
                                        color:
                                            Colors.blue.withValues(alpha: 0.3)),
                                  ),
                                  child: Text('🏷 ${data['coupon_code']}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          fontSize: 7,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.blue)),
                                ),
                              ],
                              if (!showPartialPaidBelowTotal) ...[
                                const SizedBox(height: 4),
                                FittedBox(
                                  fit: BoxFit.scaleDown,
                                  alignment: Alignment.center,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: payColor.withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(6),
                                      border: summary.isOverpaid
                                          ? Border.all(
                                              color: payColor.withValues(
                                                  alpha: 0.25))
                                          : null,
                                    ),
                                    child: ValueListenableBuilder<bool>(
                                      valueListenable: PrivacyService
                                          .instance.isHiddenNotifier,
                                      builder: (context, isHidden, _) => Text(
                                        isHidden ? hiddenPayText : payText,
                                        maxLines: 1,
                                        style: TextStyle(
                                          color: payColor,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 9,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (data['id'] != null)
                    ClientNotePreview(
                      appointmentId: data['id'].toString(),
                      shopId: (data['shop_id'] ?? widget.shopId).toString(),
                      clientName: clientDisplay,
                    ),
                ],
              ),
            ),
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
              color:
                  isSelected ? AppColors.primaryPurple : Colors.grey.shade200,
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
