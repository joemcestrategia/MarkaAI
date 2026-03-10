import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:table_calendar/table_calendar.dart';
import '../../core/theme/app_colors.dart';
import '../../core/services/session_service.dart';

class NewAppointmentPage extends StatefulWidget {
  final Map<String, dynamic>? preSelectedClient;
  final String? preSelectedClientId;

  const NewAppointmentPage(
      {super.key, this.preSelectedClient, this.preSelectedClientId});

  @override
  State<NewAppointmentPage> createState() => _NewAppointmentPageState();
}

class _NewAppointmentPageState extends State<NewAppointmentPage> {
  int _currentStep = 0;
  bool _isLoading = false;
  String? shopId;

  // Seleções
  DocumentSnapshot? _selectedService;
  DocumentSnapshot? _selectedProfessional;
  DateTime? _selectedDate;
  TimeOfDay? _selectedTime;

  // Calendário customizado
  DateTime _focusedDay = DateTime.now();
  final Map<DateTime, bool> _fullDays = {};
  bool _isLoadingAvailability = false;
  List<DocumentSnapshot> _monthAppointments = [];

  @override
  void initState() {
    super.initState();
    _loadShopId();
  }

  Future<void> _loadShopId() async {
    final id = await SessionService.getShopId();
    setState(() => shopId = id);
  }

  // --- PASSO 1: SERVIÇOS ---
  Widget _buildServiceStep() {
    if (shopId == null) return const Center(child: CircularProgressIndicator());

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('services')
          .where('shopId', isEqualTo: shopId)
          .where('ativo', isEqualTo: true)
          .orderBy('nome')
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
              child: Text("Erro: ${snapshot.error}",
                  style: const TextStyle(color: Colors.red)));
        }
        if (!snapshot.hasData) return const CircularProgressIndicator();
        final docs = snapshot.data!.docs;

        if (docs.isEmpty) {
          return const Center(child: Text("Nenhum serviço ativo encontrado."));
        }

        return ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final serviceDoc = docs[index];
            final data = serviceDoc.data() as Map<String, dynamic>;
            final isSelected = _selectedService?.id == serviceDoc.id;

            String precoDisplay = data['preco']?.toString() ?? "0.00";
            // âœ… CORREÇÃO: Agora busca 'tempo_min' do Firestore
            String duracao = data['tempo_min']?.toString() ?? "30";

            return Card(
              color: isSelected
                  ? AppColors.primaryPurple.withValues(alpha: 0.1)
                  : Colors.white,
              elevation: 1,
              child: ListTile(
                title: Text(data['nome'] ?? "Serviço",
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: isSelected
                            ? AppColors.primaryPurple
                            : Colors.black)),
                subtitle: Text("R\$ $precoDisplay â€¢ $duracao min"),
                trailing: isSelected
                    ? const Icon(Icons.check_circle,
                        color: AppColors.primaryPurple)
                    : const Icon(Icons.circle_outlined),
                onTap: () {
                  setState(() {
                    _selectedService = serviceDoc;
                    // ✅ IMPORTANTE: Reseta profissional e horário quando muda o serviço
                    _selectedProfessional = null;
                    _selectedTime = null;
                    _selectedDate = null;
                    _fullDays.clear();
                  });
                },
              ),
            );
          },
        );
      },
    );
  }

  // --- PASSO 2: PROFISSIONAL ---
  Widget _buildProfessionalStep() {
    if (shopId == null) {
      return const CircularProgressIndicator();
    }

    // âœ… VALIDAÇÃO: Precisa ter um serviço selecionado primeiro
    if (_selectedService == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Text(
            "Selecione um serviço primeiro",
            style: TextStyle(color: Colors.grey, fontSize: 16),
          ),
        ),
      );
    }

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('employees')
          .where('shopId', isEqualTo: shopId)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Center(
              child: Text("Erro ao carregar profissionais.",
                  style: TextStyle(color: Colors.red)));
        }
        if (!snapshot.hasData) {
          return const CircularProgressIndicator();
        }
        final allDocs = snapshot.data!.docs;

        // âœ… FILTRO: Mostra apenas profissionais que fazem este serviço
        final filteredDocs = allDocs.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          List<dynamic> servicosHabilitados = data['servicos_habilidade'] ?? [];
          return servicosHabilitados.contains(_selectedService!.id);
        }).toList();

        if (filteredDocs.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Text(
                "Nenhum profissional habilitado para este serviço.",
                style: TextStyle(color: Colors.orange, fontSize: 14),
                textAlign: TextAlign.center,
              ),
            ),
          );
        }

        return ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: filteredDocs.length,
          itemBuilder: (context, index) {
            final data = filteredDocs[index].data() as Map<String, dynamic>;
            final isSelected =
                _selectedProfessional?.id == filteredDocs[index].id;

            String nome = data['nome'] ?? "Profissional";
            String tipo = data['tipo'] ?? "funcionario";

            return Card(
              color: isSelected
                  ? AppColors.primaryPurple.withValues(alpha: 0.1)
                  : Colors.white,
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor:
                      AppColors.primaryPurple.withValues(alpha: 0.2),
                  child: Text(
                      nome.isNotEmpty
                          ? nome.substring(0, 1).toUpperCase()
                          : "?",
                      style: const TextStyle(
                          color: AppColors.primaryPurple,
                          fontWeight: FontWeight.bold)),
                ),
                title: Text(nome,
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text(tipo.toUpperCase(),
                    style: const TextStyle(fontSize: 10, color: Colors.grey)),
                trailing: isSelected
                    ? const Icon(Icons.check_circle,
                        color: AppColors.primaryPurple)
                    : null,
                onTap: () {
                  setState(() {
                    _selectedProfessional = filteredDocs[index];
                    _selectedTime = null;
                    _selectedDate = null;
                  });
                  _loadMonthAppointments(_focusedDay);
                },
              ),
            );
          },
        );
      },
    );
  }

  // --- PASSO 3: DATA E HORA ---
  Widget _buildTimeStep() {
    return Column(
      children: [
        if (_isLoadingAvailability)
          const Padding(
            padding: EdgeInsets.all(8.0),
            child: LinearProgressIndicator(minHeight: 2),
          ),
        TableCalendar(
          firstDay: DateTime.now(),
          lastDay: DateTime.now().add(const Duration(days: 90)),
          focusedDay: _focusedDay,
          locale: 'pt_BR',
          selectedDayPredicate: (day) => isSameDay(_selectedDate, day),
          headerStyle: const HeaderStyle(
            formatButtonVisible: false,
            titleCentered: true,
          ),
          onDaySelected: (selectedDay, focusedDay) {
            if (_fullDays[DateTime(
                    selectedDay.year, selectedDay.month, selectedDay.day)] ==
                true) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text("Este dia está com a agenda lotada."),
                  duration: Duration(seconds: 1)));
              return;
            }
            setState(() {
              _selectedDate = selectedDay;
              _focusedDay = focusedDay;
              _selectedTime = null;
            });
          },
          onPageChanged: (focusedDay) {
            _focusedDay = focusedDay;
            _loadMonthAppointments(focusedDay);
          },
          calendarBuilders: CalendarBuilders(
            defaultBuilder: (context, day, focusedDay) =>
                _buildCalendarDay(day, false),
            outsideBuilder: (context, day, focusedDay) =>
                _buildCalendarDay(day, true),
            todayBuilder: (context, day, focusedDay) =>
                _buildCalendarDay(day, false, isToday: true),
            selectedBuilder: (context, day, focusedDay) =>
                _buildCalendarDay(day, false, isSelected: true),
          ),
        ),
        if (_selectedDate != null) ...[
          const Divider(),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 10),
            child: Text("Horários Disponíveis:",
                style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          _buildRealTimeSlots(),
        ]
      ],
    );
  }

  Widget _buildRealTimeSlots() {
    if (_selectedProfessional == null ||
        shopId == null ||
        _selectedService == null) {
      return const Text("Selecione serviço e profissional.");
    }

    final profData = _selectedProfessional!.data() as Map<String, dynamic>;
    final servData = _selectedService!.data() as Map<String, dynamic>;

    int duracaoServico =
        int.tryParse(servData['tempo_min']?.toString() ?? "30") ?? 30;
    List<dynamic> workDays = profData['dias_trabalho'] ?? [1, 2, 3, 4, 5, 6];

    if (!workDays.contains(_selectedDate!.weekday)) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            color: Colors.red[50], borderRadius: BorderRadius.circular(8)),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            Icon(Icons.block, color: Colors.red, size: 20),
            SizedBox(width: 8),
            Text("Este profissional não atende neste dia.",
                style: TextStyle(color: Colors.red)),
          ],
        ),
      );
    }

    String startStr = profData['horario_inicio'] ?? "08:00";
    String endStr = profData['horario_fim'] ?? "19:00";

    DateTime startOfDay = DateTime(
        _selectedDate!.year, _selectedDate!.month, _selectedDate!.day, 0, 0);
    DateTime endOfDay = DateTime(
        _selectedDate!.year, _selectedDate!.month, _selectedDate!.day, 23, 59);

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('appointments')
          .where('shopId', isEqualTo: shopId)
          .where('profissionalId', isEqualTo: _selectedProfessional!.id)
          .where('data_agendamento', isGreaterThanOrEqualTo: startOfDay)
          .where('data_agendamento', isLessThanOrEqualTo: endOfDay)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Padding(
            padding: EdgeInsets.all(10),
            child: Text("Erro de conexão ou índice.",
                style: TextStyle(color: Colors.red, fontSize: 12)),
          );
        }

        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        List<String> busyTimes = [];
        for (var doc in snapshot.data!.docs) {
          final data = doc.data() as Map<String, dynamic>;
          final status = (data['status'] ?? '').toString().toLowerCase();
          if (status == 'cancelado' || status == 'recusado') {
            continue;
          }

          if (data['data_agendamento'] != null) {
            DateTime dt = (data['data_agendamento'] as Timestamp).toDate();
            String timeStr = _formatTime(dt.hour, dt.minute);
            busyTimes.add(timeStr);
          }
        }

        final slots = _generateProfessionalSlotsWithDuration(
            startStr, endStr, duracaoServico);

        if (slots.isEmpty) {
          return const Text("Sem horários que caibam o serviço hoje.");
        }

        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: slots.map((timeStr) {
            bool isBusy = busyTimes.contains(timeStr);
            bool isSelected = _selectedTime != null &&
                _formatTimeOfDay(_selectedTime!) == timeStr;

            return ChoiceChip(
              label: Text(timeStr,
                  style: TextStyle(
                      color: isBusy
                          ? Colors.grey
                          : (isSelected ? Colors.white : Colors.black),
                      decoration: isBusy ? TextDecoration.lineThrough : null)),
              selected: isSelected,
              selectedColor: AppColors.primaryPurple,
              disabledColor: Colors.grey[200],
              onSelected: isBusy
                  ? null
                  : (selected) {
                      setState(() {
                        final parts = timeStr.split(':');
                        _selectedTime = TimeOfDay(
                            hour: int.parse(parts[0]),
                            minute: int.parse(parts[1]));
                      });
                    },
            );
          }).toList(),
        );
      },
    );
  }

  Widget _buildCalendarDay(DateTime day, bool isOutside,
      {bool isToday = false, bool isSelected = false}) {
    final dayOnly = DateTime(day.year, day.month, day.day);
    final isFull = _fullDays[dayOnly] ?? false;

    return Container(
      margin: const EdgeInsets.all(4),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: isSelected
            ? AppColors.primaryPurple
            : (isToday ? AppColors.primaryPurple.withValues(alpha: 0.1) : null),
        shape: BoxShape.circle,
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Text(
            day.day.toString(),
            style: TextStyle(
              color: isSelected
                  ? Colors.white
                  : (isOutside || isFull ? Colors.grey : Colors.black),
              fontWeight:
                  isToday || isSelected ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          if (isFull)
            CustomPaint(
              size: const Size(24, 24),
              painter: StrikeThroughPainter(),
            ),
        ],
      ),
    );
  }

  Future<void> _loadMonthAppointments(DateTime focusedMonth) async {
    if (shopId == null ||
        _selectedProfessional == null ||
        _selectedService == null) {
      return;
    }

    setState(() => _isLoadingAvailability = true);

    final startOfMonth = DateTime(focusedMonth.year, focusedMonth.month, 1);
    final endOfMonth =
        DateTime(focusedMonth.year, focusedMonth.month + 1, 0, 23, 59, 59);

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('appointments')
          .where('shopId', isEqualTo: shopId)
          .where('profissionalId', isEqualTo: _selectedProfessional!.id)
          .where('data_agendamento',
              isGreaterThanOrEqualTo: Timestamp.fromDate(startOfMonth))
          .where('data_agendamento',
              isLessThanOrEqualTo: Timestamp.fromDate(endOfMonth))
          .get();

      _monthAppointments = snapshot.docs;
      _calculateFullDays(focusedMonth);
    } catch (e) {
      debugPrint("Erro ao carregar disponibilidade: $e");
    } finally {
      if (mounted) setState(() => _isLoadingAvailability = false);
    }
  }

  void _calculateFullDays(DateTime month) {
    if (_selectedService == null || _selectedProfessional == null) return;

    _fullDays.clear();
    final profData = _selectedProfessional!.data() as Map<String, dynamic>;
    final servData = _selectedService!.data() as Map<String, dynamic>;

    int duration =
        int.tryParse(servData['tempo_min']?.toString() ?? "30") ?? 30;
    List<dynamic> workDays = profData['dias_trabalho'] ?? [1, 2, 3, 4, 5, 6];
    String startStr = profData['horario_inicio'] ?? "08:00";
    String endStr = profData['horario_fim'] ?? "19:00";

    // Dias do mês
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;

    for (int i = 1; i <= daysInMonth; i++) {
      final date = DateTime(month.year, month.month, i);
      final dayOfWeek = date.weekday;

      // 1. Se não trabalha no dia, marca como cheio/riscado
      if (!workDays.contains(dayOfWeek)) {
        _fullDays[date] = true;
        continue;
      }

      // 2. Verifica se há pelo menos um slot livre
      List<String> busyTimes = [];
      for (var doc in _monthAppointments) {
        final data = doc.data() as Map<String, dynamic>;
        final status = (data['status'] ?? '').toString().toLowerCase();
        if (status == 'cancelado' || status == 'recusado') continue;

        DateTime dt = (data['data_agendamento'] as Timestamp).toDate();
        if (dt.year == date.year &&
            dt.month == date.month &&
            dt.day == date.day) {
          busyTimes.add(_formatTime(dt.hour, dt.minute));
        }
      }

      final slots =
          _generateProfessionalSlotsWithDuration(startStr, endStr, duration);
      bool hasAnySlot = false;
      for (var slot in slots) {
        if (!busyTimes.contains(slot)) {
          hasAnySlot = true;
          break;
        }
      }

      if (!hasAnySlot) {
        _fullDays[date] = true;
      }
    }

    if (mounted) setState(() {});
  }

  // --- CÃLCULO DE SLOTS COM DURAÇÃO ---
  List<String> _generateProfessionalSlotsWithDuration(
      String start, String end, int durationMin) {
    List<String> slots = [];
    int startH = int.parse(start.split(':')[0]);
    int startM = int.parse(start.split(':')[1]);
    int endH = int.parse(end.split(':')[0]);
    int endM = int.parse(end.split(':')[1]);

    int totalEndMinutes = (endH * 60) + endM;
    int currentMinutes = (startH * 60) + startM;

    // âœ… CORREÇÃO: Agora incrementa com a duração real do serviço
    while (currentMinutes + durationMin <= totalEndMinutes) {
      int h = currentMinutes ~/ 60;
      int m = currentMinutes % 60;
      slots.add(_formatTime(h, m));
      currentMinutes += durationMin; // âš¡ Usa a duração real em vez de 30 fixo
    }
    return slots;
  }

  String _formatTime(int h, int m) =>
      "${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}";
  String _formatTimeOfDay(TimeOfDay t) => _formatTime(t.hour, t.minute);

  // --- CONFIRMAR E SALVAR ---
  Future<void> _confirmAppointment() async {
    setState(() => _isLoading = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      String finalClientId;
      String finalClientName;
      String finalClientPhone;

      if (widget.preSelectedClientId != null &&
          widget.preSelectedClient != null) {
        finalClientId = widget.preSelectedClientId!;
        finalClientName = widget.preSelectedClient!['nome'];
        finalClientPhone = widget.preSelectedClient!['telefone'] ?? "";
      } else {
        if (user == null) {
          return;
        }
        finalClientId = user.uid;
        finalClientName = user.displayName ?? "Cliente App";
        finalClientPhone = "";
      }

      final DateTime fullDate = DateTime(
          _selectedDate!.year,
          _selectedDate!.month,
          _selectedDate!.day,
          _selectedTime!.hour,
          _selectedTime!.minute);

      final servicoData = _selectedService!.data() as Map<String, dynamic>;
      double valor = double.tryParse(servicoData['preco'].toString()) ?? 0.0;
      final profData = _selectedProfessional!.data() as Map<String, dynamic>;

      await FirebaseFirestore.instance.collection('appointments').add({
        'shopId': shopId,
        'clientId': finalClientId,
        'client_nome': finalClientName,
        'client_telefone': finalClientPhone,
        'profissionalId': _selectedProfessional!.id,
        'profissional_nome': profData['nome'] ?? "Profissional",
        'servicoId': _selectedService!.id,
        'servico_nome': servicoData['nome'],
        // ✔️ Salva a duração real do serviço no agendamento para evitar sobreposição na agenda
        'duracao_min':
            int.tryParse(servicoData['tempo_min']?.toString() ?? "30") ?? 30,
        'valor': valor,
        'data_agendamento': Timestamp.fromDate(fullDate),
        'status': 'agendado',
        'metodo_pagamento': 'No Local',
        'criado_em': FieldValue.serverTimestamp(),
        'criado_por': widget.preSelectedClientId != null ? 'dono' : 'cliente',
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text("Agendamento confirmado!"),
            backgroundColor: Colors.green));
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text("Erro: $e")));
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    bool isManual = widget.preSelectedClient != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(isManual ? "Agendar para Cliente" : "Novo Agendamento"),
        backgroundColor: AppColors.primaryPurple,
        foregroundColor: Colors.white,
      ),
      body: Stepper(
        type: StepperType.horizontal,
        currentStep: _currentStep,
        onStepContinue: () {
          if (_currentStep == 0 && _selectedService == null) {
            ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("Selecione um serviço.")));
            return;
          }
          if (_currentStep == 1 && _selectedProfessional == null) {
            ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("Selecione um profissional.")));
            return;
          }
          if (_currentStep == 2 &&
              (_selectedDate == null || _selectedTime == null)) {
            ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("Selecione data e hora.")));
            return;
          }
          if (_currentStep < 2) {
            setState(() => _currentStep++);
          } else {
            _confirmAppointment();
          }
        },
        onStepCancel: () {
          if (_currentStep > 0) {
            setState(() => _currentStep--);
          }
        },
        controlsBuilder: (context, details) {
          return Padding(
            padding: const EdgeInsets.only(top: 20),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: details.onStepContinue,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryPurple,
                      foregroundColor: Colors.white,
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child:
                                CircularProgressIndicator(color: Colors.white))
                        : Text(_currentStep == 2 ? "CONFIRMAR" : "PRÃ“XIMO",
                            style: const TextStyle(color: Colors.white)),
                  ),
                ),
                if (_currentStep > 0) ...[
                  const SizedBox(width: 10),
                  TextButton(
                      onPressed: details.onStepCancel,
                      child: const Text("VOLTAR")),
                ]
              ],
            ),
          );
        },
        steps: [
          Step(
            title: const Text("Serviço"),
            content: _buildServiceStep(),
            isActive: _currentStep >= 0,
            state: _selectedService != null
                ? StepState.complete
                : StepState.editing,
          ),
          Step(
            title: const Text("Equipe"),
            content: _buildProfessionalStep(),
            isActive: _currentStep >= 1,
            state: _selectedProfessional != null
                ? StepState.complete
                : StepState.editing,
          ),
          Step(
            title: const Text("Data"),
            content: _buildTimeStep(),
            isActive: _currentStep >= 2,
            state: _selectedDate != null && _selectedTime != null
                ? StepState.complete
                : StepState.editing,
          ),
        ],
      ),
    );
  }
}

class StrikeThroughPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.grey.withValues(alpha: 0.5)
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;

    // Linha diagonal para indicar indisponibilidade
    canvas.drawLine(
      Offset(size.width * 0.2, size.height * 0.8),
      Offset(size.width * 0.8, size.height * 0.2),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
