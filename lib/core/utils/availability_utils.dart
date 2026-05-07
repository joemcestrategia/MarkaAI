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

    // 1. Processar Agendamentos
    
    // Otimização N+1: Coletar service_ids que precisam de duração
    final missingDurationServiceIds = dataList
        .where((d) => int.tryParse(d['duration_min']?.toString() ?? '') == null && d['service_id'] != null)
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
          serviceDurations[s['id'].toString()] = int.tryParse(s['duration_min']?.toString() ?? '') ?? 30;
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

      // Ignorar agendamentos cancelados ou rejeitados (ambas as grafias)
      if (status == 'cancelado' ||
          status == 'rejeitado' ||
          status == 'recusado' ||
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
          duration = serviceDurations[servicoId];
        }
        duration ??= 30;
      }

      int endMin = startMin + duration;
      busy.add({'start': startMin, 'end': endMin});
    }

    // 2. Processar Folgas (Breaks) do Profissional
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
            
            // Verifica se a folga sobrepõe o dia selecionado
            if (startFolga.isBefore(endOfDay) && endFolga.isAfter(startOfDay)) {
              // Calcular minutos no dia selecionado
              int fStartMin = 0;
              if (startFolga.year == date.year && startFolga.month == date.month && startFolga.day == date.day) {
                fStartMin = startFolga.hour * 60 + startFolga.minute;
              }
              
              int fEndMin = 1440; // 24h em minutos
              if (endFolga.year == date.year && endFolga.month == date.month && endFolga.day == date.day) {
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
        if (busyIntervals.isEmpty) {
          // Sem agendamentos existentes: oferece apenas o PRIMEIRO slot disponível.
          // Regra: o cliente só pode agendar no início do expediente (ou no primeiro
          // horário disponível após o limite de antecedência mínima).
          // O serviço nunca pode ultrapassar o horário final do funcionário (endDayMin).
          int current = startDayMin;
          while (current + serviceDuration <= endDayMin) {
            final now = DateTime.now();
            final slotDt = DateTime(selectedDate.year, selectedDate.month,
                selectedDate.day, current ~/ 60, current % 60);
            final minAllowedTime = now.add(Duration(hours: minAdvanceHours));
            if (!slotDt.isBefore(minAllowedTime)) {
              final String timeString =
                  "${(current ~/ 60).toString().padLeft(2, '0')}:${(current % 60).toString().padLeft(2, '0')}";
              validSlots.add(timeString);
              break; // ← apenas o primeiro slot válido é retornado
            }
            current += interval;
          }
        } else {
          // Com agendamentos existentes: oferece apenas slots que não criam buracos.
          // Regra: cada âncora é o ponto exato em que o próximo serviço pode começar.
          // Âncoras válidas: startDayMin (se livre) + fim de cada agendamento existente.
          // Cada âncora é avaliada atomicamente — sem avançar além do ponto âncora.
          Set<int> anchorPoints = {};

          // startDayMin só é âncora se não há colisão nesse horário exato
          final startSlotEnd = startDayMin + serviceDuration;
          final startIsFree = busyIntervals.every(
            (b) => !(startDayMin < b['end']! && startSlotEnd > b['start']!),
          );
          if (startIsFree) {
            anchorPoints.add(startDayMin);
          }

          // Fim de cada agendamento existente é uma âncora em potencial
          for (var busy in busyIntervals) {
            if (busy['end']! < endDayMin) {
              anchorPoints.add(busy['end']!);
            }
          }

          List<int> sortedAnchors = anchorPoints.toList()..sort();

          for (int anchor in sortedAnchors) {
            // Verifica se o slot exato nesse anchor está livre (sem colisão)
            final anchorSlotEnd = anchor + serviceDuration;
            final hasCollision = busyIntervals.any(
              (b) => anchor < b['end']! && anchorSlotEnd > b['start']!,
            );
            if (hasCollision) continue;

            // Verifica se o slot não ultrapassa o fim do expediente
            if (anchorSlotEnd > endDayMin) continue;

            // Verifica restrição de antecedência mínima
            final now = DateTime.now();
            final slotDt = DateTime(selectedDate.year, selectedDate.month,
                selectedDate.day, anchor ~/ 60, anchor % 60);
            final minAllowedTime = now.add(Duration(hours: minAdvanceHours));
            if (slotDt.isBefore(minAllowedTime)) continue;

            final String timeString =
                "${(anchor ~/ 60).toString().padLeft(2, '0')}:${(anchor % 60).toString().padLeft(2, '0')}";
            if (!validSlots.contains(timeString)) validSlots.add(timeString);
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
