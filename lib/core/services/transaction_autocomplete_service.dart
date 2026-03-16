import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/availability_utils.dart';

class TransactionAutocompleteService {
  static const double kMinJaccardScore = 0.40;

  /// Algoritmo de associação de serviços (Fuzzy Matching)
  static Future<DocumentSnapshot?> findBestMatchingService({
    required String shopId,
    required String rawName,
  }) async {
    if (rawName.trim().isEmpty) return null;
    final firestore = FirebaseFirestore.instance;
    final search = rawName.trim().toLowerCase();

    final svcSnap = await firestore
        .collection('services')
        .where('shopId', isEqualTo: shopId)
        .get();

    if (svcSnap.docs.isEmpty) return null;

    // 1. Match exato
    for (var doc in svcSnap.docs) {
      final name = (doc.data()['nome'] ?? '').toString().trim().toLowerCase();
      if (name == search) return doc;
    }

    // 2. Match por containment
    DocumentSnapshot? bestContainment;
    int maxOverlap = 0;
    for (var doc in svcSnap.docs) {
      final name = (doc.data()['nome'] ?? '').toString().trim().toLowerCase();
      if (name.contains(search) || search.contains(name)) {
        int overlap = name.length > search.length ? search.length : name.length;
        if (overlap > maxOverlap) {
          maxOverlap = overlap;
          bestContainment = doc;
        }
      }
    }
    if (bestContainment != null) return bestContainment;

    // 3. Match por tokens (Jaccard)
    DocumentSnapshot? bestJaccard;
    double maxScore = 0;

    final rawTokens = search.split(RegExp(r'\s+')).where((t) => t.length > 2).toSet();
    if (rawTokens.isEmpty) return null;

    for (var doc in svcSnap.docs) {
      final canonicalName = (doc.data()['nome'] ?? '').toString().trim().toLowerCase();
      final canonicalTokens = canonicalName.split(RegExp(r'\s+')).where((t) => t.length > 2).toSet();
      
      if (canonicalTokens.isEmpty) continue;

      final intersection = rawTokens.intersection(canonicalTokens).length;
      final union = rawTokens.union(canonicalTokens).length;
      final score = intersection / union;

      if (score >= kMinJaccardScore && score > maxScore) {
        maxScore = score;
        bestJaccard = doc;
      }
    }

    return bestJaccard;
  }

  /// Busca candidatos aptos para realizar o serviço
  static Future<List<DocumentSnapshot>> getCandidates({
    required String shopId,
    required String? serviceId,
  }) async {
    final firestore = FirebaseFirestore.instance;
    
    // Se temos serviceId, procuramos por habilidade
    if (serviceId != null && serviceId.isNotEmpty) {
      // Tenta buscar funcionários que tenham o serviço em 'servicos_habilidade'
      final prosBySkill = await firestore
          .collection('employees')
          .where('shopId', isEqualTo: shopId)
          .where('servicos_habilidade', arrayContains: serviceId)
          .get();
      
      if (prosBySkill.docs.isNotEmpty) return prosBySkill.docs;

      // Fallback: Verificar o contrário (se no serviço tem 'profissionais_aptos')
      final svcDoc = await firestore.collection('services').doc(serviceId).get();
      if (svcDoc.exists) {
        final aptos = List<String>.from(svcDoc.data()?['profissionais_aptos'] ?? []);
        if (aptos.isNotEmpty) {
          final prosBySvc = await firestore
              .collection('employees')
              .where(FieldPath.documentId, whereIn: aptos)
              .get();
          return prosBySvc.docs;
        }
      }
    }

    // Fallback total: todos os funcionários ativos
    final allPros = await firestore
        .collection('employees')
        .where('shopId', isEqualTo: shopId)
        .get();
    return allPros.docs;
  }

  /// Verifica se o profissional está disponível no dia e horário
  static Future<bool> isProfessionalAvailable({
    required String employeeId,
    required DateTime targetDate,
    int durationMin = 60,
    String? excludeDocId,
  }) async {
    final firestore = FirebaseFirestore.instance;
    final empDoc = await firestore.collection('employees').doc(employeeId).get();
    if (!empDoc.exists) return false;

    final data = empDoc.data()!;
    
    // 1. Check weekday
    final List<int> workDays = List<int>.from(data['dias_trabalho'] ?? []);
    int weekday = targetDate.weekday; // 1=Seg...7=Dom
    // Se a lista usa 0 para domingo, precisamos converter
    if (!workDays.contains(weekday)) {
       // Tenta o 0 se for 7
       if (weekday == 7 && workDays.contains(0)) {
         // ok
       } else {
         return false;
       }
    }

    // 2. Check business hours
    final String startStr = data['horario_inicio'] ?? "08:00";
    final String endStr = data['horario_fim'] ?? "18:00";
    int startDayMin = int.parse(startStr.split(':')[0]) * 60 + int.parse(startStr.split(':')[1]);
    int endDayMin = int.parse(endStr.split(':')[0]) * 60 + int.parse(endStr.split(':')[1]);
    
    int targetStartMin = targetDate.hour * 60 + targetDate.minute;
    if (targetDate.hour == 0 && targetDate.minute == 0) {
      // Se for apenas data sem hora, assumimos que precisa estar aberto
      // Critério relaxado: se ele trabalha no dia, está "possivelmente" disponível
    } else {
      if (targetStartMin < startDayMin || (targetStartMin + durationMin) > endDayMin) {
        return false;
      }
    }

    // 3. Check overlaps
    final busy = await AvailabilityUtils.getBusyIntervals(employeeId, targetDate, excludeDocId: excludeDocId);
    return AvailabilityUtils.isSlotAvailable(targetStartMin, durationMin, busy);
  }

  /// Ordena os candidatos pela carga de trabalho no mês
  static Future<List<DocumentSnapshot>> rankCandidatesByWorkload({
    required String shopId,
    required List<DocumentSnapshot> candidates,
    required DateTime targetMonth,
  }) async {
    if (candidates.isEmpty) return [];
    
    final firestore = FirebaseFirestore.instance;
    final startOfMonth = DateTime(targetMonth.year, targetMonth.month, 1);
    final endOfMonth = DateTime(targetMonth.year, targetMonth.month + 1, 0, 23, 59, 59);

    Map<String, int> workload = {};
    
    // Para cada candidato, contamos documentos em 'appointments' no mês
    for (var pro in candidates) {
      final snap = await firestore
          .collection('appointments')
          .where('profissionalId', isEqualTo: pro.id)
          .where('data_agendamento', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfMonth))
          .where('data_agendamento', isLessThanOrEqualTo: Timestamp.fromDate(endOfMonth))
          .where('status', isNotEqualTo: 'cancelado')
          .count()
          .get();
      workload[pro.id] = snap.count ?? 0;
    }

    final sortedCandidates = List<DocumentSnapshot>.from(candidates);
    sortedCandidates.sort((a, b) => (workload[a.id] ?? 0).compareTo(workload[b.id] ?? 0));

    return sortedCandidates;
  }
}
