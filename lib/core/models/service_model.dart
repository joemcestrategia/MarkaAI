class ServiceModel {
  final String? id;
  final String shopId;
  final String name;
  final String? description;
  final double price;
  final double cost;
  final int durationMin;
  final bool isActive;
  final List<String> photosUrls;
  final List<String> categoryIds;
  final List<Map<String, dynamic>> variations;
  final bool requiresWarning;
  final String? warningMessage;
  final DateTime? updatedAt;

  ServiceModel({
    this.id,
    required this.shopId,
    required this.name,
    this.description,
    required this.price,
    this.cost = 0.0,
    required this.durationMin,
    this.isActive = true,
    this.photosUrls = const [],
    this.categoryIds = const [],
    this.variations = const [],
    this.requiresWarning = false,
    this.warningMessage,
    this.updatedAt,
  });

  factory ServiceModel.fromMap(Map<String, dynamic> map) {
    return ServiceModel(
      id: map['id'],
      shopId: map['shop_id'] ?? '',
      name: map['name'] ?? '',
      description: map['description'],
      price: (map['price'] ?? 0).toDouble(),
      cost: (map['cost'] ?? 0).toDouble(),
      durationMin: map['duration_min'] ?? 30,
      isActive: map['is_active'] ?? true,
      photosUrls: List<String>.from(map['photos_urls'] ?? []),
      categoryIds: List<String>.from(map['category_ids'] ?? []),
      variations: List<Map<String, dynamic>>.from(map['variations'] ?? []),
      requiresWarning: map['requires_warning'] ?? false,
      warningMessage: map['warning_message'],
      updatedAt: map['updated_at'] != null ? DateTime.parse(map['updated_at']) : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'shop_id': shopId,
      'name': name,
      'description': description,
      'price': price,
      'cost': cost,
      'duration_min': durationMin,
      'is_active': isActive,
      'photos_urls': photosUrls,
      'category_ids': categoryIds,
      'variations': variations,
      'requires_warning': requiresWarning,
      'warning_message': warningMessage,
      'updated_at': (updatedAt ?? DateTime.now()).toIso8601String(),
    };
  }
}
