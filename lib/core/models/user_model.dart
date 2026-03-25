class UserModel {
  final String id;
  final String name;
  final String email;
  final String phone;
  final String role;
  final String? shopId;
  final String? plan;
  final bool isActive;
  final String? photoUrl;
  final String? birthDate; // ISO-8601 (YYYY-MM-DD)
  final String? city;
  final String? state; // Adicionado
  final String? neighborhood;
  final String? number;
  final String? street;
  final String? address; // Adicionado
  final bool verified;
  final String? zipCode;
  final String? documentCpf;
  final String? gender;
  final String? bio;

  UserModel({
    required this.id,
    required this.name,
    required this.email,
    required this.phone,
    required this.role,
    this.shopId,
    this.plan,
    this.isActive = true,
    this.photoUrl,
    this.birthDate,
    this.city,
    this.state,
    this.neighborhood,
    this.number,
    this.street,
    this.address,
    this.verified = false,
    this.zipCode,
    this.documentCpf,
    this.gender,
    this.bio,
  });

  factory UserModel.fromMap(Map<String, dynamic> map) {
    return UserModel(
      id: map['id'] ?? '',
      name: map['name'] ?? '',
      email: map['email'] ?? '',
      phone: map['phone'] ?? '',
      role: map['role'] ?? 'cliente',
      shopId: map['shop_id'],
      plan: map['plan'],
      isActive: map['is_active'] ?? true,
      photoUrl: map['photo_url'],
      birthDate: map['birth_date'],
      city: map['city'],
      state: map['state'],
      neighborhood: map['neighborhood'],
      number: map['number'],
      street: map['street'],
      address: map['address'],
      verified: map['verified'] ?? false,
      zipCode: map['zip_code'],
      documentCpf: map['document_cpf'],
      gender: map['gender'],
      bio: map['bio'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'email': email,
      'phone': phone,
      'role': role,
      'shop_id': shopId,
      'plan': plan,
      'is_active': isActive,
      'photo_url': photoUrl,
      'birth_date': birthDate,
      'city': city,
      'state': state,
      'neighborhood': neighborhood,
      'number': number,
      'street': street,
      'address': address,
      'verified': verified,
      'zip_code': zipCode,
      'document_cpf': documentCpf,
      'gender': gender,
      'bio': bio,
      'updated_at': DateTime.now().toIso8601String(),
    };
  }
}
