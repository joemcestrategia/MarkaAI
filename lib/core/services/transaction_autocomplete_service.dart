import 'package:supabase_flutter/supabase_flutter.dart';
import '../utils/availability_utils.dart';
import '../utils/work_schedule.dart';

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
    
    // Busca todos os funcionários da loja uma única vez para filtrar
    final allProsSnap = await supabase
        .from('employees')
        .select()
        .eq('shop_id', shopId);
    
    if (allProsSnap.isEmpty) return [];
    final List<Map<String, dynamic>> allPros = List<Map<String, dynamic>>.from(allProsSnap);

    // Se temos serviceId, procuramos por habilidade
    if (serviceId != null && serviceId.isNotEmpty) {
      final String targetId = serviceId.toString();
      
      final prosBySkill = allPros.where((p) {
        final List<dynamic> skills = p['services_ids'] ?? [];
        return skills.map((id) => id.toString()).contains(targetId);
      }).toList();
      
      if (prosBySkill.isNotEmpty) return prosBySkill;

      // Fallback: Verificar o contrário (se no serviço tem 'profissionais_aptos')
      final svcDoc = await supabase.from('services').select().eq('id', serviceId).maybeSingle();
      if (svcDoc != null) {
        final aptos = List<String>.from(svcDoc['profissionais_aptos'] ?? []);
        if (aptos.isNotEmpty) {
          return allPros.where((p) => aptos.contains(p['id'].toString())).toList();
        }
      }
    }

    // Fallback total: todos os funcionários ativos da loja
    return allPros;
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
    
    // 1. Check weekday + per-day schedule
    final ws = WorkSchedule.fromEmployeeRow(data);
    int weekday = targetDate.weekday; // 1=Seg...7=Dom
    final dayCfg = ws.forWeekday(weekday);
    if (dayCfg == null) {
      // Compat: lista legada usando 0 para domingo
      final List<int> legacy = List<int>.from(data['work_days'] ?? []);
      if (!(weekday == 7 && (legacy.contains(0) || legacy.contains(7)))) {
        return false;
      }
    }

    // 2. Check business hours (per-day)
    final String startStr = dayCfg?.start ?? (data['work_start'] ?? "08:00");
    final String endStr = dayCfg?.end ?? (data['work_end'] ?? "18:00");
    int startDayMin = int.parse(startStr.split(':')[0]) * 60 + int.parse(startStr.split(':')[1]);
    int endDayMin = int.parse(endStr.split(':')[0]) * 60 + int.parse(endStr.split(':')[1]);

    int targetStartMin = targetDate.hour * 60 + targetDate.minute;
    if (targetDate.hour == 0 && targetDate.minute == 0) {
      // Se for apenas data sem hora, assumimos que precisa estar aberto.
    } else {
      if (targetStartMin < startDayMin || (targetStartMin + durationMin) > endDayMin) {
        return false;
      }
      // Pausa diária: rejeita se colide.
      final br = dayCfg?.breakInterval;
      if (br != null &&
          targetStartMin < br.endMin &&
          (targetStartMin + durationMin) > br.startMin) {
        return false;
      }
    }

    // 3. Check overlaps (incluindo pausa via breakInterval seria redundante:
    // já validamos acima; aqui verificamos somente agendamentos reais).
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
          .eq('shop_id', shopId)
          .eq('professional_id', pro['id'])
          .gte('scheduled_at', startOfMonth.toIso8601String())
          .lte('scheduled_at', endOfMonth.toIso8601String())
          .neq('status', 'cancelado')
          .count(CountOption.exact);
      workload[pro['id']] = res.count;
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
    final String? escaped = (search != null && search.trim().isNotEmpty)
        ? search.trim().replaceAll(r'\', r'\\').replaceAll('%', r'\%').replaceAll('_', r'\_')
        : null;

    // Normalização usada para evitar duplicar um cliente manual que já
    // aparece nos agendamentos (mesmo nome + mesmo telefone).
    String digits(String v) => v.replaceAll(RegExp(r'\D'), '');
    String norm(String v) => v.trim().toLowerCase();

    // 1. Clientes cadastrados MANUALMENTE pelo lojista (shop_clients).
    //    Mesmo sem nenhum agendamento anterior, eles precisam aparecer
    //    imediatamente para que o lojista consiga agendar.
    //    Só entram registros sem conta Auth (user_id nulo): clientes com
    //    conta aparecem via appointments/users.
    var manualQuery = supabase
        .from('shop_clients')
        .select('id, nome, telefone, notes')
        .eq('shop_id', shopId)
        .eq('is_manual_client', true)
        .isFilter('user_id', null);

    if (escaped != null) {
      manualQuery = manualQuery.or('nome.ilike.%$escaped%,telefone.ilike.%$escaped%');
    }

    List<dynamic> manualRows = [];
    try {
      manualRows = await manualQuery.order('last_updated', ascending: false).limit(100);
    } catch (_) {
      // Falha na busca de cadastros manuais não deve quebrar o autocomplete.
    }

    final Map<String, Map<String, dynamic>> uniqueClients = {};
    final Set<String> manualSignatures = {};

    for (var row in manualRows) {
      if ((row['notes'] ?? '').toString() == '[DELETED_MANUAL]') continue;
      final name = row['nome']?.toString() ?? '';
      final phone = row['telefone']?.toString() ?? '';
      final scId = row['id']?.toString() ?? '';
      if (name.isEmpty || scId.isEmpty) continue;

      manualSignatures.add('${norm(name)}|${digits(phone)}');
      uniqueClients['sc:$scId'] = {
        'id': null, // sem conta Auth: o agendamento é gravado só com nome/telefone
        'name': name,
        'phone': phone,
        'isManual': true,
        'shopClientId': scId,
      };
    }

    // 2. Busca na tabela appointments por clientes que já agendaram
    var query = supabase
        .from('appointments')
        .select('client_name, client_phone, client_id')
        .eq('shop_id', shopId);

    if (escaped != null) {
      query = query.or('client_name.ilike.%$escaped%,client_phone.ilike.%$escaped%');
    }

    final List<dynamic> apps = await query.order('scheduled_at', ascending: false).limit(200);

    for (var app in apps) {
      final name = app['client_name']?.toString() ?? '';
      final phone = app['client_phone']?.toString() ?? '';
      final id = app['client_id']?.toString() ?? '';

      if (name.isEmpty && id.isEmpty) continue;

      // Já listado como cadastro manual (mesmo nome + telefone): não duplica.
      if (id.isEmpty && manualSignatures.contains('${norm(name)}|${digits(phone)}')) {
        continue;
      }

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

    return uniqueClients.values.toList();
  }
}
