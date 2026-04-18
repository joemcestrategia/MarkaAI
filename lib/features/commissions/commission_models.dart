class CommissionSummary {
  final String professionalId;
  final String professionalName;
  final String? professionalAvatar;
  final int totalAppointments;
  final double totalRevenue;
  final double totalCommission;
  final double employeeCommissionPercent;
  final List<CommissionDetail> details;

  const CommissionSummary({
    required this.professionalId,
    required this.professionalName,
    this.professionalAvatar,
    required this.totalAppointments,
    required this.totalRevenue,
    required this.totalCommission,
    required this.employeeCommissionPercent,
    required this.details,
  });

  factory CommissionSummary.fromDetails(
    String professionalId,
    String professionalName,
    String? professionalAvatar,
    List<CommissionDetail> details,
  ) {
    return CommissionSummary(
      professionalId: professionalId,
      professionalName: professionalName,
      professionalAvatar: professionalAvatar,
      totalAppointments: details.length,
      totalRevenue: details.fold(0, (s, d) => s + d.servicePrice),
      totalCommission: details.fold(0, (s, d) => s + d.commissionAmount),
      employeeCommissionPercent: details.isNotEmpty ? details.first.employeeCommissionPercent : 0,
      details: details,
    );
  }
}

class CommissionDetail {
  final String appointmentId;
  final String serviceName;
  final double servicePrice;
  final String commissionType; // 'percentage' | 'fixed'
  final double commissionValue;
  final double commissionAmount;
  final double employeeCommissionPercent;
  final DateTime scheduledAt;

  const CommissionDetail({
    required this.appointmentId,
    required this.serviceName,
    required this.servicePrice,
    required this.commissionType,
    required this.commissionValue,
    required this.commissionAmount,
    required this.employeeCommissionPercent,
    required this.scheduledAt,
  });

  factory CommissionDetail.fromMap(Map<String, dynamic> map) {
    return CommissionDetail(
      appointmentId: map['appointment_id'] ?? '',
      serviceName: map['service_name'] ?? '',
      servicePrice: (map['service_price'] ?? 0).toDouble(),
      commissionType: map['commission_type'] ?? 'percentage',
      commissionValue: (map['commission_value'] ?? 0).toDouble(),
      commissionAmount: (map['commission_amount'] ?? 0).toDouble(),
      employeeCommissionPercent: (map['employee_commission_percent'] ?? 0).toDouble(),
      scheduledAt: DateTime.parse(map['scheduled_at']),
    );
  }
}
