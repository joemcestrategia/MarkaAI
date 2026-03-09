import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

class AvailabilityUtils {
  /// Retorna uma lista de intervalos ocupados para um profissional em uma data específica.
  /// Cada intervalo é um Map com 'start' e 'end' em minutos desde o início do dia.
  static Future<List<Map<String, int>>> getBusyIntervals(
      String professionalId, DateTime date,
      {String? excludeDocId}) async {
    final startOfDay = DateTime(date.year, date.month, date.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));

    final snapshot = await FirebaseFirestore.instance
        .collection('appointments')
        .where('profissionalId', isEqualTo: professionalId)
        .where('data_agendamento',
            isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
        .where('data_agendamento', isLessThan: Timestamp.fromDate(endOfDay))
        .get();

    List<Map<String, int>> busy = [];

    for (var doc in snapshot.docs) {
      if (excludeDocId != null && doc.id == excludeDocId) {
        continue;
      }
      final data = doc.data();
      final status = data['status']?.toString().toLowerCase() ?? '';

      // Ignorar agendamentos cancelados ou rejeitados
      if (status == 'cancelado' ||
          status == 'rejeitado' ||
          status == 'excluido') {
        continue;
      }

      final Timestamp startTs = data['data_agendamento'];
      final DateTime startTime = startTs.toDate();

      int startMin = startTime.hour * 60 + startTime.minute;
      int duration =
          int.tryParse(data['duracao_min']?.toString() ?? '30') ?? 30;
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
        return false; // Conflito encontrado
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
          int slotEnd = current + serviceDuration;
          if (slotEnd > endDayMin) continue;
          bool hasCollision = false;
          for (var busy in busyIntervals) {
            if (current < busy['end']! && slotEnd > busy['start']!) {
              hasCollision = true;
              break;
            }
          }

          bool isPast = false;
          final now = DateTime.now();
          final slotDt = DateTime(selectedDate.year, selectedDate.month,
              selectedDate.day, current ~/ 60, current % 60);
          final minAllowedTime = now.add(Duration(hours: minAdvanceHours));
          if (slotDt.isBefore(minAllowedTime)) isPast = true;

          if (!hasCollision && !isPast) {
            String timeString =
                "${(current ~/ 60).toString().padLeft(2, '0')}:${(current % 60).toString().padLeft(2, '0')}";
            if (!validSlots.contains(timeString)) validSlots.add(timeString);
          }
        }
      } else {
        int current = startDayMin;
        while (current < endDayMin) {
          int slotEnd = current + serviceDuration;
          if (slotEnd > endDayMin) break;
          bool hasCollision = false;
          for (var busy in busyIntervals) {
            if (current < busy['end']! && slotEnd > busy['start']!) {
              hasCollision = true;
              break;
            }
          }

          bool isPast = false;
          final now = DateTime.now();
          final slotDt = DateTime(selectedDate.year, selectedDate.month,
              selectedDate.day, current ~/ 60, current % 60);
          final minAllowedTime = now.add(Duration(hours: minAdvanceHours));
          if (slotDt.isBefore(minAllowedTime)) isPast = true;

          if (!hasCollision && !isPast) {
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
