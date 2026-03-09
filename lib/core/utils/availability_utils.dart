import 'package:cloud_firestore/cloud_firestore.dart';

class AvailabilityUtils {
  /// Retorna uma lista de intervalos ocupados para um profissional em uma data específica.
  /// Cada intervalo é um Map com 'start' e 'end' em minutos desde o início do dia.
  static Future<List<Map<String, int>>> getBusyIntervals(
      String professionalId, DateTime date) async {
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
}
