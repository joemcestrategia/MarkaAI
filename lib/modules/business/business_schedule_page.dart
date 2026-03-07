// ignore_for_file: use_build_context_synchronously
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:async';
import '../../core/theme/app_colors.dart';
import 'appointment_details_page.dart';
import '../clients/client_details_page.dart';

class BusinessSchedulePage extends StatefulWidget {
  final String shopId;
  const BusinessSchedulePage({super.key, required this.shopId});

  @override
  State<BusinessSchedulePage> createState() => _BusinessSchedulePageState();
}

class _BusinessSchedulePageState extends State<BusinessSchedulePage> {
  // --- CALENDÃRIO ---
  DateTime _focusedDay = DateTime.now();
  DateTime _selectedDay = DateTime.now();
  CalendarFormat _calendarFormat = CalendarFormat.month;

  // Eventos por dia (para pontinho laranja)
  Map<DateTime, List<String>> _events = {};
  // Keys para cada cabeçalho de dia (permitir scroll até o header)
  final Map<DateTime, GlobalKey> _dayKeys = {};

  // --- CONTROLE DE LISTA ---
  final ScrollController _scrollController = ScrollController();
  List<DocumentSnapshot> _appointments = [];
  // Cache simples por id para acesso rápido e evitar duplicatas
  final Map<String, DocumentSnapshot> _docCache = {};
  final Map<String, DateTime> _cacheAccess = {};
  final int _cacheMaxEntries = 300; // limite de entradas no cache
  final Duration _cacheTTL =
      const Duration(minutes: 5); // tempo antes de validar novamente
  Timer? _cacheRefreshTimer;
  bool _isLoading = false;
  bool _hasMore = true;
  bool _hasMorePast =
      true; // indica se há mais documentos no passado para carregar
  DocumentSnapshot? _lastDocument;
  DocumentSnapshot? _firstDocument;
  final int _perPage = 20;

  // --- LÃ“GICA DE VISUALIZAÇÃO ---
  bool _showOnlySelectedDay = true;
  DocumentSnapshot? _selectedAppointment;
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
    _loadMonthEvents();
    _loadAppointments();
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

  // Carregar eventos do mês para marcar no calendário
  Future<void> _loadMonthEvents() async {
    // Load a wider window (previous, current and next month) to ensure calendar markers are present
    final startOfMonth = DateTime(_focusedDay.year, _focusedDay.month, 1)
        .subtract(const Duration(days: 35));
    final endOfMonth =
        DateTime(_focusedDay.year, _focusedDay.month + 1, 0, 23, 59, 59)
            .add(const Duration(days: 35));

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('appointments')
          .where('shopId', isEqualTo: widget.shopId)
          .where('data_agendamento',
              isGreaterThanOrEqualTo: Timestamp.fromDate(startOfMonth))
          .where('data_agendamento',
              isLessThanOrEqualTo: Timestamp.fromDate(endOfMonth))
          .get();

      final Map<DateTime, List<String>> events = {};
      for (var doc in snapshot.docs) {
        final data = doc.data();
        final timestamp = data['data_agendamento'] as Timestamp?;
        if (timestamp == null) continue;
        final status = (data['status'] ?? '').toString().toLowerCase();
        if (status == 'cancelado') continue;

        final bool isManual =
            (data['tipo'] ?? '').toString().toLowerCase() == 'manual';
        final bool hasClient = (data['clientId'] ?? data['clienteId']) != null;
        if (!isManual && !hasClient) continue;

        final date = timestamp.toDate();
        final dateKey = DateTime(date.year, date.month, date.day);
        events[dateKey] = (events[dateKey] ?? [])..add(doc.id);
      }

      if (mounted) {
        // Merge events to avoid losing markers already loaded for other months
        setState(() {
          final merged = Map<DateTime, List<String>>.from(_events);
          events.forEach((k, v) {
            final existing = merged[k] ?? [];
            final union = [...existing];
            for (var id in v) {
              if (!union.contains(id)) union.add(id);
            }
            merged[k] = union;
          });
          _events = merged;
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

  // ðŸ”„ CARREGAMENTO PRINCIPAL
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
      Query query = _buildQuery();
      // If query is week-based, load the whole week; otherwise limit to _perPage
      final snapshot = await ((_startFromSelectedDay &&
              _startFromDate != null &&
              _weekEndDate != null)
          ? query.get()
          : query.limit(_perPage).get());

      if (mounted) {
        setState(() {
          if (snapshot.docs.isNotEmpty) {
            _firstDocument = snapshot.docs.first;
            _lastDocument = snapshot.docs.last;
            // update cache and list avoiding duplicates
            _appointments = [];
            for (var d in snapshot.docs) {
              _addToCache(d);
              _appointments.add(d);
            }
          }
          if (snapshot.docs.length < _perPage) _hasMore = false;
          // if we received less than perPage and the first doc is the earliest known, stop past loading
          if (snapshot.docs.length < _perPage) _hasMorePast = false;
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
      Query query = _buildQuery();
      if (_lastDocument == null) {
        setState(() => _isLoading = false);
        return;
      }
      final snapshot =
          await query.startAfterDocument(_lastDocument!).limit(_perPage).get();

      if (mounted) {
        setState(() {
          if (snapshot.docs.isNotEmpty) {
            _lastDocument = snapshot.docs.last;
            for (var d in snapshot.docs) {
              if (!_docCache.containsKey(d.id)) {
                _addToCache(d);
                _appointments.add(d);
              } else {
                // update access time
                _cacheAccess[d.id] = DateTime.now();
              }
            }
          }
          if (snapshot.docs.length < _perPage) _hasMore = false;
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
      Query base = _buildQuery();
      if (_firstDocument == null) {
        setState(() => _isLoading = false);
        return;
      }

      // buscamos documentos anteriores ao primeiro carregado, ordenados desc para pegar os mais próximos
      final snapshot = await base
          .orderBy('data_agendamento', descending: true)
          .endBeforeDocument(_firstDocument!)
          .limit(_perPage)
          .get();

      if (mounted) {
        setState(() {
          if (snapshot.docs.isNotEmpty) {
            // inserir na frente (reverter para ordem asc)
            final newDocs = snapshot.docs.reversed.toList();
            // add to cache and to list avoiding duplicates
            for (var d in newDocs) {
              if (!_docCache.containsKey(d.id)) {
                _addToCache(d);
              }
            }
            // build merged list preserving order
            final merged = <DocumentSnapshot>[];
            for (var d in newDocs) {
              if (!_appointments.any((a) => a.id == d.id)) merged.add(d);
            }
            _appointments = [...merged, ..._appointments];
            _firstDocument = _appointments.first;
          }
          if (snapshot.docs.length < _perPage) _hasMorePast = false;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Erro ao carregar antigos: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Query _buildQuery() {
    Query query = FirebaseFirestore.instance
        .collection('appointments')
        .where('shopId', isEqualTo: widget.shopId);

    // If user selected a week start, load only that week (inclusive)
    if (_startFromSelectedDay &&
        _startFromDate != null &&
        _weekEndDate != null) {
      final start = DateTime(_startFromDate!.year, _startFromDate!.month,
          _startFromDate!.day, 0, 0, 0);
      final end = DateTime(_weekEndDate!.year, _weekEndDate!.month,
          _weekEndDate!.day, 23, 59, 59);
      return query
          .where('data_agendamento',
              isGreaterThanOrEqualTo: Timestamp.fromDate(start))
          .where('data_agendamento',
              isLessThanOrEqualTo: Timestamp.fromDate(end))
          .orderBy('data_agendamento');
    }

    if (_showOnlySelectedDay) {
      // Expand window around selected day to allow scrolling multiple days while keeping "day-focused" behavior.
      final start =
          DateTime(_selectedDay.year, _selectedDay.month, _selectedDay.day)
              .subtract(const Duration(days: 7));
      final end = DateTime(
              _selectedDay.year, _selectedDay.month, _selectedDay.day)
          .add(const Duration(days: 14, hours: 23, minutes: 59, seconds: 59));
      return query
          .where('data_agendamento',
              isGreaterThanOrEqualTo: Timestamp.fromDate(start))
          .where('data_agendamento',
              isLessThanOrEqualTo: Timestamp.fromDate(end))
          .orderBy('data_agendamento');
    } else {
      // For the "month" / full view, don't restrict to the first day of current month.
      // Use a broad start date so older months load when paginating.
      final start = DateTime(2020, 1, 1);
      return query
          .where('data_agendamento',
              isGreaterThanOrEqualTo: Timestamp.fromDate(start))
          .orderBy('data_agendamento');
    }
  }

  // Filtra apenas agendamentos ativos (exclui cancelados)
  bool _shouldShowAppointment(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>?;
    if (data == null) return false;
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
  void _showEditDialog(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;

    final TextEditingController nameController =
        TextEditingController(text: data['client_nome'] ?? '');
    String? selectedServiceId = data['servicoId'];
    String selectedServiceName = data['servico_nome'] ?? '';
    double selectedServicePrice = _safeParseValue(doc);

    final TextEditingController valueController = TextEditingController(
        text: selectedServicePrice.toStringAsFixed(2).replaceAll('.', ','));
    final TextEditingController paidController = TextEditingController(
        text: (data['valor_pago']?.toString() ?? '0').replaceAll('.', ','));

    DateTime appointmentDate = (data['data_agendamento'] as Timestamp).toDate();
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
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2030),
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
                    StreamBuilder<QuerySnapshot>(
                      stream: FirebaseFirestore.instance
                          .collection('services')
                          .where('shopId', isEqualTo: widget.shopId)
                          .where('ativo', isEqualTo: true)
                          .orderBy('nome')
                          .snapshots(),
                      builder: (context, snapshot) {
                        if (!snapshot.hasData) {
                          return const CircularProgressIndicator();
                        }
                        final services = snapshot.data!.docs;

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
                                  final sData =
                                      service.data() as Map<String, dynamic>;
                                  return DropdownMenuItem<String>(
                                    value: service.id,
                                    child: Text(
                                        '${sData['nome']} - R\$ ${sData['preco']}'),
                                  );
                                }).toList(),
                                onChanged: (value) {
                                  if (value != null) {
                                    final service = services
                                        .firstWhere((s) => s.id == value);
                                    final sData =
                                        service.data() as Map<String, dynamic>;
                                    setModalState(() {
                                      selectedServiceId = value;
                                      selectedServiceName = sData['nome'] ?? '';
                                      selectedServicePrice =
                                          (sData['preco'] ?? 0).toDouble();
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

                    double valorTotal = double.tryParse(
                            valueController.text.replaceAll(',', '.')) ??
                        0.0;

                    double valorPago = double.tryParse(
                            paidController.text.replaceAll(',', '.')) ??
                        0.0;

                    try {
                      await FirebaseFirestore.instance
                          .collection('appointments')
                          .doc(doc.id)
                          .update({
                        'client_nome': nameController.text.trim(),
                        'servico_nome': selectedServiceName.isEmpty
                            ? 'Serviço'
                            : selectedServiceName,
                        if (selectedServiceId != null)
                          'servicoId': selectedServiceId,
                        'valor_total': valorTotal,
                        'valor': valorTotal,
                        'valor_pago': valorPago,
                        'restante_a_pagar': valorTotal - valorPago,
                        'status': selectedStatus,
                        'data_agendamento': Timestamp.fromDate(appointmentDate),
                        'editado_em': FieldValue.serverTimestamp(),
                      });

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

  // âž• MODAL DE LANÇAMENTO
  void _showManualEntryDialog({DateTime? initialDate}) {
    final TextEditingController nameController = TextEditingController();
    final TextEditingController serviceController = TextEditingController();
    final TextEditingController valueController = TextEditingController();
    DateTime manualDate = initialDate ?? _selectedDay;
    TimeOfDay manualTime = const TimeOfDay(hour: 8, minute: 0);

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return AlertDialog(
              title: Row(
                children: const [
                  Icon(Icons.flash_on, color: Colors.orange),
                  SizedBox(width: 8),
                  Text("Lançamento Rápido"),
                ],
              ),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    InkWell(
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: manualDate,
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2030),
                        );
                        if (picked != null) {
                          setModalState(() => manualDate = picked);
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
                              DateFormat('dd/MM/yyyy').format(manualDate),
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
                    // Hora do agendamento (novo)
                    InkWell(
                      onTap: () async {
                        final picked = await showTimePicker(
                            context: context, initialTime: manualTime);
                        if (picked != null) {
                          setModalState(() => manualTime = picked);
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
                              manualTime.format(context),
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            const Icon(Icons.access_time,
                                size: 18, color: AppColors.primaryPurple),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
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
                    TextField(
                      controller: serviceController,
                      decoration: InputDecoration(
                        labelText: 'Serviço',
                        filled: true,
                        fillColor: Colors.grey.shade50,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: valueController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: 'Valor (R\$)',
                        prefixText: "R\$ ",
                        filled: true,
                        fillColor: Colors.grey.shade50,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide.none,
                        ),
                      ),
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
                    if (nameController.text.isEmpty ||
                        valueController.text.isEmpty) {
                      return;
                    }
                    double valor = double.tryParse(
                            valueController.text.replaceAll(',', '.')) ??
                        0.0;

                    // Normalize date + time to local to avoid timezone shifts when storing.
                    final DateTime manualDateNormalized = DateTime(
                        manualDate.year,
                        manualDate.month,
                        manualDate.day,
                        manualTime.hour,
                        manualTime.minute,
                        0);

                    final ref = await FirebaseFirestore.instance
                        .collection('appointments')
                        .add({
                      'shopId': widget.shopId,
                      'client_nome': nameController.text,
                      'servico_nome': serviceController.text.isEmpty
                          ? 'Avulso'
                          : serviceController.text,
                      'valor_total': valor,
                      'valor': valor,
                      'valor_pago': valor,
                      'status': 'concluido',
                      'data_agendamento':
                          Timestamp.fromDate(manualDateNormalized),
                      'criado_em': FieldValue.serverTimestamp(),
                      'tipo': 'manual',
                    });

                    // Fetch the newly created document (single read) and update UI locally
                    final newDoc = await ref.get();

                    if (!mounted) return;
                    Navigator.pop(context);

                    // Re-load to ensure correct ordering if date has changed
                    _loadAppointments();
                    _loadMonthEvents();

                    setState(() {
                      // Update events map to show marker on calendar without reloading whole month instantly
                      final dateKey = DateTime(manualDateNormalized.year,
                          manualDateNormalized.month, manualDateNormalized.day);
                      final existing = _events[dateKey] ?? [];
                      if (!existing.contains(newDoc.id)) {
                        existing.add(newDoc.id);
                        _events[dateKey] = existing;
                      }
                    });
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
                  onPressed: _showManualEntryDialog,
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
                  onPressed: _showManualEntryDialog,
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
                onClose: () {
                  setState(() => _selectedAppointment = null);
                  _loadAppointments();
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
        final ts = (doc.data() as Map<String, dynamic>)['data_agendamento']
            as Timestamp?;
        if (ts == null) return false;
        final d = ts.toDate();
        final dd = DateTime(d.year, d.month, d.day);
        return !dd.isBefore(start); // keep date >= start
      }).toList();
    }

    if (filteredAppointments.isEmpty) {
      return SliverFillRemaining(child: _buildEmptyState());
    }
    // Group by day and flatten into list of widgets (header + cards)
    final Map<DateTime, List<DocumentSnapshot>> grouped = {};
    for (var doc in filteredAppointments) {
      final data = doc.data() as Map<String, dynamic>;
      final ts = data['data_agendamento'] as Timestamp?;
      if (ts == null) continue;
      final d = ts.toDate();
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
                onPressed: () => _showManualEntryDialog(initialDate: key),
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
            setState(() => _focusedDay = focusedDay);
            _loadMonthEvents();
          },
          calendarBuilders: CalendarBuilders(
            markerBuilder: (context, day, events) {
              if (events.isNotEmpty) {
                return Positioned(
                  bottom: 1,
                  child: Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                      color: Colors.orange,
                      shape: BoxShape.circle,
                    ),
                  ),
                );
              }
              return null;
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

        // Removed Ativos/Histórico tabs â€” schedule shows active appointments by default.

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
    return FirebaseFirestore.instance
        .collection('appointments')
        .where('shopId', isEqualTo: widget.shopId)
        .where('data_agendamento',
            isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .where('data_agendamento', isLessThanOrEqualTo: Timestamp.fromDate(end))
        .snapshots()
        .map((snap) {
      double sum = 0.0;
      for (var doc in snap.docs) {
        final data = doc.data();
        final status = (data['status'] ?? '').toString().toLowerCase();
        if (status == 'cancelado') continue;
        sum += double.tryParse(data['valor_pago']?.toString() ??
                data['valor_total']?.toString() ??
                data['valor']?.toString() ??
                '0') ??
            0;
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
    return FirebaseFirestore.instance
        .collection('appointments')
        .where('shopId', isEqualTo: widget.shopId)
        .where('data_agendamento',
            isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .where('data_agendamento', isLessThanOrEqualTo: Timestamp.fromDate(end))
        .snapshots()
        .map((snap) {
      double sum = 0.0;
      for (var doc in snap.docs) {
        final data = doc.data();
        final status = (data['status'] ?? '').toString().toLowerCase();
        if (status == 'cancelado') continue;
        sum += double.tryParse(data['valor_pago']?.toString() ??
                data['valor_total']?.toString() ??
                data['valor']?.toString() ??
                '0') ??
            0;
      }
      return sum;
    });
  }

  // --- CALCULADORAS ---
  double _safeParseValue(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    dynamic val = data['valor_total'] ?? data['valor'];
    if (val == null) return 0.0;
    if (val is num) return val.toDouble();
    if (val is String) return double.tryParse(val.replaceAll(',', '.')) ?? 0.0;
    return 0.0;
  }

  // -----------------------
  // Cache helpers
  // -----------------------
  void _addToCache(DocumentSnapshot doc) {
    _docCache[doc.id] = doc;
    _cacheAccess[doc.id] = DateTime.now();
    _pruneCacheIfNeeded();
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
      _appointments.removeWhere((d) => d.id == oldest.key);
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
          final docRef =
              FirebaseFirestore.instance.collection('appointments').doc(id);
          final snap = await docRef.get();
          if (snap.exists) {
            // update cache with fresh snapshot
            _addToCache(snap);
          } else {
            // remove missing doc from cache and from visible list
            _docCache.remove(id);
            _cacheAccess.remove(id);
            _appointments.removeWhere((d) => d.id == id);
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
      final snap = await FirebaseFirestore.instance
          .collection('appointments')
          .where('shopId', isEqualTo: widget.shopId)
          .where('data_agendamento',
              isGreaterThanOrEqualTo: Timestamp.fromDate(start))
          .where('data_agendamento',
              isLessThanOrEqualTo: Timestamp.fromDate(end))
          .orderBy('data_agendamento')
          .get();

      if (!mounted) return;
      setState(() {
        // replace visible appointments with fresh week data
        _appointments = snap.docs;
        // update cache and cursors
        for (var d in snap.docs) {
          _addToCache(d);
        }
        if (_appointments.isNotEmpty) {
          _firstDocument = _appointments.first;
          _lastDocument = _appointments.last;
        }
        // update events for this week
        for (var d in snap.docs) {
          final data = d.data();
          final ts = data['data_agendamento'] as Timestamp?;
          if (ts == null) continue;
          final status = (data['status'] ?? '').toString().toLowerCase();
          if (status == 'cancelado') continue;
          final bool isManual =
              (data['tipo'] ?? '').toString().toLowerCase() == 'manual';
          final bool hasClient =
              (data['clientId'] ?? data['clienteId']) != null;
          if (!isManual && !hasClient) continue;
          final date = ts.toDate();
          final dateKey = DateTime(date.year, date.month, date.day);
          final existing = _events[dateKey] ?? [];
          if (!existing.contains(d.id)) {
            existing.add(d.id);
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
        DateTime(_weekEndDate!.year, _weekEndDate!.month, _weekEndDate!.day);

    final filtered = _docCache.values.where((doc) {
      final data = doc.data() as Map<String, dynamic>?;
      if (data == null) return false;
      final ts = data['data_agendamento'] as Timestamp?;
      if (ts == null) return false;
      final d = ts.toDate();
      final dd = DateTime(d.year, d.month, d.day);
      return !dd.isBefore(start) && !dd.isAfter(end);
    }).toList();

    // sort by date asc
    filtered.sort((a, b) {
      final da =
          (a.data() as Map<String, dynamic>)['data_agendamento'] as Timestamp;
      final db =
          (b.data() as Map<String, dynamic>)['data_agendamento'] as Timestamp;
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

  Widget _buildAppointmentCard(DocumentSnapshot doc,
      {required bool isDesktop}) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
    DateTime hora = (data['data_agendamento'] as Timestamp).toDate();

    double total = _safeParseValue(doc);
    double pago = double.tryParse(data['valor_pago']?.toString() ?? "0") ?? 0;
    String status = data['status']?.toString().toLowerCase() ?? '';

    bool isCanceled = status == 'cancelado';
    bool quitado = (pago >= total && total > 0) || status == 'concluido';

    Color statusColor =
        isCanceled ? Colors.red : (quitado ? Colors.green : Colors.orange);
    String statusText =
        isCanceled ? "CANCELADO" : (quitado ? "PAGO" : "PENDENTE");

    bool isSelected = isDesktop && _selectedAppointment?.id == doc.id;

    // Dados para abrir perfil do cliente
    final clientId = data['clientId'] ?? data['clienteId'] ?? doc.id;
    final clientNome = data['client_nome'] ?? data['cliente_nome'] ?? 'Cliente';
    final String clientInitial =
        clientNome.isNotEmpty ? clientNome[0].toUpperCase() : '?';

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
                      'Não informado',
                  'email': data['client_email'] ?? '',
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
            _selectedAppointment = doc;
          });
        } else {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => AppointmentDetailsPage(appointmentDoc: doc),
            ),
          );
          _loadAppointments();
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
                            GestureDetector(
                              onTap: openClientProfile,
                              child: Text(
                                clientNome,
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                  decoration: isCanceled
                                      ? TextDecoration.lineThrough
                                      : TextDecoration.underline,
                                  color: isCanceled
                                      ? Colors.grey
                                      : AppColors.primaryPurple,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              data['servico_nome'] ?? "Serviço",
                              style: TextStyle(
                                  color: Colors.grey.shade600, fontSize: 13),
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
                          if (data['client_phone'] != null ||
                              data['telefone'] != null) ...[
                            const SizedBox(height: 6),
                            GestureDetector(
                              onTap: () async {
                                final phone =
                                    (data['client_phone'] ?? data['telefone'])
                                        .toString()
                                        .replaceAll(RegExp(r'\D'), '');
                                final url = 'https://wa.me/$phone';
                                if (await canLaunchUrl(Uri.parse(url))) {
                                  await launchUrl(Uri.parse(url));
                                } else {
                                  if (!context.mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                        content: Text(
                                            'Não foi possível abrir o WhatsApp')),
                                  );
                                }
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: Colors.green.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.chat_rounded,
                                        color: Colors.green, size: 10),
                                    SizedBox(width: 3),
                                    Text('WhatsApp',
                                        style: TextStyle(
                                            color: Colors.green,
                                            fontSize: 9,
                                            fontWeight: FontWeight.w800)),
                                  ],
                                ),
                              ),
                            ),
                          ],
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
