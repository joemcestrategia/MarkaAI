/// Modelo unificado de jornada de trabalho por dia da semana.
///
/// Padrão Dart: weekday 1 = segunda ... 7 = domingo.
///
/// Lê `employees.work_schedule` (JSONB nova). Se ausente, faz fallback para
/// as colunas legadas (`work_days`, `work_start`/`start_time`,
/// `work_end`/`end_time`) preservando 100% do comportamento anterior.
class WorkSchedule {
  /// Mapa weekday -> DaySchedule (apenas dias habilitados).
  final Map<int, DaySchedule> days;

  const WorkSchedule(this.days);

  /// Retorna a jornada do dia da semana, ou null se o profissional não trabalha.
  DaySchedule? forWeekday(int weekday) => days[weekday];

  bool worksOn(int weekday) => days.containsKey(weekday);

  /// Lista de dias habilitados (formato igual ao legacy `work_days`).
  List<int> get workDays => days.keys.toList()..sort();

  /// Construtor a partir de uma linha de `employees`.
  /// Aceita tanto o novo formato quanto o legado.
  factory WorkSchedule.fromEmployeeRow(Map<String, dynamic> row) {
    final raw = row['work_schedule'];
    if (raw is Map) {
      final Map<int, DaySchedule> out = {};
      raw.forEach((k, v) {
        final wd = int.tryParse(k.toString());
        if (wd == null || wd < 1 || wd > 7) return;
        if (v is! Map) return;
        final enabled = v['enabled'] == true;
        if (!enabled) return;
        final start = (v['start']?.toString() ?? '').trim();
        final end = (v['end']?.toString() ?? '').trim();
        if (start.isEmpty || end.isEmpty) return;
        DayBreak? br;
        final rawBreak = v['break'];
        if (rawBreak is Map) {
          final bs = (rawBreak['start']?.toString() ?? '').trim();
          final be = (rawBreak['end']?.toString() ?? '').trim();
          if (bs.isNotEmpty && be.isNotEmpty) {
            br = DayBreak(start: bs, end: be);
          }
        }
        out[wd] = DaySchedule(start: start, end: end, breakInterval: br);
      });
      if (out.isNotEmpty) return WorkSchedule(out);
      // Se veio work_schedule mas vazio/desabilitado, devolve vazio.
      // NÃO faz fallback para legado nesse caso (intenção explícita do dono).
      if (raw.isNotEmpty) return const WorkSchedule({});
    }

    // Fallback legado.
    final List<int> wd = _readWorkDaysLegacy(row);
    final String start = (row['work_start']?.toString().isNotEmpty == true
            ? row['work_start']
            : row['start_time'])
        ?.toString() ??
        '08:00';
    final String end = (row['work_end']?.toString().isNotEmpty == true
            ? row['work_end']
            : row['end_time'])
        ?.toString() ??
        '18:00';
    final Map<int, DaySchedule> out = {
      for (final d in wd)
        d: DaySchedule(start: start, end: end, breakInterval: null),
    };
    return WorkSchedule(out);
  }

  static List<int> _readWorkDaysLegacy(Map<String, dynamic> row) {
    final raw = row['work_days'];
    if (raw is List) {
      return raw
          .map((e) => int.tryParse(e.toString()) ?? -1)
          .where((v) => v >= 1 && v <= 7)
          .toList();
    }
    return const [];
  }

  /// Serializa para o JSONB (todos os 7 dias, com enabled true/false).
  Map<String, dynamic> toJson() {
    final Map<String, dynamic> out = {};
    for (var d = 1; d <= 7; d++) {
      final ds = days[d];
      if (ds == null) {
        out['$d'] = {'enabled': false};
      } else {
        out['$d'] = {
          'enabled': true,
          'start': ds.start,
          'end': ds.end,
          'break': ds.breakInterval == null
              ? null
              : {
                  'start': ds.breakInterval!.start,
                  'end': ds.breakInterval!.end,
                },
        };
      }
    }
    return out;
  }
}

class DaySchedule {
  final String start; // "HH:mm"
  final String end;   // "HH:mm"
  final DayBreak? breakInterval;

  const DaySchedule({
    required this.start,
    required this.end,
    this.breakInterval,
  });

  int get startMin => _hhmmToMin(start);
  int get endMin => _hhmmToMin(end);
}

class DayBreak {
  final String start; // "HH:mm"
  final String end;   // "HH:mm"
  const DayBreak({required this.start, required this.end});

  int get startMin => _hhmmToMin(start);
  int get endMin => _hhmmToMin(end);
}

int _hhmmToMin(String s) {
  final parts = s.split(':');
  final h = int.tryParse(parts.elementAt(0)) ?? 0;
  final m = parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0;
  return h * 60 + m;
}
