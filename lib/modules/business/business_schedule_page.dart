import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';
import 'dart:async';
import '../../core/theme/app_colors.dart';
import 'appointment_details_page.dart';
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

class _BusinessSchedulePageState extends State<BusinessSchedulePage> {
  // --- CALENDÁRIO ---
  DateTime _focusedDay = DateTime.now();
  DateTime _selectedDay = DateTime.now();
  CalendarFormat _calendarFormat = CalendarFormat.month;

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

  @override
  void initState() {
    super.initState();
    // por padrão, começar a lista a partir de hoje sem carregar passado
    _startFromSelectedDay = true;
    _startFromDate = DateTime.now();
    _loadShopConfig();
    _loadMonthEvents();
    _loadAppointments();
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
    // Start periodic cache refresh to validate stale entries
    _cacheRefreshTimer = Timer.periodic(const Duration(minutes: 2), (_) {
      _refreshStaleCacheEntries();
    });
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
    // Load a wider window (previous, current and next month) to ensure calendar markers are present
    final startOfMonth = DateTime(_focusedDay.year, _focusedDay.month, 1)
        .subtract(const Duration(days: 35));
    final endOfMonth =
        DateTime(_focusedDay.year, _focusedDay.month + 1, 0, 23, 59, 59)
            .add(const Duration(days: 35));

    try {
      final snapshot = await sb.Supabase.instance.client
          .from('appointments')
          .select()
          .eq('shop_id', widget.shopId)
          .gte('scheduled_at', startOfMonth.toIso8601String())
          .lte('scheduled_at', endOfMonth.toIso8601String());

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
      var query = client.from('appointments').select().eq('shop_id', widget.shopId);

      // Simple implementation: load first page
      if (_startFromSelectedDay && _startFromDate != null && _weekEndDate != null) {
        query = query
          .gte('scheduled_at', _startFromDate!.toIso8601String())
          .lte('scheduled_at', _weekEndDate!.toIso8601String());
      } else if (_showOnlySelectedDay) {
        final start = DateTime(_selectedDay.year, _selectedDay.month, _selectedDay.day).subtract(const Duration(days: 7));
        final end = DateTime(_selectedDay.year, _selectedDay.month, _selectedDay.day).add(const Duration(days: 14, hours: 23, minutes: 59, seconds: 59));
        query = query
          .gte('scheduled_at', start.toIso8601String())
          .lte('scheduled_at', end.toIso8601String());
      } else {
        final start = DateTime(2020, 1, 1);
        query = query.gte('scheduled_at', start.toIso8601String());
      }

      final snapshot = await query.order('scheduled_at').limit(_perPage);

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
          .select()
          .eq('shop_id', widget.shopId)
          .gt('scheduled_at', lastDate)
          .order('scheduled_at')
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
          .select()
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

  // Filtra apenas agendamentos ativos (exclui cancelados)
  bool _shouldShowAppointment(Map<String, dynamic> data) {
    final status = (data['status'] ?? '').toString().toLowerCase();
    return status != 'cancelado';
  }

  // ðŸŽ¯ AÇÃO: IR PARA HOJE
  void _jumpToToday() {
    setState(() {
      _selectedDay = DateTime.now();
      _focusedDay = DateTime.now();
      _showOnlySelectedDay = true;
    });
    _loadAppointments();
  }

  // âœï¸ EDITAR AGENDAMENTO
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
                              .where((s) => s['is_active'] == true)
                              .toList()
                            ..sort((a, b) => (a['name'] ?? '')
                                .toString()
                                .compareTo((b['name'] ?? '').toString()))),
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
                                        '${sData['name']} - R\$ ${sData['price']}'),
                                  );
                                }).toList(),
                                onChanged: (value) {
                                  if (value != null) {
                                    final service = services
                                        .firstWhere((s) => s['id'].toString() == value);
                                    final sData = service;
                                    setModalState(() {
                                      selectedServiceId = value;
                                      selectedServiceName = sData['name'] ?? '';
                                      selectedServicePrice =
                                          (sData['price'] ?? 0).toDouble();
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
                      stream: sb.Supabase.instance.client
                          .from('employees')
                          .stream(primaryKey: ['id'])
                          .eq('shop_id', widget.shopId),
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
                                items: pros.map((pro) {
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
                                          pData['name'] ?? '';
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
                                      empData['horario_inicio'] ?? "08:00",
                                  endStr: empData['horario_fim'] ?? "18:00",
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
                              });
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

                    // Verificação de Conflito de Horário
                    if (selectedProfessionalId != null) {
                      final busy = await AvailabilityUtils.getBusyIntervals(
                        selectedProfessionalId!,
                        appointmentDate,
                        excludeDocId: data['id']?.toString(),
                      );

                      int duration = int.tryParse(
                              data['duracao_min']?.toString() ?? '30') ??
                          30;
                      int startMin =
                          appointmentTime.hour * 60 + appointmentTime.minute;

                      bool available = AvailabilityUtils.isSlotAvailable(
                          startMin, duration, busy);

                      if (!available) {
                        bool? confirm = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text("Conflito de Horário"),
                            content: const Text(
                                "Este profissional já possui um agendamento neste horário. Deseja agendar mesmo assim?"),
                            actions: [
                              TextButton(
                                  onPressed: () => Navigator.pop(ctx, false),
                                  child: const Text("NÃO")),
                              TextButton(
                                  onPressed: () => Navigator.pop(ctx, true),
                                  child: const Text("SIM, AGENDAR")),
                            ],
                          ),
                        );
                        if (confirm != true) return;
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
    final Map<String, dynamic>? editData = appointment;


    // Controladores básicos
    final TextEditingController nameController = TextEditingController(text: editData?['client_name'] ?? editData?['client_nome'] ?? '');
    final TextEditingController phoneController = TextEditingController(text: editData?['client_phone'] ?? editData?['telefone'] ?? '');
    final TextEditingController serviceController = TextEditingController(text: editData?['service_name'] ?? editData?['servico_nome'] ?? '');
    final TextEditingController valueController = TextEditingController();
    
    // Estado do Modal
    String? selectedClientId = editData?['client_id'] ?? editData?['clientId'];
    String? serviceId = editData?['service_id'] ?? editData?['servicoId'];
    int durationMin = editData?['duration_min'] ?? editData?['duracao_min'] ?? 30;
    String? selectedProfessionalId = editData?['professional_id'] ?? editData?['profissionalId'];
    String selectedProfessionalName = editData?['professional_name'] ?? editData?['profissional_nome'] ?? 'Selecione Profissional';
    DateTime manualDate = initialDate ?? _selectedDay;
    TimeOfDay manualTime = TimeOfDay.now();

    if (editData != null) {
      final dateStr = editData['scheduled_at'] as String?;
      if (dateStr != null) {
        manualDate = DateTime.parse(dateStr);
        manualTime = TimeOfDay.fromDateTime(manualDate);
      }
      double val = _safeParseValue(appointment!);
      valueController.text = val > 0 ? val.toString().replaceAll('.', ',') : '';
    }

    // --- REVISÃO / INTELIGÊNCIA INICIAL ---
    Map<String, dynamic>? suggestedService;
    Map<String, dynamic>? suggestedProfessional;
    bool isServiceConfirmed = false;
    bool isProfessionalConfirmed = false;

    Future<void> runInitialIntelligence() async {
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

        // Verifica disponibilidade e rankeia
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
        }
      }
    }

    try {
      await runInitialIntelligence();
    } catch (e) {
      debugPrint("Erro na inteligência do agendamento: $e");
    }

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
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
                                                size: 16,
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
                               stream: sb.Supabase.instance.client
                                   .from('employees')
                                   .stream(primaryKey: ['id'])
                                   .eq('shop_id', widget.shopId),
                               builder: (context, snapshot) {
                                 if (!snapshot.hasData) return const SizedBox(height: 40);
                                 final pros = snapshot.data!;
                                 
                                 return LayoutBuilder(builder: (context, constraints) {
                                   return Autocomplete<Map<String, dynamic>>(
                                     initialValue: TextEditingValue(
                                         text: selectedProfessionalId != null ? selectedProfessionalName : ''),
                                     optionsBuilder: (TextEditingValue textEditingValue) {
                                       if (textEditingValue.text.isEmpty) return pros;
                                       return pros.where((p) => (p['name'] ?? '')
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
                            // Horários
                            if (selectedProfessionalId != null) ...[
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
                                        startStr: empData['horario_inicio'] ?? "08:00",
                                        endStr: empData['horario_fim'] ?? "18:00",
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
                            ] else
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
                                    final busy = await AvailabilityUtils.getBusyIntervals(selectedProfessionalId!, manualDate, excludeDocId: appointment?['id']);
                                    int startMin = manualTime.hour * 60 + manualTime.minute;
                                    bool available = AvailabilityUtils.isSlotAvailable(startMin, durationMin, busy);
                                    if (!available) {
                                      bool? confirm = await showDialog<bool>(
                                        context: context,
                                        builder: (ctx) => AlertDialog(
                                          title: const Text("Conflito de Horário"),
                                          content: const Text("Este profissional já possui um agendamento. Prosseguir mesmo assim?"),
                                          actions: [
                                            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("NÃO")),
                                            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("SIM")),
                                          ],
                                        ),
                                      );
                                      if (confirm != true) return;
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
                                    'status': editData?['status'] ?? 'concluido',
                                    'scheduled_at': manualDateNormalized.toIso8601String(),
                                    if (appointment == null) 'created_at': DateTime.now().toIso8601String(),
                                  };

                                  try {
                                    if (appointment == null) {
                                      await sb.Supabase.instance.client.from('appointments').insert(appointmentData);
                                    } else {
                                      await sb.Supabase.instance.client.from('appointments').update(appointmentData).eq('id', appointment['id']);
                                    }

                                    ShopDataCacheService().invalidate(widget.shopId, 'appointments');

                                    if (!mounted) return;
                                    Navigator.pop(context);
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
    );
  }

  @override
  Widget build(BuildContext context) {
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

  // ðŸ“± LAYOUT MOBILE
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

  // ðŸ–¥ï¸ LAYOUT DESKTOP
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
                          // ðŸ†• Filtrar appointments baseado na aba selecionada
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

    // ðŸ†• Filtrar appointments baseado na aba selecionada
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
            CalendarFormat.twoWeeks: '2 Semanas',
            CalendarFormat.week: 'Semana'
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
                  DateTime(endOfWeek.year, endOfWeek.month, endOfWeek.day);
            });
            // Aplicar filtro imediato aos dados em cache e rolar para topo.
            _applyWeekFilterToCache();
            WidgetsBinding.instance.addPostFrameCallback((_) {
              try {
                _scrollController.animateTo(0.0,
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut);
              } catch (_) {}
            });
            // Buscar a semana no servidor em background e atualizar a lista quando retornar.
            _fetchWeekFromServer(_startFromDate!, _weekEndDate!);
          },
          onFormatChanged: (format) {
            if (isMobile) setState(() => _calendarFormat = format);
          },
          onPageChanged: (focusedDay) {
            final oldYear = _focusedDay.year;
            setState(() => _focusedDay = focusedDay);
            if (focusedDay.year != oldYear) {
              _fetchHolidays();
            }
            _loadMonthEvents();
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

        // Removed Ativos/Histórico tabs — schedule shows active appointments by default.

        if (_showOnlySelectedDay)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0),
            child: TextButton.icon(
              onPressed: () {
                setState(() => _showOnlySelectedDay = false);
                _loadAppointments();
              },
              icon: const Icon(Icons.list_alt, size: 16),
              label: const Text("Ver mês inteiro"),
              style: TextButton.styleFrom(foregroundColor: Colors.grey),
            ),
          )
      ],
    );
  }

  Widget _buildStatsSection() {
    final startWeek = _startFromDate ?? DateTime.now();
    // Usa _focusedDay para o mês exibido atualmente
    final startMonth = _focusedDay;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      color: Colors.transparent,
      child: StreamBuilder<double>(
        stream: _weeklyRevenueStream(startWeek),
        builder: (context, snapWeek) {
          final valWeek = snapWeek.data ?? 0.0;
          return StreamBuilder<double>(
            stream: _monthlyRevenueStream(startMonth),
            builder: (context, snapMonth) {
              final valMonth = snapMonth.data ?? 0.0;
              return Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start, // Alinhado à esquerda
                children: [
                  Text(
                    "Faturamento da semana: ${NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$').format(valWeek)}",
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 16),
                    textAlign: TextAlign.left,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    "Faturamento do mês: ${NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$').format(valMonth)}",
                    style: const TextStyle(
                        fontWeight: FontWeight.normal, fontSize: 14),
                    textAlign: TextAlign.left,
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  // Stream do faturamento do mês base
  Stream<double> _monthlyRevenueStream(DateTime dateInMonth) {
    final start = DateTime(dateInMonth.year, dateInMonth.month, 1, 0, 0, 0);
    final end = DateTime(dateInMonth.year, dateInMonth.month + 1, 1, 0, 0, 0)
        .subtract(const Duration(seconds: 1));
    return sb.Supabase.instance.client
        .from('appointments')
        .stream(primaryKey: ['id'])
        .eq('shop_id', widget.shopId)
        .map((dataList) {
      double sum = 0.0;
      for (var data in dataList) {
        final dateStr = data['scheduled_at'] as String?;
        if (dateStr == null) continue;
        final date = DateTime.parse(dateStr);
        if (date.isBefore(start) || date.isAfter(end)) continue;

        final status = (data['status'] ?? '').toString().toLowerCase();
        if (status == 'cancelado') continue;
        String vp = data['paid_amount']?.toString() ?? data['valor_pago']?.toString() ?? '';
        String vt = data['total_price']?.toString() ?? data['valor_total']?.toString() ?? '';
        String v = data['price']?.toString() ?? data['valor']?.toString() ?? '';
        String finalStr = vp.trim().isNotEmpty
            ? vp
            : (vt.trim().isNotEmpty ? vt : (v.trim().isNotEmpty ? v : '0'));
        sum += double.tryParse(finalStr.replaceAll(',', '.')) ?? 0.0;
      }
      return sum;
    });
  }

  // Stream do faturamento da semana com base em startDate (7 dias)
  Stream<double> _weeklyRevenueStream(DateTime startDate) {
    final start =
        DateTime(startDate.year, startDate.month, startDate.day, 0, 0, 0);
    final end =
        start.add(const Duration(days: 7)).subtract(const Duration(seconds: 1));
    return sb.Supabase.instance.client
        .from('appointments')
        .stream(primaryKey: ['id'])
        .eq('shop_id', widget.shopId)
        .map((dataList) {
      double sum = 0.0;
      for (var data in dataList) {
        final dateStr = data['scheduled_at'] as String?;
        if (dateStr == null) continue;
        final date = DateTime.parse(dateStr);
        if (date.isBefore(start) || date.isAfter(end)) continue;

        final status = (data['status'] ?? '').toString().toLowerCase();
        if (status == 'cancelado') continue;
        String vp = data['paid_amount']?.toString() ?? data['valor_pago']?.toString() ?? '';
        String vt = data['total_price']?.toString() ?? data['valor_total']?.toString() ?? '';
        String v = data['price']?.toString() ?? data['valor']?.toString() ?? '';
        String finalStr = vp.trim().isNotEmpty
            ? vp
            : (vt.trim().isNotEmpty ? vt : (v.trim().isNotEmpty ? v : '0'));
        sum += double.tryParse(finalStr.replaceAll(',', '.')) ?? 0.0;
      }
      return sum;
    });
  }

  // --- CALCULADORAS ---
  double _safeParseValue(Map<String, dynamic> data) {
    dynamic val = data['total_value'] ?? data['total_price'] ?? data['valor_total'] ?? data['price'] ?? data['valor'] ?? data['labor_value'] ?? data['preco'] ?? 0;
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
      // limit refresh batch to avoid many reads
      final batch = staleIds.take(20).toList();
      for (var id in batch) {
        try {
          final doc = await sb.Supabase.instance.client
              .from('appointments')
              .select()
              .eq('id', id)
              .maybeSingle();
          if (doc != null) {
            // update cache with fresh data
            _addToCache(doc);
          } else {
            // remove missing doc from cache and from visible list
            _docCache.remove(id);
            _cacheAccess.remove(id);
            _appointments.removeWhere((d) => d['id'].toString() == id);
          }
        } catch (_) {
          // ignore single failures
        }
      }
    } catch (e) {
      debugPrint('Erro ao refresh cache: $e');
    }
  }

  @override
  void dispose() {
    _cacheRefreshTimer?.cancel();
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
          .select()
          .eq('shop_id', widget.shopId)
          .gte('scheduled_at', start.toIso8601String())
          .lte('scheduled_at', end.toIso8601String())
          .order('scheduled_at');

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
          final bool isManual =
              (data['type'] ?? data['tipo'] ?? '').toString().toLowerCase() == 'manual';
          final bool hasClient =
              data['client_id'] != null;
          if (!isManual && !hasClient) continue;
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

    bool isCanceled = status == 'cancelado';
    bool quitado = (pago >= total && total > 0) || status == 'concluido';

    Color statusColor =
        isCanceled ? Colors.red : (quitado ? Colors.green : Colors.orange);
    String statusText =
        isCanceled ? "CANCELADO" : (quitado ? "PAGO" : "PENDENTE");

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
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => AppointmentDetailsPage(
                appointmentDoc: data,
                onEdit: () {
                  Navigator.pop(context); // Fecha Detalhes para abrir Modal
                  _showQuickEntryModal(appointment: data);
                },
              ),
            ),
          );
          // Limpa cache específico do documento para evitar "flash" se foi deletado
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
                      // Hora
                      Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            DateFormat('HH:mm').format(hora),
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 16,
                              color: Colors.black87,
                            ),
                          ),
                          Text(
                            DateFormat('dd/MM').format(hora),
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey.shade500,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(width: 16),
                      Container(
                          width: 1, height: 30, color: Colors.grey.shade200),
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
                            // Tags do cliente
                            if (clientId != null)
                              FutureBuilder<Map<String, dynamic>?>(
                                future: sb.Supabase.instance.client
                                    .from('clients')
                                    .select()
                                    .eq('id', clientId.toString())
                                    .maybeSingle(),
                                builder: (context, snapshot) {
                                  if (!snapshot.hasData ||
                                      snapshot.data == null) {
                                    return const SizedBox.shrink();
                                  }
                                  final clientData = snapshot.data!;
                                  final List<String> tags = List<String>.from(
                                      clientData['manualTags'] ?? []);
                                  if (tags.isEmpty) {
                                    return const SizedBox.shrink();
                                  }

                                  return Padding(
                                    padding: const EdgeInsets.only(top: 2),
                                    child: Wrap(
                                      spacing: 4,
                                      runSpacing: 2,
                                      children: tags.map((tag) {
                                        return Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: AppColors.primaryPurple
                                                .withValues(alpha: 0.1),
                                            borderRadius:
                                                BorderRadius.circular(4),
                                          ),
                                          child: Text(
                                            tag,
                                            style: const TextStyle(
                                              color: AppColors.primaryPurple,
                                              fontSize: 8,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        );
                                      }).toList(),
                                    ),
                                  );
                                },
                              ),
                             const SizedBox(height: 2),
                             Text(
                               serviceDisplay,
                               style: TextStyle(
                                   color: Colors.grey.shade600, fontSize: 13, fontWeight: FontWeight.w500),
                               overflow: TextOverflow.ellipsis,
                             ),
                             const SizedBox(height: 2),
                             Row(
                               children: [
                                 Icon(Icons.person_outline, size: 10, color: Colors.grey.shade400),
                                 const SizedBox(width: 4),
                                 Expanded(
                                   child: Text(
                                     professionalNome,
                                     style: TextStyle(
                                         color: Colors.grey.shade500, fontSize: 11),
                                     overflow: TextOverflow.ellipsis,
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
                          Text(
                            "R\$ ${total.toStringAsFixed(2)}",
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 14),
                          ),
                          const SizedBox(height: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: statusColor.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              statusText,
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                                color: statusColor,
                              ),
                            ),
                          ),
                        ],
                      ),

                      // Botão de perfil do cliente
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: openClientProfile,
                        child: Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color:
                                AppColors.primaryPurple.withValues(alpha: 0.1),
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: Text(
                              clientInitial,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: AppColors.primaryPurple,
                              ),
                            ),
                          ),
                        ),
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

  // Deleção agora ocorre na tela de detalhes (AppointmentDetailsPage).
}
