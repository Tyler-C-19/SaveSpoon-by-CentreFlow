class AuthUser {
  const AuthUser({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
    this.phone,
    this.hasVendorProfile = false,
  });

  factory AuthUser.fromJson(Map<String, dynamic> json) => AuthUser(
    id: json['_id'] as String,
    name: json['name'] as String,
    email: json['email'] as String,
    role: json['role'] as String,
    phone: json['phone'] as String?,
    hasVendorProfile: json['hasVendorProfile'] as bool? ?? false,
  );

  final String id;
  final String name;
  final String email;
  final String role;
  final String? phone;
  final bool hasVendorProfile;

  bool get canUseMobileApp => role == 'customer' || role == 'vendor';

  bool get needsVendorSetup => role == 'vendor' && !hasVendorProfile;

  AuthUser withVendorProfile() => AuthUser(
    id: id,
    name: name,
    email: email,
    role: role,
    phone: phone,
    hasVendorProfile: true,
  );

  Map<String, dynamic> toJson() => {
    '_id': id,
    'name': name,
    'email': email,
    'role': role,
    'phone': phone,
    'hasVendorProfile': hasVendorProfile,
  };
}
