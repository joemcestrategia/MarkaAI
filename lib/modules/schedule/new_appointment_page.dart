import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;
import 'package:table_calendar/table_calendar.dart';
import '../../core/theme/app_colors.dart';
import '../../core/services/session_service.dart';
import '../../core/models/appointment_model.dart';

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
  Map<String, dynamic>? _selectedService;
  Map<String, dynamic>? _selectedProfessional;
  DateTime? _selectedDate;
  TimeOfDay? _selectedTime;

  // Calendário customizado
  DateTime _focusedDay = DateTime.now();
  final Map<DateTime, bool> _fullDays = {};
  bool _isLoadingAvailability = false;
  List<Map<String, dynamic>> _monthAppointments = [];

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

    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: sb.Supabase.instance.client
          .from('services')
          .stream(primaryKey: ['id'])
          .eq('shop_id', shopId!)
          .map((list) {
            final filtered = list.where((d) => d['is_active'] == null || d['is_active'] == true).toList();
            filtered.sort((a, b) => (a['name'] ?? '').toString().toLowerCase().compareTo((b['name'] ?? '').toString().toLowerCase()));
            return filtered;
          }),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
              child: Text("Erro: ${snapshot.error}",
                  style: const TextStyle(color: Colors.red)));
        }
        if (!snapshot.hasData) return const CircularProgressIndicator();
        final docs = snapshot.data!;

        if (docs.isEmpty) {
          return const Center(child: Text("Nenhum serviço ativo encontrado."));
        }

        return ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final serviceDoc = docs[index];
            final data = serviceDoc;
            final isSelected = _selectedService?['id'] == serviceDoc['id'];

            String precoDisplay = data['price']?.toString() ?? "0.00";
            String duracao = data['duration_min']?.toString() ?? "30";

            return Card(
              color: isSelected
                  ? AppColors.primaryPurple.withValues(alpha: 0.1)
                  : Colors.white,
              elevation: 1,
              child: ListTile(
                title: Text(data['name'] ?? "Serviço",
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: isSelected
                            ? AppColors.primaryPurple
                            : Colors.black)),
                subtitle: Text("R\$ $precoDisplay • $duracao min"),
                trailing: isSelected
                    ? const Icon(Icons.check_circle,
                        color: AppColors.primaryPurple)
                    : const Icon(Icons.circle_outlined),
                onTap: () {
                  setState(() {
                    _selectedService = serviceDoc;
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

    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: sb.Supabase.instance.client
          .from('employees')
          .stream(primaryKey: ['id'])
          .eq('shop_id', shopId!),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Center(
              child: Text("Erro ao carregar profissionais.",
                  style: TextStyle(color: Colors.red)));
        }
        if (!snapshot.hasData) {
          return const CircularProgressIndicator();
        }
        final allDocs = snapshot.data!;

        final filteredDocs = allDocs.where((data) {
          final List<dynamic> servicosHabilitados = data['services_ids'] ?? [];
          return servicosHabilitados.map((id) => id.toString()).contains(_selectedService!['id'].toString());
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
            final data = filteredDocs[index];
            final isSelected =
                _selectedProfessional?['id'] == filteredDocs[index]['id'];

            String name = data['name'] ?? "Profissional";
            String role = data['role'] ?? "funcionario";

            return Card(
              color: isSelected
                  ? AppColors.primaryPurple.withValues(alpha: 0.1)
                  : Colors.white,
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor:
                      AppColors.primaryPurple.withValues(alpha: 0.2),
                  child: Text(
                      name.isNotEmpty
                          ? name.substring(0, 1).toUpperCase()
                          : "?",
                      style: const TextStyle(
                          color: AppColors.primaryPurple,
                          fontWeight: FontWeight.bold)),
                ),
                title: Text(name,
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text(role.toUpperCase(),
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

    final profData = _selectedProfessional!;
    final servData = _selectedService!;

    int duracaoServico =
        int.tryParse(servData['duration_min']?.toString() ?? "30") ?? 30;
    List<dynamic> workDays = profData['work_days'] ?? [1, 2, 3, 4, 5, 6];

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

    String startStr = profData['work_start'] ?? "08:00";
    String endStr = profData['work_end'] ?? "19:00";

    DateTime startOfDay = DateTime(
        _selectedDate!.year, _selectedDate!.month, _selectedDate!.day, 0, 0);
    DateTime endOfDay = DateTime(
        _selectedDate!.year, _selectedDate!.month, _selectedDate!.day, 23, 59);

    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: sb.Supabase.instance.client
          .from('appointments')
          .stream(primaryKey: ['id'])
          .eq('shop_id', shopId!)
          .map((list) => list.where((d) => d['professional_id'] == _selectedProfessional!['id']).toList()),
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
        final appointmentsInRange = snapshot.data!.where((data) {
          if (data['scheduled_at'] == null) return false;
          final dt = DateTime.parse(data['scheduled_at']);
          return dt.isAfter(startOfDay.subtract(const Duration(seconds: 1))) && 
                 dt.isBefore(endOfDay.add(const Duration(seconds: 1)));
        });

        for (var data in appointmentsInRange) {
          final status = (data['status'] ?? '').toString().toLowerCase();
          if (status == 'cancelado' || status == 'recusado') {
            continue;
          }

          if (data['scheduled_at'] != null) {
            DateTime dt = DateTime.parse(data['scheduled_at']);
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
                          ? (isSelected ? Colors.white : Colors.orange)
                          : (isSelected ? Colors.white : Colors.black),
                      decoration: isBusy && !isSelected ? TextDecoration.lineThrough : null)),
              selected: isSelected,
              selectedColor: isBusy ? Colors.orange : AppColors.primaryPurple,
              disabledColor: Colors.grey[200],
              onSelected: (selected) async {
                if (isBusy) {
                  // Apenas administradores (fluxo manual) podem sobrepor
                  if (widget.preSelectedClientId != null) {
                    bool confirm = await _showConflictDialog(context, timeStr);
                    if (!confirm) return;
                  } else {
                    return; // Cliente não pode clicar em busy
                  }
                }
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
      final results = await sb.Supabase.instance.client
          .from('appointments')
          .select()
          .eq('shop_id', shopId!)
          .eq('professional_id', _selectedProfessional!['id'])
          .gte('scheduled_at', startOfMonth.toIso8601String())
          .lte('scheduled_at', endOfMonth.toIso8601String());

      _monthAppointments = List<Map<String, dynamic>>.from(results);
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
    final profData = _selectedProfessional!;
    final servData = _selectedService!;

    int duration =
        int.tryParse(servData['duration_min']?.toString() ?? "30") ?? 30;
    List<dynamic> workDays = profData['work_days'] ?? [1, 2, 3, 4, 5, 6];
    String startStr = profData['work_start'] ?? "08:00";
    String endStr = profData['work_end'] ?? "19:00";

    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;

    for (int i = 1; i <= daysInMonth; i++) {
      final date = DateTime(month.year, month.month, i);
      final dayOfWeek = date.weekday;

      if (!workDays.contains(dayOfWeek)) {
        _fullDays[date] = true;
        continue;
      }

      List<String> busyTimes = [];
      for (var data in _monthAppointments) {
        final status = (data['status'] ?? '').toString().toLowerCase();
        if (status == 'cancelado' || status == 'recusado') continue;

        DateTime dt = DateTime.parse(data['scheduled_at']);
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

  List<String> _generateProfessionalSlotsWithDuration(
      String start, String end, int durationMin) {
    List<String> slots = [];
    int startH = int.parse(start.split(':')[0]);
    int startM = int.parse(start.split(':')[1]);
    int endH = int.parse(end.split(':')[0]);
    int endM = int.parse(end.split(':')[1]);

    int totalEndMinutes = (endH * 60) + endM;
    int currentMinutes = (startH * 60) + startM;

    while (currentMinutes + durationMin <= totalEndMinutes) {
      int h = currentMinutes ~/ 60;
      int m = currentMinutes % 60;
      slots.add(_formatTime(h, m));
      currentMinutes += durationMin;
    }
    return slots;
  }

  String _formatTime(int h, int m) =>
      "${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}";
  String _formatTimeOfDay(TimeOfDay t) => _formatTime(t.hour, t.minute);

  Future<void> _confirmAppointment() async {
    setState(() => _isLoading = true);
    try {
      final supabase = sb.Supabase.instance.client;
      final user = supabase.auth.currentUser;
      String finalClientId;
      String finalClientName;
      String finalClientPhone;

      if (widget.preSelectedClientId != null &&
          widget.preSelectedClient != null) {
        finalClientId = widget.preSelectedClientId!;
        finalClientName = widget.preSelectedClient!['name'];
        finalClientPhone = widget.preSelectedClient!['phone'] ?? "";
      } else {
        if (user == null) {
          return;
        }
        finalClientId = user.id;
        finalClientName = user.userMetadata?['name'] ?? user.userMetadata?['nome'] ?? "Cliente App";
        finalClientPhone = "";
      }

      final DateTime fullDate = DateTime(
          _selectedDate!.year,
          _selectedDate!.month,
          _selectedDate!.day,
          _selectedTime!.hour,
          _selectedTime!.minute);

      final servicoData = _selectedService!;
      double valor = double.tryParse(servicoData['price'].toString()) ?? 0.0;
      final profData = _selectedProfessional!;

      final appointment = AppointmentModel(
        shopId: shopId ?? '',
        clientId: finalClientId,
        clientName: finalClientName,
        clientPhone: finalClientPhone,
        clientEmail: (widget.preSelectedClient != null)
            ? (widget.preSelectedClient!['email'] ?? "")
            : (user?.email ?? ""),
        professionalId: _selectedProfessional!['id'],
        professionalName: profData['name'] ?? "Profissional",
        serviceId: _selectedService!['id'],
        serviceName: servicoData['name'],
        scheduledAt: fullDate,
        totalValue: valor,
        totalPrice: valor,
        durationMin:
            int.tryParse(servicoData['duration_min']?.toString() ?? "30") ?? 30,
        createdBy: widget.preSelectedClientId != null ? 'dono' : 'cliente',
      );

      await sb.Supabase.instance.client
          .from('appointments')
          .insert(appointment.toMap());

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
                        : Text(_currentStep == 2 ? "CONFIRMAR" : "PRÓXIMO",
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

  Future<bool> _showConflictDialog(BuildContext context, String timeStr) async {
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
        content: const Text(
          "Este horário já possui um agendamento. Deseja realizar a sobreposição (overlap) administrativa?",
          style: TextStyle(fontWeight: FontWeight.w500),
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
}

class StrikeThroughPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.grey.withValues(alpha: 0.5)
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(
      Offset(size.width * 0.2, size.height * 0.8),
      Offset(size.width * 0.8, size.height * 0.2),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
