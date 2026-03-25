import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/availability_utils.dart';

/// Calendário customizado para o modo de edição do dono.
///
/// Regras de disponibilidade:
/// - Foca na disponibilidade do PROFISSIONAL selecionado.
/// - A regra `preventGaps` (anti-buracos) NÃO é aplicada no modo dono:
///   ele tem liberdade total de horários nos dias que a pessoa trabalha.
/// - Dias completamente sem disponibilidade aparecem CINZOS com RISCO.
class OwnerCalendarPicker extends StatefulWidget {
  final DateTime initialDate;
  final DateTime firstDate;
  final DateTime lastDate;
  final List<int> workDays;
  final String shopId;
  final String professionalId;
  final int intervalMinutes;
  final int serviceDurationMinutes;
  final String profStartTime;
  final String profEndTime;

  /// Id do agendamento sendo editado — excluído do cálculo de ocupação.
  final String? excludeAppointmentId;
  final ValueChanged<DateTime> onDateSelected;

  const OwnerCalendarPicker({
    super.key,
    required this.initialDate,
    required this.firstDate,
    required this.lastDate,
    required this.workDays,
    required this.shopId,
    required this.professionalId,
    required this.intervalMinutes,
    required this.serviceDurationMinutes,
    required this.profStartTime,
    required this.profEndTime,
    this.excludeAppointmentId,
    required this.onDateSelected,
  });

  @override
  State<OwnerCalendarPicker> createState() => _OwnerCalendarPickerState();
}

class _OwnerCalendarPickerState extends State<OwnerCalendarPicker> {
  late DateTime _focusedMonth;
  late DateTime _selectedDate;

  /// Cache: "yyyy-MM-dd" -> hasAnyAvailableSlot
  final Map<String, bool?> _slotCache = {};
  bool _loadingMonth = false;

  static const List<String> _weekdayLabels = [
    'D',
    'S',
    'T',
    'Q',
    'Q',
    'S',
    'S'
  ];

  @override
  void initState() {
    super.initState();
    _selectedDate = widget.initialDate;
    _focusedMonth =
        DateTime(widget.initialDate.year, widget.initialDate.month, 1);
    _loadMonthAvailability(_focusedMonth);
  }

  Future<void> _loadMonthAvailability(DateTime month) async {
    if (!mounted) return;
    setState(() => _loadingMonth = true);

    final firstDay = DateTime(month.year, month.month, 1);
    final lastDay = DateTime(month.year, month.month + 1, 0, 23, 59);

    try {
      final snap = await Supabase.instance.client
          .from('appointments')
          .select()
          .eq('shop_id', widget.shopId)
          .eq('professional_id', widget.professionalId)
          .gte('scheduled_at', firstDay.toIso8601String())
          .lte('scheduled_at', lastDay.toIso8601String());

      final Map<String, List<Map<String, int>>> busyByDay = {};

      for (final doc in snap) {
        if (widget.excludeAppointmentId != null &&
            doc['id'] == widget.excludeAppointmentId) continue;

        final data = doc;
        final status = (data['status'] ?? '').toString().toLowerCase();
        if (status == 'cancelado' ||
            status == 'recusado' ||
            status == 'excluido') {
          continue;
        }

        final dt = DateTime.parse(data['scheduled_at'].toString());
        final key = _dayKey(dt);
        final dur = int.tryParse(data['duracao_min']?.toString() ?? '') ??
            widget.serviceDurationMinutes;
        final startMin = dt.hour * 60 + dt.minute;

        busyByDay.putIfAbsent(key, () => []);
        busyByDay[key]!.add({'start': startMin, 'end': startMin + dur});
      }

      if (!mounted) return;
      setState(() {
        _loadingMonth = false;
        int dayNum = 1;
        while (true) {
          final day = DateTime(month.year, month.month, dayNum);
          if (day.month != month.month) break;

          final key = _dayKey(day);

          if (!widget.workDays.contains(day.weekday) ||
              day.isBefore(widget.firstDate) ||
              day.isAfter(widget.lastDate)) {
            _slotCache[key] = false;
          } else {
            final busy = busyByDay[key] ?? [];
            final freeSlots = AvailabilityUtils.generateSmartSlots(
              startStr: widget.profStartTime,
              endStr: widget.profEndTime,
              interval: widget.intervalMinutes,
              serviceDuration: widget.serviceDurationMinutes,
              busyIntervals: busy,
              preventGaps: false, // Dono tem total liberdade
              minAdvanceHours: 0,
              selectedDate: day,
            );
            _slotCache[key] = freeSlots.isNotEmpty;
          }
          dayNum++;
        }
      });
    } catch (e) {
      if (mounted) setState(() => _loadingMonth = false);
    }
  }

  String _dayKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  bool? _isAvailable(DateTime day) => _slotCache[_dayKey(day)];

  void _prevMonth() {
    final prev = DateTime(_focusedMonth.year, _focusedMonth.month - 1, 1);
    if (prev.isBefore(
        DateTime(widget.firstDate.year, widget.firstDate.month, 1))) return;
    setState(() => _focusedMonth = prev);
    _loadMonthAvailability(prev);
  }

  void _nextMonth() {
    final next = DateTime(_focusedMonth.year, _focusedMonth.month + 1, 1);
    if (next.isAfter(DateTime(widget.lastDate.year, widget.lastDate.month, 1)))
      return;
    setState(() => _focusedMonth = next);
    _loadMonthAvailability(next);
  }

  @override
  Widget build(BuildContext context) {
    final daysInMonth =
        DateTime(_focusedMonth.year, _focusedMonth.month + 1, 0).day;
    // 0 = domingo, conforme padrão pt-BR
    final startWeekday =
        DateTime(_focusedMonth.year, _focusedMonth.month, 1).weekday % 7;

    final monthNames = [
      '',
      'janeiro',
      'fevereiro',
      'março',
      'abril',
      'maio',
      'junho',
      'julho',
      'agosto',
      'setembro',
      'outubro',
      'novembro',
      'dezembro'
    ];

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // ── Navegação do mês ────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left),
                onPressed: _prevMonth,
                splashRadius: 20,
              ),
              Expanded(
                child: Text(
                  '${monthNames[_focusedMonth.month]} de ${_focusedMonth.year}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 15),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                onPressed: _nextMonth,
                splashRadius: 20,
              ),
            ],
          ),
        ),
        // ── Cabeçalho dos dias da semana ────────────────────────────────
        Row(
          children: _weekdayLabels
              .map((l) => Expanded(
                    child: Center(
                      child: Text(l,
                          style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Colors.grey)),
                    ),
                  ))
              .toList(),
        ),
        const SizedBox(height: 8),
        // ── Grade de dias ────────────────────────────────────────────────
        if (_loadingMonth)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: CircularProgressIndicator(
                color: AppColors.primaryPurple, strokeWidth: 2),
          )
        else
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              childAspectRatio: 1,
            ),
            itemCount: startWeekday + daysInMonth,
            itemBuilder: (ctx, idx) {
              if (idx < startWeekday) return const SizedBox.shrink();

              final dayNum = idx - startWeekday + 1;
              final day =
                  DateTime(_focusedMonth.year, _focusedMonth.month, dayNum);

              final isSelected = day.year == _selectedDate.year &&
                  day.month == _selectedDate.month &&
                  day.day == _selectedDate.day;

              final available = _isAvailable(day);
              // null = ainda carregando → não bloqueia visual
              final isUnavailable = available == false;

              final now = DateTime.now();
              final isToday = day.year == now.year &&
                  day.month == now.month &&
                  day.day == now.day;

              return GestureDetector(
                onTap: isUnavailable
                    ? null
                    : () {
                        setState(() => _selectedDate = day);
                        widget.onDateSelected(day);
                      },
                child: Container(
                  margin: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppColors.primaryPurple
                        : isToday && !isSelected
                            ? AppColors.primaryPurple.withValues(alpha: 0.10)
                            : Colors.transparent,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      '$dayNum',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight:
                            isSelected || isToday ? FontWeight.bold : null,
                        color: isSelected
                            ? Colors.white
                            : isUnavailable
                                ? Colors.grey.shade400
                                : Colors.black87,
                        // Risco apenas em dias sem disponibilidade real
                        decoration: isUnavailable
                            ? TextDecoration.lineThrough
                            : TextDecoration.none,
                        decorationColor: Colors.grey.shade400,
                        decorationThickness: 2,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        // ── Legenda ──────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _LegendDot(color: AppColors.primaryPurple, label: 'Selecionado'),
              const SizedBox(width: 16),
              _LegendDot(
                color: Colors.grey.shade400,
                label: 'Sem disponibilidade',
                strikethrough: true,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;
  final bool strikethrough;

  const _LegendDot(
      {required this.color, required this.label, this.strikethrough = false});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: Colors.grey.shade600,
            decoration: strikethrough
                ? TextDecoration.lineThrough
                : TextDecoration.none,
            decorationColor: Colors.grey.shade400,
          ),
        ),
      ],
    );
  }
}
