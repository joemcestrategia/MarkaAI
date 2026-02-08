import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';
import '../../core/theme/app_colors.dart';
import 'appointment_details_page.dart';

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

  // --- CONTROLE DE LISTA ---
  final ScrollController _scrollController = ScrollController();
  List<DocumentSnapshot> _appointments = [];
  bool _isLoading = false;
  bool _hasMore = true;
  DocumentSnapshot? _lastDocument;
  final int _perPage = 20;

  // --- LÓGICA DE VISUALIZAÇÃO ---
  bool _showOnlySelectedDay = true;
  DocumentSnapshot? _selectedAppointment;
  
  // 🆕 ABAS: Ativos ou Histórico
  int _selectedTab = 0; // 0 = Ativos, 1 = Histórico

  @override
  void initState() {
    super.initState();
    _loadMonthEvents();
    _loadAppointments();
    _scrollController.addListener(() {
      if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent * 0.9) {
        _loadMoreAppointments();
      }
    });
  }
  
  // Carregar eventos do mês para marcar no calendário
  Future<void> _loadMonthEvents() async {
    final startOfMonth = DateTime(_focusedDay.year, _focusedDay.month, 1);
    final endOfMonth = DateTime(_focusedDay.year, _focusedDay.month + 1, 0, 23, 59, 59);
    
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('appointments')
          .where('shopId', isEqualTo: widget.shopId)
          .where('data_agendamento', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfMonth))
          .where('data_agendamento', isLessThanOrEqualTo: Timestamp.fromDate(endOfMonth))
          .get();
      
      final Map<DateTime, List<String>> events = {};
      for (var doc in snapshot.docs) {
        final data = doc.data();
        final timestamp = data['data_agendamento'] as Timestamp?;
        if (timestamp != null) {
          final date = timestamp.toDate();
          final dateKey = DateTime(date.year, date.month, date.day);
          events[dateKey] = (events[dateKey] ?? [])..add(doc.id);
        }
      }
      
      if (mounted) {
        setState(() => _events = events);
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
      _hasMore = true;
    });

    try {
      Query query = _buildQuery();
      final snapshot = await query.limit(_perPage).get();

      if (mounted) {
        setState(() {
          if (snapshot.docs.isNotEmpty) {
            _lastDocument = snapshot.docs.last;
            _appointments = snapshot.docs;
          }
          if (snapshot.docs.length < _perPage) _hasMore = false;
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
      final snapshot = await query.startAfterDocument(_lastDocument!).limit(_perPage).get();

      if (mounted) {
        setState(() {
          if (snapshot.docs.isNotEmpty) {
            _lastDocument = snapshot.docs.last;
            _appointments.addAll(snapshot.docs);
          }
          if (snapshot.docs.length < _perPage) _hasMore = false;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Query _buildQuery() {
    Query query = FirebaseFirestore.instance
        .collection('appointments')
        .where('shopId', isEqualTo: widget.shopId);

    if (_showOnlySelectedDay) {
      final start = DateTime(_selectedDay.year, _selectedDay.month, _selectedDay.day, 0, 0, 0);
      final end = DateTime(_selectedDay.year, _selectedDay.month, _selectedDay.day, 23, 59, 59);
      return query
          .where('data_agendamento', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
          .where('data_agendamento', isLessThanOrEqualTo: Timestamp.fromDate(end))
          .orderBy('data_agendamento');
    } else {
      final startOfMonth = DateTime(_selectedDay.year, _selectedDay.month, 1);
      return query
          .where('data_agendamento', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfMonth))
          .orderBy('data_agendamento');
    }
  }
  
  // 🆕 Filtro de status no lado do cliente
  bool _shouldShowAppointment(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>?;
    if (data == null) return false;
    
    final status = (data['status'] ?? '').toString().toLowerCase();
    
    if (_selectedTab == 0) {
      // Ativos: tudo EXCETO cancelado
      return status != 'cancelado';
    } else {
      // Histórico: apenas cancelado
      return status == 'cancelado';
    }
  }

  // 🎯 AÇÃO: IR PARA HOJE
  void _jumpToToday() {
    setState(() {
      _selectedDay = DateTime.now();
      _focusedDay = DateTime.now();
      _showOnlySelectedDay = true;
    });
    _loadAppointments();
  }

  // ✏️ EDITAR AGENDAMENTO
  // ignore: unused_element
  void _showEditDialog(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    
    final TextEditingController nameController = TextEditingController(text: data['client_nome'] ?? '');
    String? selectedServiceId = data['servicoId'];
    String selectedServiceName = data['servico_nome'] ?? '';
    double selectedServicePrice = _safeParseValue(doc);
    
    final TextEditingController valueController = TextEditingController(
      text: selectedServicePrice.toStringAsFixed(2).replaceAll('.', ',')
    );
    final TextEditingController paidController = TextEditingController(
      text: (data['valor_pago']?.toString() ?? '0').replaceAll('.', ',')
    );
    
    DateTime appointmentDate = (data['data_agendamento'] as Timestamp).toDate();
    TimeOfDay appointmentTime = TimeOfDay.fromDateTime(appointmentDate);
    String selectedStatus = data['status']?.toString().toLowerCase() ?? 'pendente';

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
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
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
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 15),
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
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            const Icon(Icons.calendar_today, size: 18, color: AppColors.primaryPurple),
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
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 15),
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
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            const Icon(Icons.access_time, size: 18, color: AppColors.primaryPurple),
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
                          .snapshots(),
                      builder: (context, snapshot) {
                        if (!snapshot.hasData) {
                          return const CircularProgressIndicator();
                        }
                        final services = snapshot.data!.docs;
                        
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Serviço', style: TextStyle(fontWeight: FontWeight.bold)),
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade50,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: DropdownButton<String>(
                                isExpanded: true,
                                underline: const SizedBox(),
                                value: selectedServiceId,
                                hint: Text(selectedServiceName.isNotEmpty ? selectedServiceName : 'Selecione um serviço'),
                                items: services.map((service) {
                                  final sData = service.data() as Map<String, dynamic>;
                                  return DropdownMenuItem<String>(
                                    value: service.id,
                                    child: Text('${sData['nome']} - R\$ ${sData['preco']}'),
                                  );
                                }).toList(),
                                onChanged: (value) {
                                  if (value != null) {
                                    final service = services.firstWhere((s) => s.id == value);
                                    final sData = service.data() as Map<String, dynamic>;
                                    setModalState(() {
                                      selectedServiceId = value;
                                      selectedServiceName = sData['nome'] ?? '';
                                      selectedServicePrice = (sData['preco'] ?? 0).toDouble();
                                      valueController.text = selectedServicePrice.toStringAsFixed(2).replaceAll('.', ',');
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
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: [
                        ChoiceChip(
                          label: const Text('Pendente'),
                          selected: selectedStatus == 'pendente',
                          onSelected: (selected) {
                            if (selected) setModalState(() => selectedStatus = 'pendente');
                          },
                          selectedColor: Colors.orange.withValues(alpha: 0.3),
                        ),
                        ChoiceChip(
                          label: const Text('Concluído'),
                          selected: selectedStatus == 'concluido',
                          onSelected: (selected) {
                            if (selected) setModalState(() => selectedStatus = 'concluido');
                          },
                          selectedColor: Colors.green.withValues(alpha: 0.3),
                        ),
                        ChoiceChip(
                          label: const Text('Cancelado'),
                          selected: selectedStatus == 'cancelado',
                          onSelected: (selected) {
                            if (selected) setModalState(() => selectedStatus = 'cancelado');
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
                  child: const Text("Cancelar", style: TextStyle(color: Colors.grey)),
                ),
                ElevatedButton(
                  onPressed: () async {
                    if (nameController.text.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Nome do cliente é obrigatório')),
                      );
                      return;
                    }

                    double valorTotal = double.tryParse(
                      valueController.text.replaceAll(',', '.')
                    ) ?? 0.0;
                    
                    double valorPago = double.tryParse(
                      paidController.text.replaceAll(',', '.')
                    ) ?? 0.0;

                    try {
                      await FirebaseFirestore.instance
                          .collection('appointments')
                          .doc(doc.id)
                          .update({
                        'client_nome': nameController.text.trim(),
                        'servico_nome': selectedServiceName.isEmpty ? 'Serviço' : selectedServiceName,
                        if (selectedServiceId != null) 'servicoId': selectedServiceId,
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
                            content: Text('Agendamento atualizado com sucesso!'),
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
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: const Text("Salvar", style: TextStyle(color: Colors.white)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // ➕ MODAL DE LANÇAMENTO
  void _showManualEntryDialog() {
    final TextEditingController nameController = TextEditingController();
    final TextEditingController serviceController = TextEditingController();
    final TextEditingController valueController = TextEditingController();
    DateTime manualDate = _selectedDay;

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
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
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
                        if (picked != null) setModalState(() => manualDate = picked);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 15),
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
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            const Icon(Icons.calendar_today, size: 18, color: AppColors.primaryPurple),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 15),
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
                  child: const Text("Cancelar", style: TextStyle(color: Colors.grey)),
                ),
                ElevatedButton(
                  onPressed: () async {
                    if (nameController.text.isEmpty || valueController.text.isEmpty) return;
                    double valor = double.tryParse(
                      valueController.text.replaceAll(',', '.')
                    ) ?? 0.0;
                    
                    await FirebaseFirestore.instance.collection('appointments').add({
                      'shopId': widget.shopId,
                      'client_nome': nameController.text,
                      'servico_nome': serviceController.text.isEmpty ? 'Avulso' : serviceController.text,
                      'valor_total': valor,
                      'valor': valor,
                      'valor_pago': valor,
                      'status': 'concluido',
                      'data_agendamento': Timestamp.fromDate(manualDate),
                      'criado_em': FieldValue.serverTimestamp(),
                      'tipo': 'manual',
                    });
                    
                    if (mounted) Navigator.pop(context);
                    _loadAppointments();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryPurple,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: const Text("Salvar", style: TextStyle(color: Colors.white)),
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
                  onPressed: _showManualEntryDialog,
                  icon: const Icon(Icons.add, color: Colors.white),
                  label: const Text(
                    "NOVO AGENDAMENTO",
                    style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.5),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryPurple,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(double.infinity, 50),
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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
                          final filteredAppointments = _appointments.where(_shouldShowAppointment).toList();
                          
                          return filteredAppointments.isEmpty
                              ? _buildEmptyState()
                              : ListView.builder(
                                  controller: _scrollController,
                                  padding: const EdgeInsets.only(top: 10, bottom: 20),
                                  itemCount: filteredAppointments.length + (_hasMore ? 1 : 0),
                                  itemBuilder: (context, index) {
                                    if (index == filteredAppointments.length) {
                                      return const Center(
                                        child: Padding(
                                          padding: EdgeInsets.all(10),
                                          child: CircularProgressIndicator(),
                                        ),
                                      );
                                    }
                                    return _buildAppointmentCard(filteredAppointments[index], isDesktop: true);
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
    if (_isLoading && _appointments.isEmpty) {
      return const SliverFillRemaining(child: Center(child: CircularProgressIndicator()));
    }
    
    // 🆕 Filtrar appointments baseado na aba selecionada
    final filteredAppointments = _appointments.where(_shouldShowAppointment).toList();
    
    if (filteredAppointments.isEmpty) {
      return SliverFillRemaining(child: _buildEmptyState());
    }
    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          if (index == filteredAppointments.length) {
            return _hasMore
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(10),
                      child: CircularProgressIndicator(),
                    ),
                  )
                : const SizedBox();
          }
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _buildAppointmentCard(filteredAppointments[index], isDesktop: false),
          );
        },
        childCount: filteredAppointments.length + 1,
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
            if (!isSameDay(_selectedDay, selectedDay)) {
              setState(() {
                _selectedDay = selectedDay;
                _focusedDay = focusedDay;
                _showOnlySelectedDay = true;
              });
              _loadAppointments();
            }
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
            titleTextStyle: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
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
        
        // 🆕 ABAS: Ativos / Histórico
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () {
                    setState(() => _selectedTab = 0);
                    _loadAppointments();
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: _selectedTab == 0 ? AppColors.primaryPurple : Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.event_available,
                          size: 18,
                          color: _selectedTab == 0 ? Colors.white : Colors.grey,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          "Ativos",
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: _selectedTab == 0 ? Colors.white : Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Expanded(
                child: GestureDetector(
                  onTap: () {
                    setState(() => _selectedTab = 1);
                    _loadAppointments();
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: _selectedTab == 1 ? AppColors.primaryPurple : Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.history,
                          size: 18,
                          color: _selectedTab == 1 ? Colors.white : Colors.grey,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          "Histórico",
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: _selectedTab == 1 ? Colors.white : Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        
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
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 20),
      color: Colors.transparent,
      child: Row(
        children: [
          Expanded(
            child: _buildMetricCard(
              "Hoje",
              _calculateDailyProjection(_selectedDay),
              Colors.blue,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _buildMetricCard(
              "Mês",
              _calculateMonthlyProjection(),
              Colors.green,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricCard(String title, Stream<double> stream, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 5,
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
              Text(
                title,
                style: TextStyle(
                  color: Colors.grey.shade600,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Icon(Icons.trending_up, size: 14, color: color),
            ],
          ),
          const SizedBox(height: 6),
          StreamBuilder<double>(
            stream: stream,
            builder: (context, snapshot) {
              double val = snapshot.data ?? 0.0;
              return Text(
                "R\$ ${val.toStringAsFixed(0)}",
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              );
            },
          ),
        ],
      ),
    );
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

  Stream<double> _calculateDailyProjection(DateTime date) {
    final start = DateTime(date.year, date.month, date.day, 0, 0);
    final end = DateTime(date.year, date.month, date.day, 23, 59);

    return FirebaseFirestore.instance
        .collection('appointments')
        .where('shopId', isEqualTo: widget.shopId)
        .where('data_agendamento', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .where('data_agendamento', isLessThanOrEqualTo: Timestamp.fromDate(end))
        .snapshots()
        .map((snapshot) {
      double total = 0.0;
      for (var doc in snapshot.docs) {
        final status = doc['status']?.toString().toLowerCase() ?? '';
        if (status != 'cancelado') total += _safeParseValue(doc);
      }
      return total;
    });
  }

  Stream<double> _calculateMonthlyProjection() {
    DateTime now = _focusedDay;
    DateTime startOfMonth = DateTime(now.year, now.month, 1);
    DateTime endOfMonth = DateTime(now.year, now.month + 1, 0, 23, 59, 59);

    return FirebaseFirestore.instance
        .collection('appointments')
        .where('shopId', isEqualTo: widget.shopId)
        .where('data_agendamento', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfMonth))
        .where('data_agendamento', isLessThanOrEqualTo: Timestamp.fromDate(endOfMonth))
        .snapshots()
        .map((snapshot) {
      double total = 0.0;
      for (var doc in snapshot.docs) {
        final status = doc['status']?.toString().toLowerCase() ?? '';
        if (status != 'cancelado') total += _safeParseValue(doc);
      }
      return total;
    });
  }

  // 💎 CARD DE AGENDAMENTO (com botão de edição)
  Widget _buildAppointmentCard(DocumentSnapshot doc, {required bool isDesktop}) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
    DateTime hora = (data['data_agendamento'] as Timestamp).toDate();

    double total = _safeParseValue(doc);
    double pago = double.tryParse(data['valor_pago']?.toString() ?? "0") ?? 0;
    String status = data['status']?.toString().toLowerCase() ?? '';

    bool isCanceled = status == 'cancelado';
    bool quitado = (pago >= total && total > 0) || status == 'concluido';

    Color statusColor = isCanceled ? Colors.red : (quitado ? Colors.green : Colors.orange);
    String statusText = isCanceled ? "CANCELADO" : (quitado ? "PAGO" : "PENDENTE");

    bool isSelected = isDesktop && _selectedAppointment?.id == doc.id;

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
                      Container(width: 1, height: 30, color: Colors.grey.shade200),
                      const SizedBox(width: 16),

                      // Infos Cliente
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              data['client_nome'] ?? "Cliente",
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                                decoration: isCanceled ? TextDecoration.lineThrough : null,
                                color: isCanceled ? Colors.grey : Colors.black87,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              data['servico_nome'] ?? "Serviço",
                              style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
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
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                          ),
                          const SizedBox(height: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
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

                      // Botão de Edição
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.edit, size: 18),
                        color: AppColors.primaryPurple,
                        onPressed: () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => AppointmentDetailsPage(
                                appointmentDoc: doc,
                                startInEditMode: true, // 🆕 Inicia direto em modo de edição
                              ),
                            ),
                          );
                          _loadAppointments(); // Recarrega após edição
                        },
                        tooltip: 'Editar agendamento',
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, size: 18),
                        color: Colors.red,
                        onPressed: () => _confirmAndDeleteAppointment(doc),
                        tooltip: 'Excluir agendamento',
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

  Future<void> _confirmAndDeleteAppointment(DocumentSnapshot doc) async {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    final status = (data['status'] ?? '').toString();
    final isHistory = status == 'cancelado' || status == 'concluido';

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Excluir agendamento?'),
        content: Text(
          isHistory
              ? 'Deseja remover permanentemente este agendamento do histórico?'
              : 'Deseja excluir permanentemente este agendamento ativo?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Excluir', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await doc.reference.delete();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Agendamento excluído'),
            backgroundColor: Colors.green,
          ));
          _loadAppointments();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Erro ao excluir: $e'),
            backgroundColor: Colors.red,
          ));
        }
      }
    }
  }
}