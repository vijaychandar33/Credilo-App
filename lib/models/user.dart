enum UserRole { businessOwner, businessOwnerReadOnly, owner, ownerReadOnly, manager, staff }

class User {
  final String id;
  final String name;
  final String? phone;
  final String? email;
  final UserRole? role;
  final DateTime? createdAt;

  User({
    required this.id,
    required this.name,
    this.phone,
    this.email,
    this.role,
    this.createdAt,
  });

  Map<String, dynamic> toJson() {
    String? roleToDbString(UserRole? role) {
      if (role == null) return null;
      final camelCase = role.toString().split('.').last;
      return camelCase.replaceAllMapped(
        RegExp(r'([A-Z])'),
        (match) => '_${match.group(1)!.toLowerCase()}',
      );
    }
    return {
      'id': id,
      'name': name,
      'phone': phone,
      'email': email,
      if (role != null) 'role': roleToDbString(role),
      if (createdAt != null) 'created_at': createdAt!.toIso8601String(),
    };
  }

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id']?.toString() ?? '',
      name: json['name'] ?? '',
      phone: json['phone'],
      email: json['email'],
      role: _roleFromJson(json['role']?.toString()),
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'])
          : null,
    );
  }

  static UserRole? _roleFromJson(String? roleStr) {
    if (roleStr == null || roleStr.isEmpty) return null;
    // Convert snake_case to camelCase
    String camelCase = roleStr
        .split('_')
        .map((word) => word.isEmpty
            ? word
            : word[0].toUpperCase() + word.substring(1).toLowerCase())
        .join();
    if (camelCase.isEmpty) return null;
    camelCase = camelCase[0].toLowerCase() + camelCase.substring(1);
    try {
      return UserRole.values.firstWhere(
        (e) => e.toString().split('.').last == camelCase,
      );
    } catch (_) {
      return UserRole.staff;
    }
  }
}

