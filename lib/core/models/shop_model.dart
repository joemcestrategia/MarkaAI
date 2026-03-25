class ShopModel {
  final String id;
  final String name;
  final String? slug;
  final String? ownerEmail;
  final String? phone;
  final String? whatsapp;
  final String? instagram;
  final String? tiktok;
  final String? youtube;
  final String? planId;
  final String? city;
  final String? state;
  final String? zipCode;
  final String? street;
  final String? number;
  final String? address;
  final String? imageUrl;
  final String? logoUrl;
  final String? description;
  final String? category;
  final String? niche;
  final String? neighborhood;
  final String? ownerId;
  final bool verified;
  final bool noFixedAddress;
  final String? complement;
  final double? lat;
  final double? lng;
  final Map<String, dynamic>? config;
  final Map<String, dynamic>? notificationSettings;
  final List<dynamic>? pendingHolidays;
  final Map<String, dynamic>? configuredHolidays;
  final List<dynamic>? customHolidays;
  final Map<String, dynamic>? mercadopago;
  final String? mpAccessToken;
  final Map<String, dynamic>? googleBusiness;

  ShopModel({
    required this.id,
    required this.name,
    this.slug,
    this.ownerEmail,
    this.phone,
    this.whatsapp,
    this.instagram,
    this.tiktok,
    this.youtube,
    this.planId,
    this.city,
    this.state,
    this.zipCode,
    this.street,
    this.number,
    this.address,
    this.imageUrl,
    this.logoUrl,
    this.description,
    this.category,
    this.niche,
    this.neighborhood,
    this.ownerId,
    this.verified = false,
    this.noFixedAddress = false,
    this.complement,
    this.lat,
    this.lng,
    this.config,
    this.notificationSettings,
    this.pendingHolidays,
    this.configuredHolidays,
    this.customHolidays,
    this.mercadopago,
    this.mpAccessToken,
    this.googleBusiness,
  });

  factory ShopModel.fromMap(Map<String, dynamic> map) {
    return ShopModel(
      id: map['id'] ?? '',
      name: map['name'] ?? '',
      slug: map['slug'],
      ownerEmail: map['email'],
      phone: map['phone'],
      whatsapp: map['whatsapp'],
      instagram: map['instagram'],
      tiktok: map['tiktok'],
      youtube: map['youtube'],
      planId: map['plan_id'],
      city: map['city'],
      state: map['state'],
      zipCode: map['zip_code'],
      street: map['street'],
      number: map['number'],
      address: map['address'],
      imageUrl: map['image_url'],
      logoUrl: map['logo_url'],
      description: map['description'],
      category: map['category'],
      niche: map['niche'],
      neighborhood: map['neighborhood'],
      ownerId: map['owner_id'],
      verified: map['verified'] ?? false,
      noFixedAddress: map['no_fixed_address'] ?? false,
      complement: map['complement'],
      lat: (map['lat'] != null) ? (map['lat'] as num).toDouble() : null,
      lng: (map['lng'] != null) ? (map['lng'] as num).toDouble() : null,
      config: map['config'],
      notificationSettings: map['notification_settings'],
      pendingHolidays: map['pending_holidays'] != null 
          ? List<dynamic>.from(map['pending_holidays']) 
          : null,
      configuredHolidays: map['configured_holidays'],
      customHolidays: map['custom_holidays'] != null 
          ? List<dynamic>.from(map['custom_holidays']) 
          : null,
      mercadopago: map['mercadopago'],
      mpAccessToken: map['mp_access_token'],
      googleBusiness: map['google_business'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'slug': slug,
      'email': ownerEmail,
      'phone': phone,
      'whatsapp': whatsapp,
      'instagram': instagram,
      'tiktok': tiktok,
      'youtube': youtube,
      'plan_id': planId,
      'city': city,
      'state': state,
      'zip_code': zipCode,
      'street': street,
      'number': number,
      'address': address,
      'image_url': imageUrl,
      'logo_url': logoUrl,
      'description': description,
      'category': category,
      'niche': niche,
      'neighborhood': neighborhood,
      'owner_id': ownerId,
      'verified': verified,
      'no_fixed_address': noFixedAddress,
      'complement': complement,
      'lat': lat,
      'lng': lng,
      'config': config,
      'notification_settings': notificationSettings,
      'pending_holidays': pendingHolidays,
      'configured_holidays': configuredHolidays,
      'custom_holidays': customHolidays,
      'mercadopago': mercadopago,
      'mp_access_token': mpAccessToken,
      'google_business': googleBusiness,
      'updated_at': DateTime.now().toIso8601String(),
    };
  }
}
