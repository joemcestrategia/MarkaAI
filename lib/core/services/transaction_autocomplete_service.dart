import 'package:supabase_flutter/supabase_flutter.dart';
import '../utils/availability_utils.dart';

class TransactionAutocompleteService {
  static const double kMinJaccardScore = 0.40;

  /// Algoritmo de associação de serviços (Fuzzy Matching)
  static Future<Map<String, dynamic>?> findBestMatchingService({
    required String shopId,
    required String rawName,
  }) async {
    if (rawName.trim().isEmpty) return null;
    final supabase = Supabase.instance.client;
    final search = rawName.trim().toLowerCase();

    final svcSnap = await supabase
        .from('services')
        .select()
        .eq('shop_id', shopId);

    if (svcSnap.isEmpty) return null;

    final List<Map<String, dynamic>> docs = List<Map<String, dynamic>>.from(svcSnap);

    // 1. Match exato
    for (var doc in docs) {
      final name = (doc['name'] ?? '').toString().trim().toLowerCase();
      if (name == search) return doc;
    }

    // 2. Match por containment
    Map<String, dynamic>? bestContainment;
    int maxOverlap = 0;
    for (var doc in docs) {
      final name = (doc['name'] ?? '').toString().trim().toLowerCase();
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
    Map<String, dynamic>? bestJaccard;
    double maxScore = 0;

    final rawTokens = search.split(RegExp(r'\s+')).where((t) => t.length > 2).toSet();
    if (rawTokens.isEmpty) return null;

    for (var doc in docs) {
      final canonicalName = (doc['name'] ?? '').toString().trim().toLowerCase();
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
  static Future<List<Map<String, dynamic>>> getCandidates({
    required String shopId,
    required String? serviceId,
  }) async {
    final supabase = Supabase.instance.client;
    
    // Se temos serviceId, procuramos por habilidade
    if (serviceId != null && serviceId.isNotEmpty) {
      // Tenta buscar funcionários que tenham o serviço em 'services_ids'
      final prosBySkill = await supabase
          .from('employees')
          .select()
          .eq('shop_id', shopId)
          .contains('services_ids', [serviceId]);
      
      if (prosBySkill.isNotEmpty) return List<Map<String, dynamic>>.from(prosBySkill);

      // Fallback: Verificar o contrário (se no serviço tem 'profissionais_aptos')
      final svcDoc = await supabase.from('services').select().eq('id', serviceId).maybeSingle();
      if (svcDoc != null) {
        final aptos = List<String>.from(svcDoc['profissionais_aptos'] ?? []);
        if (aptos.isNotEmpty) {
          final prosBySvc = await supabase
              .from('employees')
              .select()
              .inFilter('id', aptos);
          return List<Map<String, dynamic>>.from(prosBySvc);
        }
      }
    }

    // Fallback total: todos os funcionários ativos
    final allPros = await supabase
        .from('employees')
        .select()
        .eq('shop_id', shopId);
    return List<Map<String, dynamic>>.from(allPros);
  }

  /// Verifica se o profissional está disponível no dia e horário
  static Future<bool> isProfessionalAvailable({
    required String employeeId,
    required DateTime targetDate,
    int durationMin = 60,
    String? excludeDocId,
  }) async {
    final supabase = Supabase.instance.client;
    final empDoc = await supabase.from('employees').select().eq('id', employeeId).maybeSingle();
    if (empDoc == null) return false;

    final data = empDoc;
    
    // 1. Check weekday
    final List<int> workDays = List<int>.from(data['work_days'] ?? []);
    int weekday = targetDate.weekday; // 1=Seg...7=Dom
    // Se a lista usa 0 para domingo, precisamos converter
    if (!workDays.contains(weekday)) {
       // Tenta o 0 se for 7
       if (weekday == 7 && (workDays.contains(0) || workDays.contains(7))) {
         // ok
       } else {
         return false;
       }
    }

    // 2. Check business hours
    final String startStr = data['work_start'] ?? "08:00";
    final String endStr = data['work_end'] ?? "18:00";
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
  static Future<List<Map<String, dynamic>>> rankCandidatesByWorkload({
    required String shopId,
    required List<Map<String, dynamic>> candidates,
    required DateTime targetMonth,
  }) async {
    if (candidates.isEmpty) return [];
    
    final supabase = Supabase.instance.client;
    final startOfMonth = DateTime(targetMonth.year, targetMonth.month, 1);
    final endOfMonth = DateTime(targetMonth.year, targetMonth.month + 1, 0, 23, 59, 59);

    Map<String, int> workload = {};
    
    // Para cada candidato, contamos documentos em 'appointments' no mês
    for (var pro in candidates) {
      final res = await supabase
          .from('appointments')
          .select()
          .eq('professional_id', pro['id'])
          .gte('scheduled_at', startOfMonth.toIso8601String())
          .lte('scheduled_at', endOfMonth.toIso8601String())
          .neq('status', 'cancelado')
          .count(CountOption.exact);
      
      workload[pro['id']] = res.count ?? 0;
    }

    final sortedCandidates = List<Map<String, dynamic>>.from(candidates);
    sortedCandidates.sort((a, b) => (workload[a['id']] ?? 0).compareTo(workload[b['id']] ?? 0));

    return sortedCandidates;
  }

  /// Busca clientes recentes (manuais e registrados) para autocomplete
  static Future<List<Map<String, dynamic>>> findRecentClients({
    required String shopId,
    String? search,
  }) async {
    final supabase = Supabase.instance.client;
    
    // 1. Busca na tabela appointments por clientes que já agendaram
    var query = supabase
        .from('appointments')
        .select('client_name, client_phone, client_id')
        .eq('shop_id', shopId);

    if (search != null && search.trim().isNotEmpty) {
      final s = search.trim();
      query = query.or('client_name.ilike.%$s%,client_phone.ilike.%$s%');
    }

    final List<dynamic> apps = await query.order('scheduled_at', ascending: false).limit(200);
    
    final Map<String, Map<String, dynamic>> uniqueClients = {};

    for (var app in apps) {
      final name = app['client_name']?.toString() ?? '';
      final phone = app['client_phone']?.toString() ?? '';
      final id = app['client_id']?.toString() ?? '';

      if (name.isEmpty && id.isEmpty) continue;

      // Chave única: ID se existir (registrado), senão Telefone (manual recorrente), senão Nome
      final key = id.isNotEmpty ? id : (phone.isNotEmpty ? phone : name);
      
      if (!uniqueClients.containsKey(key)) {
        uniqueClients[key] = {
          'id': id.isNotEmpty ? id : null,
          'name': name,
          'phone': phone,
          'isManual': id.isEmpty,
        };
      }
    }

    // 2. Opcional: Busca na tabela shop_clients para pegar clientes cadastrados sem agendamento
    // (Poderia ser adicionado aqui se necessário, mas a busca em appointments já cobre a maioria dos casos)

    return uniqueClients.values.toList();
  }
}
