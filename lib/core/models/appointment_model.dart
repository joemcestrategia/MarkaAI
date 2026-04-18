class AppointmentModel {
  final String? id;
  final String shopId;
  final String clientId;
  final String clientName;
  final String? clientPhone;
  final String? clientEmail;
  final String professionalId;
  final String professionalName;
  final String serviceId;
  final String serviceName;
  final DateTime scheduledAt;
  final String status;
  final String paymentMethod;
  final double totalValue;
  final double totalPrice;
  final int durationMin;
  final DateTime? createdAt;
  final String createdBy; // 'dono' ou 'cliente'

  AppointmentModel({
    this.id,
    required this.shopId,
    required this.clientId,
    required this.clientName,
    this.clientPhone,
    this.clientEmail,
    required this.professionalId,
    required this.professionalName,
    required this.serviceId,
    required this.serviceName,
    required this.scheduledAt,
    this.status = 'agendado',
    this.paymentMethod = 'No Local',
    required this.totalValue,
    required this.totalPrice,
    required this.durationMin,
    this.createdAt,
    required this.createdBy,
  });

  factory AppointmentModel.fromMap(Map<String, dynamic> map) {
    return AppointmentModel(
      id: map['id'],
      shopId: map['shop_id'] ?? '',
      clientId: map['client_id'] ?? '',
      clientName: map['client_name'] ?? '',
      clientPhone: map['client_phone'],
      clientEmail: map['client_email'],
      professionalId: map['professional_id'] ?? '',
      professionalName: map['professional_name'] ?? '',
      serviceId: map['service_id'] ?? '',
      serviceName: map['service_name'] ?? '',
      scheduledAt: DateTime.parse(map['scheduled_at']),
      status: map['status'] ?? 'agendado',
      paymentMethod: map['payment_method'] ?? 'No Local',
      totalValue: (map['total_value'] ?? map['total_price'] ?? 0).toDouble(),
      totalPrice: (map['total_price'] ?? map['total_value'] ?? 0).toDouble(),
      durationMin: map['duration_min'] ?? 30,
      createdAt: map['created_at'] != null ? DateTime.parse(map['created_at']) : null,
      createdBy: map['created_by'] ?? 'cliente',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'shop_id': shopId,
      'client_id': clientId,
      'client_name': clientName,
      'client_phone': clientPhone,
      'client_email': clientEmail,
      'professional_id': professionalId,
      'professional_name': professionalName,
      'service_id': serviceId,
      'service_name': serviceName,
      'scheduled_at': scheduledAt.toIso8601String(),
      'status': status,
      'payment_method': paymentMethod,
      'total_value': totalValue,
      'total_price': totalPrice,
      'duration_min': durationMin,
      'created_at': (createdAt ?? DateTime.now()).toIso8601String(),
      'created_by': createdBy,
    };
  }
}
