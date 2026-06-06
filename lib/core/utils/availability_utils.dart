import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';

class AvailabilityUtils {
  /// Retorna intervalos ocupados "reais" (agendamentos ativos + folgas longas)
  /// para um profissional em uma data específica.
  ///
  /// IMPORTANTE: a pausa diária (almoço) NÃO é incluída aqui — ela é tratada
  /// separadamente via parâmetro `breakInterval` em [generateSmartSlots] para
  /// preservar a semântica do modo `preventGaps` (que considera "dia sem
  /// agendamentos" diferente de "dia com pausa fixa").
  static Future<List<Map<String, int>>> getBusyIntervals(
      String professionalId, DateTime date,
      {String? excludeDocId}) async {
    final startOfDay = DateTime(date.year, date.month, date.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));

    final response = await Supabase.instance.client
        .from('appointments')
        .select()
        .eq('professional_id', professionalId)
        .gte('scheduled_at', startOfDay.toIso8601String())
        .lt('scheduled_at', endOfDay.toIso8601String());

    final List<dynamic> dataList = response;
    List<Map<String, int>> busy = [];

    // Otimização N+1: Coletar service_ids que precisam de duração
    final missingDurationServiceIds = dataList
        .where((d) =>
            int.tryParse(d['duration_min']?.toString() ?? '') == null &&
            d['service_id'] != null)
        .map((d) => d['service_id'].toString())
        .toSet()
        .toList();

    Map<String, int> serviceDurations = {};
    if (missingDurationServiceIds.isNotEmpty) {
      try {
        final servicesData = await Supabase.instance.client
            .from('services')
            .select('id, duration_min')
            .inFilter('id', missingDurationServiceIds);

        for (var s in servicesData) {
          serviceDurations[s['id'].toString()] =
              int.tryParse(s['duration_min']?.toString() ?? '') ?? 30;
        }
      } catch (e) {
        debugPrint("Erro ao buscar durações em lote: $e");
      }
    }

    for (var data in dataList) {
      if (excludeDocId != null && data['id']?.toString() == excludeDocId) {
        continue;
      }

      final status = data['status']?.toString().toLowerCase() ?? '';

      if (status == 'cancelado' ||
          status == 'rejeitado' ||
          status == 'recusado' ||
          status == 'excluido') {
        continue;
      }

      final DateTime startTime = DateTime.parse(data['scheduled_at']);
      int startMin = startTime.hour * 60 + startTime.minute;

      int? duration = int.tryParse(data['duration_min']?.toString() ?? '');

      if (duration == null) {
        String? servicoId = data['service_id']?.toString();
        if (servicoId != null && servicoId.isNotEmpty) {
          duration = serviceDurations[servicoId];
        }
        duration ??= 30;
      }

      int endMin = startMin + duration;
      busy.add({'start': startMin, 'end': endMin});
    }

    // Folgas longas (date-range — férias, médico, etc.) continuam aqui.
    try {
      final empRes = await Supabase.instance.client
          .from('employees')
          .select('breaks')
          .eq('id', professionalId)
          .maybeSingle();

      if (empRes != null && empRes['breaks'] != null) {
        final List<dynamic> folgasList = empRes['breaks'];
        for (var folga in folgasList) {
          final startFolgaStr = folga['start']?.toString();
          final endFolgaStr = folga['end']?.toString();

          if (startFolgaStr != null && endFolgaStr != null) {
            final startFolga = DateTime.parse(startFolgaStr);
            final endFolga = DateTime.parse(endFolgaStr);

            if (startFolga.isBefore(endOfDay) &&
                endFolga.isAfter(startOfDay)) {
              int fStartMin = 0;
              if (startFolga.year == date.year &&
                  startFolga.month == date.month &&
                  startFolga.day == date.day) {
                fStartMin = startFolga.hour * 60 + startFolga.minute;
              }

              int fEndMin = 1440;
              if (endFolga.year == date.year &&
                  endFolga.month == date.month &&
                  endFolga.day == date.day) {
                fEndMin = endFolga.hour * 60 + endFolga.minute;
              }

              busy.add({'start': fStartMin, 'end': fEndMin});
            }
          }
        }
      }
    } catch (e) {
      debugPrint("Erro ao buscar folgas do profissional: $e");
    }

    return busy;
  }

  /// Verifica se um determinado horário está disponível.
  static bool isSlotAvailable(
      int startMin, int duration, List<Map<String, int>> busyIntervals) {
    int endMin = startMin + duration;
    for (var interval in busyIntervals) {
      if (startMin < interval['end']! && endMin > interval['start']!) {
        return false;
      }
    }
    return true;
  }

  /// Gera slots disponíveis (HH:mm).
  ///
  /// [busyIntervals] — agendamentos REAIS (+ folgas longas).
  /// [breakInterval] — pausa fixa diária (almoço, etc.). Tratada como bloqueio
  ///   adicional, MAS não conta como "agendamento" para o critério de
  ///   `preventGaps` (sem isso, dia sem agendamentos com pausa de almoço
  ///   ofereceria apenas o slot logo após o almoço, em vez do início do dia).
  static List<String> generateSmartSlots({
    required String startStr,
    required String endStr,
    required int interval,
    required int serviceDuration,
    required List<Map<String, int>> busyIntervals,
    required bool preventGaps,
    required int minAdvanceHours,
    required DateTime selectedDate,
    Map<String, int>? breakInterval,
  }) {
    List<String> validSlots = [];
    try {
      int startDayMin = int.parse(startStr.split(':')[0]) * 60 +
          int.parse(startStr.split(':')[1]);
      int endDayMin = int.parse(endStr.split(':')[0]) * 60 +
          int.parse(endStr.split(':')[1]);

      if (interval <= 0) {
        debugPrint(
            '⚠️ AvailabilityUtils: intervalo inválido ($interval). Abortando.');
        return [];
      }

      // Lista combinada (real + pausa) para teste de colisão.
      final List<Map<String, int>> allBusy = [
        ...busyIntervals,
        if (breakInterval != null) breakInterval,
      ];
      allBusy.sort((a, b) => a['start']!.compareTo(b['start']!));
      busyIntervals.sort((a, b) => a['start']!.compareTo(b['start']!));

      bool collidesAny(int s, int e) =>
          allBusy.any((b) => s < b['end']! && e > b['start']!);

      if (preventGaps) {
        // Modo "sem buracos": apenas startDayMin (se livre) e fins de
        // agendamentos REAIS são âncoras. A pausa NÃO gera nova âncora — o
        // primeiro slot do dia continua sendo o início do expediente, e ao
        // colidir com a pausa, o ponto avança até o fim dela.
        Set<int> anchorPoints = {};

        // Âncora: início do expediente (se não colide com nada — nem pausa).
        if (!collidesAny(startDayMin, startDayMin + serviceDuration)) {
          anchorPoints.add(startDayMin);
        } else if (breakInterval != null &&
            startDayMin >= breakInterval['start']! &&
            startDayMin < breakInterval['end']!) {
          // Caso degenerado: expediente começa exatamente dentro da pausa
          // (configuração estranha). Avança para o fim da pausa.
          final after = breakInterval['end']!;
          if (!collidesAny(after, after + serviceDuration)) {
            anchorPoints.add(after);
          }
        }

        // Âncora: fim de cada agendamento real.
        for (var busy in busyIntervals) {
          if (busy['end']! < endDayMin) {
            anchorPoints.add(busy['end']!);
          }
        }

        // Âncora extra: fim da pausa, mas SOMENTE se houver agendamento
        // antes dela. Caso contrário, dia sem agendamentos manteria o
        // início do expediente como única âncora (regra clássica).
        if (breakInterval != null && busyIntervals.isNotEmpty) {
          final firstBusyStart = busyIntervals.first['start']!;
          if (firstBusyStart < breakInterval['start']!) {
            anchorPoints.add(breakInterval['end']!);
          }
        }

        final List<int> sortedAnchors = anchorPoints.toList()..sort();
        for (final anchor in sortedAnchors) {
          final anchorEnd = anchor + serviceDuration;
          if (anchorEnd > endDayMin) continue;
          if (collidesAny(anchor, anchorEnd)) continue;

          final now = DateTime.now();
          final slotDt = DateTime(selectedDate.year, selectedDate.month,
              selectedDate.day, anchor ~/ 60, anchor % 60);
          final minAllowedTime = now.add(Duration(hours: minAdvanceHours));
          if (slotDt.isBefore(minAllowedTime)) continue;

          final String timeString =
              "${(anchor ~/ 60).toString().padLeft(2, '0')}:${(anchor % 60).toString().padLeft(2, '0')}";
          if (!validSlots.contains(timeString)) validSlots.add(timeString);
        }
      } else {
        int current = startDayMin;
        while (current + serviceDuration <= endDayMin) {
          int slotEnd = current + serviceDuration;
          bool hasCollision = false;
          int jumpTo = current + interval;

          for (var busy in allBusy) {
            if (current < busy['end']! && slotEnd > busy['start']!) {
              hasCollision = true;
              jumpTo = busy['end']!;
              break;
            }
          }

          if (hasCollision) {
            current = jumpTo;
            continue;
          }

          bool isPast = false;
          final now = DateTime.now();
          final slotDt = DateTime(selectedDate.year, selectedDate.month,
              selectedDate.day, current ~/ 60, current % 60);
          final minAllowedTime = now.add(Duration(hours: minAdvanceHours));
          if (slotDt.isBefore(minAllowedTime)) isPast = true;

          if (!isPast) {
            String timeString =
                "${(current ~/ 60).toString().padLeft(2, '0')}:${(current % 60).toString().padLeft(2, '0')}";
            validSlots.add(timeString);
          }
          current += interval;
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print("Erro generateSmartSlots: $e");
      }
    }

    validSlots.sort((a, b) {
      int minA = int.parse(a.split(':')[0]) * 60 + int.parse(a.split(':')[1]);
      int minB = int.parse(b.split(':')[0]) * 60 + int.parse(b.split(':')[1]);
      return minA.compareTo(minB);
    });

    return validSlots;
  }
}
