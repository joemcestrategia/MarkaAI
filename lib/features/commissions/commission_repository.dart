import 'package:supabase_flutter/supabase_flutter.dart';
import 'commission_models.dart';

class CommissionRepository {
  final SupabaseClient _client;

  CommissionRepository(this._client);

  Future<List<CommissionDetailWithEmployeeInfo>> fetchCommissions({
    required String shopId,
    required int month,
    required int year,
    String? employeeId,
  }) async {
    final start = DateTime(year, month, 1);
    // Para pegar até o último dia do mês, ou avança 1 mês.
    final end = DateTime(year, month + 1, 1);

    var query = _client
        .from('vw_commission_summary')
        .select('*, employee_id, employee_name, employee_avatar') // Para garantir que extraímos esses dados pro fromMap interno de fromDetails, mas eles no the CommissionDetail só ficam em map
        .eq('shop_id', shopId)
        .gte('scheduled_at', start.toIso8601String())
        .lt('scheduled_at', end.toIso8601String());

    if (employeeId != null && employeeId.isNotEmpty) {
      query = query.eq('employee_id', employeeId);
    }

    final data = await query.order('scheduled_at', ascending: false);
    
    // Passar employeeId, employeeName, employeeAvatar implicitamente no Map retornado para o agrupador
    return (data as List).map((e) {
      return CommissionDetailWithEmployeeInfo(
        detail: CommissionDetail.fromMap(e),
        employeeId: e['employee_id'] as String?,
        employeeName: e['employee_name'] as String?,
        employeeAvatar: e['employee_avatar'] as String?,
      );
    }).toList();
  }

  List<CommissionSummary> groupByProfessional(
    List<dynamic> itemsWithEmployeeInfo,
  ) {
    final map = <String, List<CommissionDetailWithEmployeeInfo>>{};
    for (var item in itemsWithEmployeeInfo) {
      final info = item as CommissionDetailWithEmployeeInfo;
      map.putIfAbsent(info.employeeId ?? '', () => []).add(info);
    }
    
    return map.entries.map((e) {
      final first = e.value.first;
      return CommissionSummary.fromDetails(
        e.key.isEmpty ? 'SemID' : e.key,
        first.employeeName ?? 'Desconhecido',
        first.employeeAvatar,
        e.value.map((v) => v.detail).toList(),
      );
    }).toList()
      ..sort((a, b) => b.totalCommission.compareTo(a.totalCommission));
  }
}

// Classe helper para guardar infomações conjuntas do profissional
class CommissionDetailWithEmployeeInfo {
  final CommissionDetail detail;
  final String? employeeId;
  final String? employeeName;
  final String? employeeAvatar;

  CommissionDetailWithEmployeeInfo({
    required this.detail,
    this.employeeId,
    this.employeeName,
    this.employeeAvatar,
  });
}
