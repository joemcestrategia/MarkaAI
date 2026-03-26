import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';

class AvailabilityUtils {
  /// Retorna uma lista de intervalos ocupados para um profissional em uma data específica.
  /// Cada intervalo é um Map com 'start' e 'end' em minutos desde o início do dia.
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

    for (var data in dataList) {
      if (excludeDocId != null && data['id']?.toString() == excludeDocId) {
        continue;
      }
      
      final status = data['status']?.toString().toLowerCase() ?? '';

      // Ignorar agendamentos cancelados ou rejeitados
      if (status == 'cancelado' ||
          status == 'rejeitado' ||
          status == 'excluido') {
        continue;
      }

      final DateTime startTime = DateTime.parse(data['scheduled_at']);
      int startMin = startTime.hour * 60 + startTime.minute;

      int? duration = int.tryParse(data['duration_min']?.toString() ?? '');

      // Fallback para compromissos legados
      if (duration == null) {
        String? servicoId = data['service_id']?.toString();
        if (servicoId != null && servicoId.isNotEmpty) {
          try {
            final svcDoc = await Supabase.instance.client
                .from('services')
                .select()
                .eq('id', servicoId)
                .maybeSingle();
            if (svcDoc != null) {
              duration = int.tryParse(svcDoc['duration_min']?.toString() ?? '');
            }
          } catch (e) {
            debugPrint("Erro ao buscar duração original do serviço antigo: $e");
          }
        }
        duration ??= 30;
      }

      int endMin = startMin + duration;
      busy.add({'start': startMin, 'end': endMin});
    }

    return busy;
  }

  /// Verifica se um determinado horário está disponível para um profissional.
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

  /// Gera uma lista de horários (HH:mm) disponíveis baseados nos parâmetros.
  static List<String> generateSmartSlots({
    required String startStr,
    required String endStr,
    required int interval,
    required int serviceDuration,
    required List<Map<String, int>> busyIntervals,
    required bool preventGaps,
    required int minAdvanceHours,
    required DateTime selectedDate,
  }) {
    List<String> validSlots = [];
    try {
      int startDayMin = int.parse(startStr.split(':')[0]) * 60 +
          int.parse(startStr.split(':')[1]);
      int endDayMin = int.parse(endStr.split(':')[0]) * 60 +
          int.parse(endStr.split(':')[1]);

      // Proteção contra loop infinito se o intervalo for inválido
      if (interval <= 0) {
        debugPrint('⚠️ AvailabilityUtils: intervalo inválido ($interval). Abortando geração.');
        return [];
      }

      busyIntervals.sort((a, b) => a['start']!.compareTo(b['start']!));

      if (preventGaps) {
        Set<int> anchorPoints = {startDayMin};
        for (var busy in busyIntervals) {
          if (busy['end']! < endDayMin) {
            anchorPoints.add(busy['end']!);
          }
        }

        List<int> sortedAnchors = anchorPoints.toList()..sort();

        for (int anchor in sortedAnchors) {
          int current = anchor;
          while (current + serviceDuration <= endDayMin) {
            int slotEnd = current + serviceDuration;
            bool hasCollision = false;
            int jumpTo = current + interval;

            for (var busy in busyIntervals) {
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
              if (!validSlots.contains(timeString)) validSlots.add(timeString);
            }
            break;
          }
        }
      } else {
        int current = startDayMin;
        while (current + serviceDuration <= endDayMin) {
          int slotEnd = current + serviceDuration;
          bool hasCollision = false;
          int jumpTo = current + interval;

          for (var busy in busyIntervals) {
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
